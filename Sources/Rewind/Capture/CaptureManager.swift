@preconcurrency import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit

actor CaptureManager {
    private enum Constants {
        static let rotationFrameDelayNanos: UInt64 = 50_000_000
        static let fileReadyAttempts = 10
        static let fileReadyDelayNanos: UInt64 = 50_000_000
        static let nanosPerSecond: Double = 1_000_000_000
        /// Consecutive rotation failures (other than an empty segment) tolerated
        /// before the capture is treated as broken and stopped.
        static let maxConsecutiveRotationFailures = 3
    }

    private let screenCapture: CaptureSource
    private let captureQueue: DispatchQueue
    private let writerQueue: DispatchQueue
    private let makeWriter: @Sendable () -> SegmentWriter
    /// Validates a finished segment file and returns its duration.
    private let inspectSegment: @Sendable (URL) async throws -> TimeInterval
    /// active writer receiving samples (accessed via nonisolated helper for callbacks)
    private var activeWriter: SegmentWriter
    /// standby writer pre-configured for instant switchover
    private var standbyWriter: SegmentWriter?
    /// Serializes start/stop/failure teardown. Actor methods interleave at every
    /// `await`, so without this a restart's `start()` could run while the previous
    /// `stop()` was still suspended (and no-op), or two starts could each create a
    /// capture stream.
    private let lifecycle = AsyncMutex()
    /// Serializes segment rotation (timer and save) so two rotations never
    /// overlap and finished segments reach the buffer in order.
    private let rotation = AsyncMutex()
    private var consecutiveRotationFailures = 0
    private let replayBuffer = ReplayBuffer()
    private let exporter = ReplayExporter()
    private var isRunning = false
    private var isSaving = false
    private var rotationTask: Task<Void, Never>?
    private let segmentDuration: TimeInterval
    private let maxBufferDuration: TimeInterval = 300
    private var currentQuality: QualityPreset = .default
    private var currentFrameRate: Int = CaptureFrameRate.default.framesPerSecond
    private var currentAudioCodec: CaptureAudioCodec = .default
    private var currentVideoCodec: CaptureVideoCodec = .default
    private var recordMicrophoneEnabled: Bool = false
    private var recordDesktopAudioEnabled: Bool = true
    private var onCaptureInterrupted: (@MainActor (Error) -> Void)?

    /// thread-safe reference to current writer for use in callbacks
    /// sses lock-based synchronization so it can be safely accessed from nonisolated contexts
    private let currentWriterLock = NSLock()
    private nonisolated(unsafe) var _currentWriter: SegmentWriter?
    private nonisolated var currentWriter: SegmentWriter? {
        get {
            currentWriterLock.withLock { _currentWriter }
        }
        set {
            currentWriterLock.withLock { _currentWriter = newValue }
        }
    }

    /// The defaults build the real ScreenCaptureKit/AVAssetWriter pipeline; tests
    /// pass fakes (and a short `segmentDuration`) through the parameters.
    init(
        captureSource: CaptureSource? = nil,
        makeWriter: (@Sendable (DispatchQueue) -> SegmentWriter)? = nil,
        inspectSegment: (@Sendable (URL) async throws -> TimeInterval)? = nil,
        segmentDuration: TimeInterval = 10
    ) {
        // sse userInteractive QoS for real-time capture processing
        let queue = DispatchQueue(label: "rewind.capture.samples", qos: .userInteractive)
        captureQueue = queue
        let audioQueue = DispatchQueue(label: "rewind.capture.audio", qos: .userInteractive)
        // dedicated writer queue keeps encoding work off the capture callback queue.
        let writerQueue = DispatchQueue(label: "rewind.capture.writer", qos: .userInitiated)
        self.writerQueue = writerQueue
        screenCapture = captureSource ?? ScreenCaptureService(sampleQueue: queue, audioQueue: audioQueue)
        let writerFactory = makeWriter ?? { ReplayWriter(queue: $0) }
        self.makeWriter = { writerFactory(writerQueue) }
        self.inspectSegment = inspectSegment ?? Self.inspectSegmentFile
        self.segmentDuration = segmentDuration
        activeWriter = writerFactory(writerQueue)
        screenCapture.onCaptureStopped = { [weak self] reason in
            guard let self else { return }
            // Only plain values cross into the task: the framework's error object
            // may already be freed by the time this runs.
            let error = CaptureError.streamStopped(reason: reason)
            Task {
                await self.handleCaptureFailure(error, label: "Capture stream stopped")
            }
        }
    }

    func setOnCaptureInterruptedHandler(_ handler: (@MainActor (Error) -> Void)?) {
        onCaptureInterrupted = handler
    }

    func start(
        contentFilter: UncheckedSendable<SCContentFilter>? = nil,
        resolution: CaptureResolution? = nil,
        quality: QualityPreset = .default,
        frameRate: Int = CaptureFrameRate.default.framesPerSecond,
        audioCodec: CaptureAudioCodec = .default,
        videoCodec: CaptureVideoCodec = .default,
        recordMicrophoneEnabled: Bool = false,
        recordDesktopAudioEnabled: Bool = true,
        microphoneDeviceID: String? = nil
    ) async throws {
        try await lifecycle.withLock {
            try await startLocked(
                contentFilter: contentFilter, resolution: resolution, quality: quality,
                frameRate: frameRate, audioCodec: audioCodec, videoCodec: videoCodec,
                recordMicrophoneEnabled: recordMicrophoneEnabled,
                recordDesktopAudioEnabled: recordDesktopAudioEnabled,
                microphoneDeviceID: microphoneDeviceID)
        }
    }

    private func startLocked(
        contentFilter: UncheckedSendable<SCContentFilter>?,
        resolution: CaptureResolution?,
        quality: QualityPreset,
        frameRate: Int,
        audioCodec: CaptureAudioCodec,
        videoCodec: CaptureVideoCodec,
        recordMicrophoneEnabled: Bool,
        recordDesktopAudioEnabled: Bool,
        microphoneDeviceID: String?
    ) async throws {
        guard !isRunning else { return }
        consecutiveRotationFailures = 0
        currentQuality = quality
        currentFrameRate = frameRate
        currentAudioCodec = audioCodec
        currentVideoCodec = videoCodec
        self.recordMicrophoneEnabled = recordMicrophoneEnabled
        self.recordDesktopAudioEnabled = recordDesktopAudioEnabled


        do {
            try await screenCapture.startCapture(
                contentFilter: contentFilter,
                resolution: resolution,
                quality: quality,
                frameRate: frameRate,
                recordMicrophone: recordMicrophoneEnabled,
                recordDesktopAudio: recordDesktopAudioEnabled,
                microphoneDeviceID: microphoneDeviceID
            )
            try configureActiveWriter()
            currentWriter = activeWriter
            screenCapture.onVideoSampleBuffer = { [weak self] sampleBuffer in
                self?.currentWriter?.appendVideo(sampleBuffer)
            }
            screenCapture.onAudioSampleBuffer = { [weak self] sampleBuffer in
                self?.currentWriter?.appendAudio(sampleBuffer)
            }
            screenCapture.onMicSampleBuffer = { [weak self] sampleBuffer in
                self?.currentWriter?.appendMic(sampleBuffer)
            }
            isRunning = true
            prepareStandbyWriter()
            startRotationLoop()
        } catch {
            await resetCaptureState()
            throw error
        }
    }

    func stop() async {
        await lifecycle.withLock {
            guard isRunning else { return }
            await stopCapturePipeline()
        }
    }

    /// Whether capture is currently running. Exposed for tests and diagnostics.
    func isCaptureRunning() -> Bool { isRunning }

    /// URLs of the finished segments currently held in the replay buffer, oldest first.
    func bufferedSegmentURLs() async -> [URL] {
        await replayBuffer.segmentURLs()
    }

    func saveReplay(
        seconds: TimeInterval,
        container: CaptureContainer = .default,
        desktopAudioVolume: Double = 1,
        microphoneVolume: Double = 1
    ) async throws -> URL {
        guard isRunning else { throw CaptureError.noFramesCaptured }
        guard !isSaving else { throw CaptureError.saveInProgress }
        isSaving = true
        defer { isSaving = false }

        AppLog.info(.capture, "Save replay start. seconds:", seconds)


        // Rotating, validating and buffering the finished segment happens as one
        // serialized step, so a save that lands next to a timer rotation can't
        // interleave with it.
        do {
            try await rotateForSave()
        } catch {
            Self.logError("Replay rotation failed", error)
            throw error
        }

        var segmentsToUnlock: [ReplaySegment] = []
        do {
            let segments = await replayBuffer.latestSegments(totalDuration: seconds)
            segmentsToUnlock = segments

            // Mic and desktop audio are recorded as separate tracks; the clip folds
            // them into one so every player (Discord included) plays both.
            let audioMix = ExportAudioMix(
                roles: ExportAudioMix.roles(
                    desktop: recordDesktopAudioEnabled, microphone: recordMicrophoneEnabled),
                desktopVolume: desktopAudioVolume,
                microphoneVolume: microphoneVolume)
            let exportURL = try await exporter.export(
                segments: segments, seconds: seconds, container: container, audioMix: audioMix)

            await replayBuffer.unlockSegments(segmentsToUnlock)
            AppLog.info(.capture, "Save replay success:", exportURL.lastPathComponent)
            return exportURL
        } catch {
            // Always unlock segments on failure
            if !segmentsToUnlock.isEmpty {
                await replayBuffer.unlockSegments(segmentsToUnlock)
            }
            Self.logError("Export failed", error)
            throw error
        }
    }

    /// configures the active writer with a new output file
    private func configureActiveWriter() throws {
        guard let size = screenCapture.displaySize else {
            throw CaptureError.noDisplay
        }
        let outputURL = makeSegmentURL()
        try activeWriter.configureSegment(
            outputURL: outputURL,
            videoSize: size,
            includeAudio: recordDesktopAudioEnabled,
            audioSettings: captureAudioSettings,
            quality: currentQuality,
            frameRate: currentFrameRate,
            recordMicrophone: recordMicrophoneEnabled,
            videoCodec: currentVideoCodec
        )
    }

    /// pre-configures the standby writer for instant switchover
    private func prepareStandbyWriter() {
        guard let size = screenCapture.displaySize else { return }
        let writer = makeWriter()
        let outputURL = makeSegmentURL()
        do {
            try writer.configureSegment(
                outputURL: outputURL,
                videoSize: size,
                includeAudio: recordDesktopAudioEnabled,
                audioSettings: captureAudioSettings,
                quality: currentQuality,
                frameRate: currentFrameRate,
                recordMicrophone: recordMicrophoneEnabled,
                videoCodec: currentVideoCodec
            )
            standbyWriter = writer
        } catch {
            Self.logError("Failed to prepare standby writer", error)
            standbyWriter = nil
        }
    }

    /// seamlessly rotates to the standby writer and returns the finished segment URL.
    private func rotateWriterSeamlessly() async throws -> URL {
        // ensure standby is ready, or prepare it now
        if standbyWriter == nil {
            prepareStandbyWriter()
        }
        guard let newWriter = standbyWriter else {
            throw CaptureError.writerUnavailable
        }

        let oldWriter = activeWriter

        #if arch(x86_64)
            currentWriter = nil
            // Install the new writer whether or not the old segment turned out to
            // be usable (an empty segment throws): otherwise frames keep going to
            // a finished writer and capture is dead until the failure limit trips.
            let finishResult: Result<URL, Error>
            do {
                finishResult = .success(try await oldWriter.finishWriting())
            } catch {
                finishResult = .failure(error)
            }

            activeWriter = newWriter
            standbyWriter = nil
            currentWriter = newWriter
            prepareStandbyWriter()
            return try finishResult.get()
        #else
        // callbacks will pick up new writer
        activeWriter = newWriter
        standbyWriter = nil

        // update currentWriter atomically; this is what callbacks use
        currentWriter = newWriter

        // small delay to ensure the new writer receives at least one frame
        // before we finish the old writer (prevents black frame at segment boundary)
        try? await Task.sleep(nanoseconds: Constants.rotationFrameDelayNanos)  // 50ms = ~3 frames at 60fps

        // finish the old writer and prepare next standby in background
        let sourceURL = try await oldWriter.finishWriting()
        prepareStandbyWriter()
        return sourceURL
        #endif
    }

    private func makeSegmentURL() -> URL {
        let folder = LiveSegmentCleanup.defaultFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(LiveSegmentCleanup.prefix)\(UUID().uuidString).mov")
    }

    private var captureAudioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]
    }

    private static func inspectSegmentFile(at url: URL) async throws -> TimeInterval {
        try await waitForFileReady(at: url)
        return try await loadDuration(of: url)
    }

    private static func waitForFileReady(at url: URL) async throws {
        let fm = FileManager.default
        for _ in 0..<Constants.fileReadyAttempts {
            if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
                size.intValue > 0
            {
                return
            }
            try await Task.sleep(nanoseconds: Constants.fileReadyDelayNanos)
        }
        throw CaptureError.noFramesCaptured
    }

    private static func loadDuration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw CaptureError.invalidDuration
        }
        return seconds
    }

    private static func logError(_ label: String, _ error: Error) {
        AppLog.error(.capture, label, error: error)
    }

    private func startRotationLoop() {
        rotationTask?.cancel()
        rotationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(segmentDuration * Constants.nanosPerSecond))
                if Task.isCancelled { break }
                await self.rotateSegment()
            }
        }
    }

    /// The rotation a save performs to capture the most recent footage. If the
    /// current segment is empty (a save right after a timer rotation, or a static
    /// screen) that is fine as long as earlier footage is already buffered.
    func rotateForSave() async throws {
        do {
            _ = try await rotateAndRecordSegment()
        } catch let error as CaptureError where error == .noFramesCaptured || error == .invalidDuration {
            let buffered = await replayBuffer.segmentURLs()
            guard !buffered.isEmpty else { throw error }
            AppLog.debug(.capture, "Save: current segment empty, using buffered footage")
        }
    }

    /// One timer-driven rotation. A bad segment is skipped rather than treated as
    /// fatal: an empty segment (no frames arrived in the window, e.g. a static
    /// screen) is dropped silently, and other failures only stop the capture after
    /// several in a row. Either way the already-buffered replay is kept.
    func rotateSegment() async {
        guard isRunning else { return }

        do {
            _ = try await rotateAndRecordSegment()
            consecutiveRotationFailures = 0
        } catch let error as CaptureError where error == .noFramesCaptured || error == .invalidDuration {
            AppLog.debug(.capture, "Skipping empty replay segment:", error.localizedDescription)
        } catch is CancellationError {
            return
        } catch {
            guard isRunning else { return }
            consecutiveRotationFailures += 1
            Self.logError(
                "Rotation failed (\(consecutiveRotationFailures)/\(Constants.maxConsecutiveRotationFailures))",
                error)
            if consecutiveRotationFailures >= Constants.maxConsecutiveRotationFailures {
                await handleCaptureFailure(error, label: "Rotation failed repeatedly")
            }
        }
    }

    /// Rotates to the standby writer, validates the finished segment and appends it
    /// to the replay buffer, all while holding the rotation lock.
    private func rotateAndRecordSegment() async throws -> URL {
        try await rotation.withLock {
            guard isRunning else { throw CaptureError.writerUnavailable }
            let sourceURL = try await rotateWriterSeamlessly()
            do {
                let duration = try await inspectSegment(sourceURL)
                let removed = await replayBuffer.appendSegment(
                    url: sourceURL, duration: duration, maxDuration: maxBufferDuration)
                removeFiles(removed)
                return sourceURL
            } catch {
                removeFiles([sourceURL])
                throw error
            }
        }
    }

    private func handleCaptureFailure(_ error: Error, label: String) async {
        let handled = await lifecycle.withLock { () -> Bool in
            guard isRunning else { return false }
            Self.logError(label, error)
            await stopCapturePipeline()
            return true
        }
        // Outside the lifecycle lock so the handler can restart capture.
        if handled, let onCaptureInterrupted {
            await onCaptureInterrupted(error)
        }
    }

    private func stopCapturePipeline() async {
        await resetCaptureState()
    }

    private func resetCaptureState() async {
        rotationTask?.cancel()
        rotationTask = nil
        screenCapture.onVideoSampleBuffer = nil
        screenCapture.onAudioSampleBuffer = nil
        screenCapture.onMicSampleBuffer = nil
        currentWriter = nil
        // Let any rotation already in flight finish before tearing the pipeline
        // down, so it can't add a segment to the buffer after it is cleared.
        await rotation.withLock {
            await screenCapture.stopCapture()
            if let url = try? await activeWriter.finishWriting() {
                removeFiles([url])
            }
            standbyWriter = nil
            let urls = await replayBuffer.clear()
            removeFiles(urls)
            cleanupTemporaryLiveSegments()
        }
        isSaving = false
        isRunning = false
    }

    private func removeFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let fm = FileManager.default
        for url in urls {
            try? fm.removeItem(at: url)
        }
    }

    private func cleanupTemporaryLiveSegments() {
        LiveSegmentCleanup.removeAll()
    }
}
