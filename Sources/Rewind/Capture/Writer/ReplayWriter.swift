@preconcurrency import AVFoundation
import CoreGraphics
import RewindObjCSupport

/// Encodes captured video/audio/mic sample buffers into a single `.mov` segment
/// via `AVAssetWriter`. All state is confined to a single serial queue; the
/// public `append*` entry points hop onto it, and the pipeline is split across
/// `ReplayWriter+Video`, `+Audio`, and `+Session`.
final class ReplayWriter: @unchecked Sendable {
    enum VideoMode {
        case pixelBufferEncode
        case passthrough
    }

    enum Constants {
        static let maxPendingAudioSamples = 240
        static let maxPendingVideoSamples = 120
        /// Sized to cover `audioBufferingWindow` even at 4K120 (~24 frames, ~300 MB),
        /// which is what the queue exists for, while keeping the ceiling far below
        /// the ~1.5 GB a bare 120-frame cap allowed at 4K.
        static let maxPendingVideoBytes = 320 * 1_024 * 1_024
        /// Audio samples are tiny; this only guards against a pathological backlog.
        static let maxPendingAudioBytes = 16 * 1_024 * 1_024
        static let audioJitterTolerance = CMTime(seconds: 0.005, preferredTimescale: 1_000)
        static let maxAudioPTSAdjustment = CMTime(seconds: 0.25, preferredTimescale: 600)
        static let audioBufferingWindow = CMTime(seconds: 0.20, preferredTimescale: 600)
        static let audioSyncTolerance = CMTime(seconds: 0.02, preferredTimescale: 48_000)
        static let videoSyncTolerance = CMTime(seconds: 0.02, preferredTimescale: 600)
        static let audioGapThreshold = CMTime(seconds: 0.04, preferredTimescale: 1_000)
        static let maxGapSeconds: Double = 0.5
        static let silenceChunkSeconds: Double = 0.1
        static let backpressureLogInterval = 30
        static let pendingVideoDropLogInterval = 60
        static let pendingAudioDropLogInterval = 50
        static let missingAdaptorLogLimit = 1
        static let finishWritingTimeout: TimeInterval = 10.0
        static let defaultFrameRate = 60
    }

    // - Queue ---

    let queue: DispatchQueue
    let queueKey = DispatchSpecificKey<Void>()

    // - Writer ---

    var writer: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var videoAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    var audioInput: AVAssetWriterInput?
    var micInput: AVAssetWriterInput?
    var micConverter: MicrophoneConverter?
    var outputURL: URL?

    // - Configuration ---

    var configuredVideoSize: CGSize?
    var configuredAudioSettings: [String: Any]?
    var configuredVideoMode: VideoMode = .pixelBufferEncode
    var configuredQuality: QualityPreset = .default
    var configuredVideoCodec: CaptureVideoCodec = .default
    var configuredFrameRate = Constants.defaultFrameRate
    var configuredRecordMicrophone = false
    var includeAudio = false

    // - Session ---

    var acceptsMediaData = false
    var sessionStarted = false
    var sessionStartPTS = CMTime.invalid
    var videoPTSOffset = CMTime.zero
    var audioPTSOffsetValid = false
    var audioBufferingEndPTS = CMTime.invalid
    var lastVideoPTS = CMTime.invalid
    var lastAudioEndPTS = CMTime.invalid
    var lastMicEndPTS = CMTime.invalid
    var reconfigureCount = 0

    /// First seen PTS on each stream, used to align audio and video at session start.
    var firstAudioPTS = CMTime.invalid
    var firstVideoPTS = CMTime.invalid

    // - Pending buffers ---

    /// Buffered until the writer session starts (or an input becomes ready) so
    /// leading samples aren't lost.
    var pendingVideo = PendingSampleQueue(
        capacity: Constants.maxPendingVideoSamples,
        byteBudget: Constants.maxPendingVideoBytes, label: "ReplayWriter.appendVideo",
        logInterval: Constants.pendingVideoDropLogInterval)
    var pendingAudio = PendingSampleQueue(
        capacity: Constants.maxPendingAudioSamples,
        byteBudget: Constants.maxPendingAudioBytes, label: "ReplayWriter.appendAudio",
        logInterval: Constants.pendingAudioDropLogInterval)
    var pendingMic = PendingSampleQueue(
        capacity: Constants.maxPendingAudioSamples,
        byteBudget: Constants.maxPendingAudioBytes, label: "ReplayWriter.appendMic",
        logInterval: Constants.pendingAudioDropLogInterval)

    // - Audio format ---

    var audioSampleRate: Double?
    var audioFormatDescription: CMAudioFormatDescription?
    var audioASBD: AudioStreamBasicDescription?

    // - One-shot log guards ---

    var loggedFirstVideoBuffer = false
    var loggedFirstAudioBuffer = false
    var loggedFirstMicBuffer = false
    var droppedNonLPCMMicLogged = false
    var loggedNoPixelBufferFormat = false
    var missingAdaptorDrops = 0
    var missingAudioInputLogged = false
    var videoBackpressureDrops = 0

    init(queue: DispatchQueue) {
        self.queue = queue
        self.queue.setSpecific(key: queueKey, value: ())
    }

    // - Configuration ---

    func configure(
        outputURL: URL,
        videoSize: CGSize,
        includeAudio: Bool,
        audioSettings: [String: Any]?,
        videoMode: VideoMode = .pixelBufferEncode,
        quality: QualityPreset = .default,
        frameRate: Int = Constants.defaultFrameRate,
        recordMicrophone: Bool = false,
        videoCodec: CaptureVideoCodec = .default
    ) throws {
        var configureError: Error?
        syncOnQueue {
            do {
                try configureOnQueue(
                    outputURL: outputURL,
                    videoSize: videoSize,
                    includeAudio: includeAudio,
                    audioSettings: audioSettings,
                    videoMode: videoMode,
                    quality: quality,
                    frameRate: frameRate,
                    recordMicrophone: recordMicrophone,
                    videoCodec: videoCodec
                )
            } catch {
                configureError = error
            }
        }

        if let configureError { throw configureError }
    }

    func configureOnQueue(
        outputURL: URL,
        videoSize: CGSize,
        includeAudio: Bool,
        audioSettings: [String: Any]?,
        videoMode: VideoMode,
        quality: QualityPreset,
        frameRate: Int,
        recordMicrophone: Bool,
        videoCodec: CaptureVideoCodec
    ) throws {
        guard outputURL.isFileURL else {
            throw CaptureError.exportFailed
        }
        let folder = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        var videoInput: AVAssetWriterInput!
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        var configuredSize: CGSize?
        var audioInput: AVAssetWriterInput?
        var micAudio: AVAssetWriterInput?
        var configError: CaptureError?
        do {
            try RewindExceptionCatcher.catchException {
                if videoMode == .pixelBufferEncode {
                    let width = Int(videoSize.width.rounded())
                    let height = Int(videoSize.height.rounded())
                    AppLog.debug(.writer, "ReplayWriter.configure video size:", width, "x", height)
                    configuredSize = CGSize(width: width, height: height)

                    let estimatedBitrate = VideoEncoderSettings.targetBitrateMbps(
                        for: quality, videoSize: CGSize(width: width, height: height),
                        frameRate: frameRate)
                    AppLog.debug(
                        .writer, "ReplayWriter.configure codec:", videoCodec.id,
                        "preset:", quality.label,
                        "target bitrate:", String(format: "%.1f", estimatedBitrate), "Mbps")

                    let videoSettings = VideoEncoderSettings.outputSettings(
                        quality: quality, width: width, height: height, frameRate: frameRate,
                        codec: videoCodec)
                    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)

                    let adaptorAttrs: [String: Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(
                            VideoEncoderSettings.sourcePixelFormat(for: quality)),
                        kCVPixelBufferWidthKey as String: width,
                        kCVPixelBufferHeightKey as String: height,
                        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                    ]
                    adaptor = AVAssetWriterInputPixelBufferAdaptor(
                        assetWriterInput: input, sourcePixelBufferAttributes: adaptorAttrs)
                    input.expectsMediaDataInRealTime = true
                    videoInput = input
                } else {
                    AppLog.debug(.writer, "ReplayWriter.configure video mode: passthrough")
                    let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
                    input.expectsMediaDataInRealTime = true
                    videoInput = input
                }

                guard writer.canAdd(videoInput) else {
                    configError = .exportFailed
                    return
                }
                writer.add(videoInput)

                if includeAudio {
                    let primaryAudio = AVAssetWriterInput(
                        mediaType: .audio, outputSettings: audioSettings)
                    primaryAudio.expectsMediaDataInRealTime = true
                    if writer.canAdd(primaryAudio) {
                        writer.add(primaryAudio)
                        audioInput = primaryAudio
                    } else {
                        AppLog.debug(
                            .writer, "ReplayWriter.configure: cannot add audio input with settings:",
                            audioSettings ?? [:])
                    }
                }

                // the microphone is an independent track: it must be available even
                // when desktop audio is off, so it isnt nested under includeAudio
                if recordMicrophone {
                    let mic = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                    mic.expectsMediaDataInRealTime = true
                    if writer.canAdd(mic) {
                        writer.add(mic)
                        micAudio = mic
                    }
                }
            }
        } catch {
            AppLog.error(
                .writer,
                "ReplayWriter.configure caught encoder exception; aborting writer setup",
                error: error)
            throw CaptureError.exportFailed
        }

        if let configError { throw configError }

        self.writer = writer
        self.videoInput = videoInput
        self.videoAdaptor = adaptor
        self.audioInput = audioInput
        self.micInput = micAudio
        self.outputURL = outputURL
        self.configuredVideoSize = configuredSize
        self.configuredAudioSettings = audioSettings
        self.configuredVideoMode = videoMode
        self.configuredQuality = quality
        self.configuredVideoCodec = videoCodec
        self.configuredFrameRate = frameRate
        self.configuredRecordMicrophone = recordMicrophone
        self.includeAudio = includeAudio

        resetRuntimeState(resetReconfigureCount: true)
        micConverter = micAudio != nil ? MicrophoneConverter(audioSettings: audioSettings) : nil
        acceptsMediaData = true
    }

    func resetRuntimeState(resetReconfigureCount: Bool) {
        acceptsMediaData = false
        sessionStarted = false
        sessionStartPTS = CMTime.invalid
        videoPTSOffset = .zero
        audioPTSOffsetValid = false
        audioBufferingEndPTS = CMTime.invalid
        lastVideoPTS = CMTime.invalid
        lastAudioEndPTS = CMTime.invalid
        lastMicEndPTS = CMTime.invalid
        loggedFirstVideoBuffer = false
        loggedFirstAudioBuffer = false
        loggedFirstMicBuffer = false
        droppedNonLPCMMicLogged = false
        loggedNoPixelBufferFormat = false
        missingAdaptorDrops = 0
        missingAudioInputLogged = false
        audioSampleRate = nil
        audioFormatDescription = nil
        audioASBD = nil
        videoBackpressureDrops = 0
        pendingVideo.removeAll()
        pendingAudio.removeAll()
        pendingMic.removeAll()
        firstAudioPTS = CMTime.invalid
        firstVideoPTS = CMTime.invalid
        if resetReconfigureCount {
            reconfigureCount = 0
        }
    }

    func resetState() {
        writer = nil
        videoInput = nil
        videoAdaptor = nil
        audioInput = nil
        micInput = nil
        micConverter = nil
        outputURL = nil
        configuredVideoSize = nil
        configuredAudioSettings = nil
        configuredVideoMode = .pixelBufferEncode
        configuredQuality = .default
        configuredVideoCodec = .default
        configuredFrameRate = Constants.defaultFrameRate
        includeAudio = false
        resetRuntimeState(resetReconfigureCount: false)
    }

    // - Queue helpers ---

    func onQueue(_ block: @escaping @Sendable () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            block()
        } else {
            queue.async(execute: block)
        }
    }

    func syncOnQueue(_ block: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            block()
        } else {
            queue.sync(execute: block)
        }
    }
}
