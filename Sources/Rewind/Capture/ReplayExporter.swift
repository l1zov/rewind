@preconcurrency import AVFoundation
import Foundation

/// Stitches buffered replay segments into a single composition and exports the
/// requested trailing `seconds` as a passthrough clip in the chosen container.
struct ReplayExporter {
    func export(
        segments: [ReplaySegment],
        seconds: TimeInterval,
        container: CaptureContainer,
        audioMix: ExportAudioMix = .unity
    ) async throws -> URL {
        guard !segments.isEmpty else { throw CaptureError.noFramesCaptured }

        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        var audioTracks: [AVMutableCompositionTrack] = []

        var cursor = CMTime.zero
        var appliedTransform = false
        for segment in segments {
            let asset = AVURLAsset(url: segment.url)
            _ = try await asset.load(.tracks)
            let assetDuration = try await asset.load(.duration)

            let sourceVideo = try await asset.loadTracks(withMediaType: .video).first
            let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)

            while audioTracks.count < sourceAudioTracks.count {
                if let newTrack = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                {
                    audioTracks.append(newTrack)
                } else {
                    break
                }
            }

            var videoTimeRange: CMTimeRange? = nil
            if let sourceVideo, let videoTrack {
                let tr = try await sourceVideo.load(.timeRange)
                if tr.duration.isValid && tr.duration > .zero {
                    videoTimeRange = tr
                    try videoTrack.insertTimeRange(tr, of: sourceVideo, at: cursor)
                    if !appliedTransform {
                        let transform = try await sourceVideo.load(.preferredTransform)
                        videoTrack.preferredTransform = transform
                        appliedTransform = true
                    }
                }
            }

            for (index, sourceAudio) in sourceAudioTracks.enumerated() {
                if index < audioTracks.count {
                    let audioTR = try await sourceAudio.load(.timeRange)
                    let insertTR: CMTimeRange
                    if let videoTimeRange {
                        let audioStart = max(audioTR.start, videoTimeRange.start)
                        let audioEnd = min(audioTR.end, videoTimeRange.end)
                        let dur = audioEnd > audioStart ? CMTimeSubtract(audioEnd, audioStart) : videoTimeRange.duration
                        insertTR = CMTimeRange(start: audioStart, duration: dur)
                    } else {
                        insertTR = audioTR
                    }
                    if insertTR.duration.isValid && insertTR.duration > .zero {
                        try audioTracks[index].insertTimeRange(insertTR, of: sourceAudio, at: cursor)
                    }
                }
            }

            let stepDuration = videoTimeRange?.duration ?? assetDuration
            if stepDuration.isValid && stepDuration > .zero {
                cursor = cursor + stepDuration
            }
        }

        let totalSeconds = cursor.seconds
        guard totalSeconds.isFinite, totalSeconds > 0 else {
            throw CaptureError.noFramesCaptured
        }
        let clipSeconds = max(0, min(seconds, totalSeconds))
        guard clipSeconds > 0 else {
            throw CaptureError.noFramesCaptured
        }
        let timescale = cursor.timescale == 0 ? CMTimeScale(600) : cursor.timescale
        let startTime = CMTime(
            seconds: max(totalSeconds - clipSeconds, 0), preferredTimescale: timescale)
        let timeRange = CMTimeRange(
            start: startTime, duration: CMTime(seconds: clipSeconds, preferredTimescale: timescale))

        let folder = ClipStorageLocation.current()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let exportURL = folder.appendingPathComponent(
            "Rewind_\(UUID().uuidString).\(container.fileExtension)")
        try? FileManager.default.removeItem(at: exportURL)

        do {
            let reconciledMix = audioMix.reconciled(trackCount: audioTracks.count)
            if reconciledMix != audioMix {
                AppLog.error(
                    .capture,
                    "Audio roles (\(audioMix.roles.count)) don't match recorded tracks (\(audioTracks.count)); using unity gain")
            }
            if reconciledMix.needsMixdown(trackCount: audioTracks.count) {
                return try await exportWithMixdown(
                    asset: composition,
                    timeRange: timeRange,
                    outputURL: exportURL,
                    container: container,
                    audioMix: reconciledMix
                )
            }
            return try await exportWithPassthrough(
                asset: composition,
                timeRange: timeRange,
                outputURL: exportURL,
                container: container
            )
        } catch {
            try? FileManager.default.removeItem(at: exportURL)
            throw error
        }
    }

    private func exportWithPassthrough(
        asset: AVAsset,
        timeRange: CMTimeRange,
        outputURL: URL,
        container: CaptureContainer
    ) async throws -> URL {
        guard
            let exportSession = AVAssetExportSession(
                asset: asset, presetName: AVAssetExportPresetPassthrough)
        else {
            throw CaptureError.exportFailed
        }

        guard exportSession.supportedFileTypes.contains(container.avFileType) else {
            throw CaptureError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = container.avFileType
        exportSession.timeRange = timeRange
        // Puts the index (moov) at the front so players can start before the
        // whole file is available; Discord's inline preview relies on this.
        exportSession.shouldOptimizeForNetworkUse = true

        let session = UncheckedSendable(exportSession)
        return try await withCheckedThrowingContinuation { continuation in
            session.value.exportAsynchronously {
                switch session.value.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed, .cancelled:
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(throwing: session.value.error ?? CaptureError.exportFailed)
                default:
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(throwing: CaptureError.exportFailed)
                }
            }
        }
    }

    // - Mixdown ---

    private static var mixdownPCMSettings: [String: Any] { [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ] }

    private static var mixdownAACSettings: [String: Any] { [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 192_000,
    ] }

    /// Copies the video untouched (no re-encode) and folds every audio track into a
    /// single AAC track, applying the per-source volume.
    private func exportWithMixdown(
        asset: AVAsset,
        timeRange: CMTimeRange,
        outputURL: URL,
        container: CaptureContainer,
        audioMix: ExportAudioMix
    ) async throws -> URL {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let videoTrack = videoTracks.first, !audioTracks.isEmpty else {
            throw CaptureError.exportFailed
        }

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw CaptureError.exportFailed }
        reader.add(videoOutput)

        let mix = AVMutableAudioMix()
        mix.inputParameters = audioTracks.enumerated().map { index, track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(audioMix.volume(forTrack: index), at: .zero)
            return parameters
        }
        let audioOutput = AVAssetReaderAudioMixOutput(
            audioTracks: audioTracks, audioSettings: Self.mixdownPCMSettings)
        audioOutput.audioMix = mix
        guard reader.canAdd(audioOutput) else { throw CaptureError.exportFailed }
        reader.add(audioOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: container.avFileType)
        writer.shouldOptimizeForNetworkUse = true

        let formatHint = try await videoTrack.load(.formatDescriptions).first
        let videoInput = AVAssetWriterInput(
            mediaType: .video, outputSettings: nil, sourceFormatHint: formatHint)
        videoInput.transform = try await videoTrack.load(.preferredTransform)
        videoInput.expectsMediaDataInRealTime = false
        let audioInput = AVAssetWriterInput(
            mediaType: .audio, outputSettings: Self.mixdownAACSettings)
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw CaptureError.exportFailed
        }
        writer.add(videoInput)
        writer.add(audioInput)

        guard reader.startReading() else { throw reader.error ?? CaptureError.exportFailed }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? CaptureError.exportFailed
        }
        writer.startSession(atSourceTime: timeRange.start)

        async let videoDone: Void = Self.pump(
            output: videoOutput, into: videoInput, writer: writer, label: "rewind.export.video")
        async let audioDone: Void = Self.pump(
            output: audioOutput, into: audioInput, writer: writer, label: "rewind.export.audio")
        _ = await (videoDone, audioDone)

        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? CaptureError.exportFailed
        }
        // finishWriting on a writer that is no longer `.writing` (disk full, encoder
        // error) raises an uncatchable NSInternalInconsistencyException.
        guard writer.status == .writing else {
            reader.cancelReading()
            let error = writer.error ?? CaptureError.exportFailed
            writer.cancelWriting()
            throw error
        }

        let finishingWriter = UncheckedSendable(writer)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishingWriter.value.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? CaptureError.exportFailed
        }
        return outputURL
    }

    /// Feeds every sample from `output` into `input`, then marks the input finished.
    private static func pump(
        output: AVAssetReaderOutput, into input: AVAssetWriterInput, writer: AVAssetWriter,
        label: String
    ) async {
        let queue = DispatchQueue(label: label)
        let pair = UncheckedSendable((output, input, writer))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finished = Locked(false)
            input.requestMediaDataWhenReady(on: queue) {
                let (output, input, writer) = pair.value
                while input.isReadyForMoreMediaData {
                    // Stop as soon as the writer has failed or been cancelled (by the other
                    // input's pump, say) so neither loop waits on a dead writer.
                    guard writer.status == .writing,
                          let sample = output.copyNextSampleBuffer(), input.append(sample)
                    else {
                        input.markAsFinished()
                        if finished.exchange(true) == false { continuation.resume() }
                        return
                    }
                }
            }
        }
    }
}

/// Minimal lock-protected value, used to make a continuation resume exactly once.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func exchange(_ newValue: Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }
}
