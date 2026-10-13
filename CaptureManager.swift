@preconcurrency import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit

actor CaptureManager {
    enum SessionError: Error, LocalizedError, Equatable {
        case alreadyActive
        case transitionInProgress

        var errorDescription: String? {
            switch self {
            case .alreadyActive:
                return "A capture session is already active."
            case .transitionInProgress:
                return "A capture session is currently starting or stopping."
            }
        }
    }

    private enum SessionMode {
        case replay
        case manual
    }

    private enum Constants {
        static let rotationFrameDelayNanos: UInt64 = 50_000_000
        static let fileReadyAttempts = 10
        static let fileReadyDelayNanos: UInt64 = 50_000_000
        static let nanosPerSecond: Double = 1_000_000_000
    }

    private let screenCapture: ScreenCaptureService
    private let captureQueue: DispatchQueue
    private let writerQueue: DispatchQueue
    /// active writer receiving samples (accessed via nonisolated helper for callbacks)
    private var activeWriter: ReplayWriter
    private var activeSegmentURL: URL?
    /// standby writer pre-configured for instant switchover
    private var standbyWriter: ReplayWriter?
    private var standbySegmentURL: URL?
    private let replayBuffer = ReplayBuffer()
    private let exporter = ReplayExporter()
    private var isRunning = false
    private var isStarting = false
    private var isSaving = false
    private var isStopping = false
    private var sessionMode: SessionMode?
    private var captureGeneration: UInt64?
    private var pendingStartupInterruption: (generation: UInt64, error: Error)?
    private var manualContainer: CaptureContainer?
    private var manualOutputFolder: URL?
    private var manualStopTask: Task<URL, Error>?
    private var manualStopClaimedByCaller = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var isRotating = false
    private var rotationWaiters: [CheckedContinuation<Void, Never>] = []
    private var rotationTask: Task<Void, Never>?
    private let segmentDuration: TimeInterval = 10
    private let maxBufferDuration: TimeInterval = 300
    private var currentQuality: QualityPreset = .default
    private var currentFrameRate: Int = CaptureFrameRate.default.framesPerSecond
    private var currentAudioCodec: CaptureAudioCodec = .default
    private var recordMicrophoneEnabled: Bool = false
    private var recordDesktopAudioEnabled: Bool = true
    private var onCaptureInterrupted: (@MainActor (Error, URL?) -> Void)?

    /// thread-safe reference to current writer for use in callbacks
    /// sses lock-based synchronization so it can be safely accessed from nonisolated contexts
    private let currentWriterLock = NSLock()
    private nonisolated(unsafe) var _currentWriter: ReplayWriter?
    private nonisolated var currentWriter: ReplayWriter? {
        get {
            currentWriterLock.withLock { _currentWriter }
        }
        set {
            currentWriterLock.withLock { _currentWriter = newValue }
        }
    }

    init() {
        // sse userInteractive QoS for real-time capture processing
        let queue = DispatchQueue(label: "rewind.capture.samples", qos: .userInteractive)
        captureQueue = queue
        let audioQueue = DispatchQueue(label: "rewind.capture.audio", qos: .userInteractive)
        // dedicated writer queue keeps encoding work off the capture callback queue.
        writerQueue = DispatchQueue(label: "rewind.capture.writer", qos: .userInitiated)
        screenCapture = ScreenCaptureService(sampleQueue: queue, audioQueue: audioQueue)
        activeWriter = ReplayWriter(queue: writerQueue)
        screenCapture.onCaptureStopped = { [weak self] generation, reason in
            guard let self else { return }
            // Only plain values cross into the task: the framework's error object
            // may already be freed by the time this runs.
            let error = CaptureError.streamStopped(reason: reason)
            Task {
                await self.handleCaptureFailure(
                    error,
                    generation: generation,
                    label: "Capture stream stopped"
                )
            }
        }
    }

    func setOnCaptureInterruptedHandler(
        _ handler: (@MainActor (Error, URL?) -> Void)?
    ) {
        onCaptureInterrupted = handler
    }

    func start(
        contentFilter: UncheckedSendable<SCContentFilter>? = nil,
        resolution: CaptureResolution? = nil,
        quality: QualityPreset = .default,
        frameRate: Int = CaptureFrameRate.default.framesPerSecond,
        audioCodec: CaptureAudioCodec = .default,
        recordMicrophoneEnabled: Bool = false,
        recordDesktopAudioEnabled: Bool = true,
        microphoneDeviceID: String? = nil
    ) async throws {
        try await startCapture(
            mode: .replay,
            contentFilter: contentFilter,
            resolution: resolution,
            quality: quality,
            frameRate: frameRate,
            audioCodec: audioCodec,
            recordMicrophoneEnabled: recordMicrophoneEnabled,
            recordDesktopAudioEnabled: recordDesktopAudioEnabled,
            microphoneDeviceID: microphoneDeviceID,
            manualContainer: nil
        )
    }

    /// Starts an OBS-style recording that runs until `stopManualRecording` is
    /// called. Unlike replay capture, this uses one long-lived writer and never
    /// rotates into the duration-limited replay buffer.
    func startManualRecording(
        contentFilter: UncheckedSendable<SCContentFilter>? = nil,
        resolution: CaptureResolution? = nil,
        quality: QualityPreset = .default,
        frameRate: Int = CaptureFrameRate.default.framesPerSecond,
        audioCodec: CaptureAudioCodec = .default,
        container: CaptureContainer = .default,
        recordMicrophoneEnabled: Bool = false,
        recordDesktopAudioEnabled: Bool = true,
        microphoneDeviceID: String? = nil
    ) async throws {
        try await startCapture(
            mode: .manual,
            contentFilter: contentFilter,
            resolution: resolution,
            quality: quality,
            frameRate: frameRate,
            audioCodec: audioCodec,
            recordMicrophoneEnabled: recordMicrophoneEnabled,
            recordDesktopAudioEnabled: recordDesktopAudioEnabled,
            microphoneDeviceID: microphoneDeviceID,
            manualContainer: container
        )
    }

    private func startCapture(
        mode: SessionMode,
        contentFilter: UncheckedSendable<SCContentFilter>?,
        resolution: CaptureResolution?,
        quality: QualityPreset,
        frameRate: Int,
        audioCodec: CaptureAudioCodec,
        recordMicrophoneEnabled: Bool,
        recordDesktopAudioEnabled: Bool,
        microphoneDeviceID: String?,
        manualContainer: CaptureContainer?
    ) async throws {
        guard !isRunning else { throw SessionError.alreadyActive }
        guard !isStarting, !isStopping else { throw SessionError.transitionInProgress }
        isStarting = true
        sessionMode = mode
        self.manualContainer = manualContainer
        manualOutputFolder = mode == .manual ? ClipStorageLocation.current() : nil
        manualStopClaimedByCaller = false
        defer { finishStarting() }

        currentQuality = quality
        currentFrameRate = frameRate
        currentAudioCodec = audioCodec
        self.recordMicrophoneEnabled = recordMicrophoneEnabled
        self.recordDesktopAudioEnabled = recordDesktopAudioEnabled


        do {
            let startedGeneration = try await screenCapture.startCapture(
                contentFilter: contentFilter,
                resolution: resolution,
                quality: quality,
                frameRate: frameRate,
                recordMicrophone: recordMicrophoneEnabled,
                recordDesktopAudio: recordDesktopAudioEnabled,
                microphoneDeviceID: microphoneDeviceID
            )
            captureGeneration = startedGeneration
            if let pendingStartupInterruption {
                self.pendingStartupInterruption = nil
                if pendingStartupInterruption.generation == startedGeneration {
                    throw pendingStartupInterruption.error
                }
            }
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
            if mode == .replay {
                prepareStandbyWriter()
                startRotationLoop()
            }
        } catch {
            await resetCaptureState()
            throw error
        }
    }

    @discardableResult
    func stop() async -> URL? {
        if isStarting {
            await waitForStartToFinish()
        }
        guard isRunning else { return nil }
        if sessionMode == .manual {
            return try? await stopManualRecording()
        }
        await stopCapturePipeline()
        return nil
    }

    /// Stops a manual recording and returns one clip in the container selected
    /// at start. Concurrent Stop requests share one finalization task, so the
    /// writer is never finished or exported twice.
    func stopManualRecording() async throws -> URL {
        if isStarting, sessionMode == .manual {
            await waitForStartToFinish()
        }
        let task = try beginManualStop()
        manualStopClaimedByCaller = true
        return try await task.value
    }

    private func beginManualStop() throws -> Task<URL, Error> {
        if let manualStopTask {
            return manualStopTask
        }
        guard isRunning, sessionMode == .manual else {
            throw CaptureError.noFramesCaptured
        }
        guard !isStopping else { throw SessionError.transitionInProgress }

        // Set this before yielding so generic Stop, interruption handling, and
        // repeated hotkey events cannot race the manual finalization task.
        isStopping = true
        let task = Task { [weak self] in
            guard let self else { throw CaptureError.writerUnavailable }
            return try await self.finishManualRecording()
        }
        manualStopTask = task
        return task
    }

    func saveReplay(seconds: TimeInterval, container: CaptureContainer = .default) async throws
        -> URL
    {
        guard isRunning, sessionMode == .replay else {
            throw CaptureError.noFramesCaptured
        }
        guard !isSaving, !isStopping else { throw CaptureError.saveInProgress }
        isSaving = true
        defer { finishSaving() }
        if isRotating {
            await waitForRotationToFinish()
        }

        AppLog.info(.capture, "Save replay start. seconds:", seconds)


        var sourceURL: URL?
        var sourceURLAddedToBuffer = false
        do {
            sourceURL = try await rotateWriterSeamlessly()
        } catch {
            Self.logError("Replay rotation failed", error)
            throw error
        }

        var segmentsToUnlock: [ReplaySegment] = []
        do {
            guard let sourceURL else { throw CaptureError.writerUnavailable }
            AppLog.debug(.capture, "Replay source ready:", sourceURL.lastPathComponent)
            try await waitForFileReady(at: sourceURL)
            let duration = try await loadDuration(of: sourceURL)
            let removed = await replayBuffer.appendSegment(
                url: sourceURL, duration: duration, maxDuration: maxBufferDuration)
            sourceURLAddedToBuffer = true
            removeFiles(removed)
            let segments = await replayBuffer.latestSegments(totalDuration: seconds)
            segmentsToUnlock = segments

            let exportURL = try await exporter.export(
                segments: segments, seconds: seconds, container: container)

            await replayBuffer.unlockSegments(segmentsToUnlock)
            AppLog.info(.capture, "Save replay success:", exportURL.lastPathComponent)
            return exportURL
        } catch {
            // Always unlock segments on failure
            if !segmentsToUnlock.isEmpty {
                await replayBuffer.unlockSegments(segmentsToUnlock)
            }
            if let sourceURL, !sourceURLAddedToBuffer {
                removeFiles([sourceURL])
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
        do {
            try activeWriter.configure(
                outputURL: outputURL,
                videoSize: size,
                includeAudio: recordDesktopAudioEnabled,
                audioSettings: captureAudioSettings,
                quality: currentQuality,
                frameRate: currentFrameRate,
                recordMicrophone: recordMicrophoneEnabled
            )
            activeSegmentURL = outputURL
        } catch {
            removeFiles([outputURL])
            throw error
        }
    }

    /// pre-configures the standby writer for instant switchover
    private func prepareStandbyWriter() {
        guard let size = screenCapture.displaySize else { return }
        let writer = ReplayWriter(queue: writerQueue)
        let outputURL = makeSegmentURL()
        do {
            try writer.configure(
                outputURL: outputURL,
                videoSize: size,
                includeAudio: recordDesktopAudioEnabled,
                audioSettings: captureAudioSettings,
                quality: currentQuality,
                frameRate: currentFrameRate,
                recordMicrophone: recordMicrophoneEnabled
            )
            standbyWriter = writer
            standbySegmentURL = outputURL
        } catch {
            Self.logError("Failed to prepare standby writer", error)
            removeFiles([outputURL])
            standbyWriter = nil
            standbySegmentURL = nil
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
            let sourceURL = try await oldWriter.finishWriting()

            activeWriter = newWriter
            activeSegmentURL = standbySegmentURL
            standbyWriter = nil
            standbySegmentURL = nil
            currentWriter = newWriter
            prepareStandbyWriter()
            return sourceURL
        #else
        // callbacks will pick up new writer
        activeWriter = newWriter
        activeSegmentURL = standbySegmentURL
        standbyWriter = nil
        standbySegmentURL = nil

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
        if sessionMode == .manual, let manualOutputFolder {
            try? FileManager.default.createDirectory(
                at: manualOutputFolder,
                withIntermediateDirectories: true
            )
            return manualOutputFolder.appendingPathComponent(
                ".Rewind_recording_\(UUID().uuidString).mov"
            )
        }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rewind", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Rewind_live_\(UUID().uuidString).mov")
    }

    private var captureAudioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]
    }

    private func waitForFileReady(at url: URL) async throws {
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

    private func loadDuration(of url: URL) async throws -> TimeInterval {
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

    private func rotateSegment() async {
        guard isRunning, sessionMode == .replay, !isSaving, !isStopping, !isRotating else {
            return
        }
        isRotating = true

        let sourceURL: URL
        do {
            sourceURL = try await rotateWriterSeamlessly()
        } catch {
            finishRotating()
            await handleCaptureFailure(
                error,
                generation: captureGeneration,
                label: "Rotation failed"
            )
            return
        }

        do {
            try await waitForFileReady(at: sourceURL)
            let duration = try await loadDuration(of: sourceURL)
            let removed = await replayBuffer.appendSegment(
                url: sourceURL, duration: duration, maxDuration: maxBufferDuration)
            removeFiles(removed)
            finishRotating()
        } catch {
            removeFiles([sourceURL])
            finishRotating()
            await handleCaptureFailure(
                error,
                generation: captureGeneration,
                label: "Rotation post-processing failed"
            )
        }
    }

    private func handleCaptureFailure(
        _ error: Error,
        generation: UInt64?,
        label: String
    ) async {
        // SCStream can report didStop while `startCapture()` is still suspended.
        // Remember that event until the start continuation supplies its generation;
        // otherwise the callback would be discarded and the caller would publish a
        // recording state for an already-dead stream.
        if isStarting, captureGeneration == nil {
            if let generation {
                if pendingStartupInterruption.map({ generation >= $0.generation }) ?? true {
                    pendingStartupInterruption = (generation, error)
                }
            }
            return
        }
        guard generation == captureGeneration, isRunning, !isStopping else { return }
        Self.logError(label, error)

        var salvagedManualRecording: URL?
        if sessionMode == .manual {
            do {
                let task = try beginManualStop()
                let recoveredURL = try await task.value
                if !manualStopClaimedByCaller {
                    salvagedManualRecording = recoveredURL
                }
            } catch {
                Self.logError("Unable to salvage interrupted manual recording", error)
            }
            manualStopClaimedByCaller = false
        } else {
            await stopCapturePipeline()
        }

        if let onCaptureInterrupted {
            await onCaptureInterrupted(error, salvagedManualRecording)
        }
    }

    private func stopCapturePipeline() async {
        if isStopping {
            await waitForStopToFinish()
            return
        }
        isStopping = true
        defer { finishStopping() }
        if isSaving {
            await waitForSaveToFinish()
        }
        if isRotating {
            await waitForRotationToFinish()
        }
        await resetCaptureState()
    }

    private func resetCaptureState() async {
        rotationTask?.cancel()
        rotationTask = nil
        captureGeneration = nil
        pendingStartupInterruption = nil
        screenCapture.onVideoSampleBuffer = nil
        screenCapture.onAudioSampleBuffer = nil
        screenCapture.onMicSampleBuffer = nil
        currentWriter = nil
        await screenCapture.stopCapture()
        if let url = try? await activeWriter.finishWriting() {
            removeFiles([url])
        }
        if let activeSegmentURL {
            removeFiles([activeSegmentURL])
        }
        if let standbySegmentURL {
            removeFiles([standbySegmentURL])
        }
        activeSegmentURL = nil
        standbyWriter = nil
        standbySegmentURL = nil
        let urls = await replayBuffer.clear()
        removeFiles(urls)
        cleanupTemporaryLiveSegments()
        isSaving = false
        isRunning = false
        sessionMode = nil
        manualContainer = nil
        manualOutputFolder = nil
    }

    private func finishManualRecording() async throws -> URL {
        let temporaryURL = activeSegmentURL
        guard let container = manualContainer else {
            await completeManualRecordingCleanup(temporaryURL: temporaryURL)
            throw CaptureError.writerUnavailable
        }

        rotationTask?.cancel()
        rotationTask = nil
        captureGeneration = nil
        screenCapture.onVideoSampleBuffer = nil
        screenCapture.onAudioSampleBuffer = nil
        screenCapture.onMicSampleBuffer = nil
        currentWriter = nil
        await screenCapture.stopCapture()

        do {
            let sourceURL = try await activeWriter.finishWriting()
            try await waitForFileReady(at: sourceURL)
            let duration = try await loadDuration(of: sourceURL)
            let recordingURL = await exportOrPreserveManualRecording(
                sourceURL: sourceURL,
                duration: duration,
                container: container
            )
            let sourceStillOwnsRecording = recordingURL == sourceURL
            await completeManualRecordingCleanup(
                temporaryURL: sourceStillOwnsRecording ? nil : sourceURL
            )
            AppLog.info(.capture, "Manual recording saved:", recordingURL.lastPathComponent)
            return recordingURL
        } catch {
            Self.logError("Manual recording export failed", error)
            if let temporaryURL,
               let recoveredURL = preserveManualSourceIfPossible(temporaryURL)
            {
                await completeManualRecordingCleanup(temporaryURL: nil)
                AppLog.info(
                    .capture,
                    "Preserved manual recording after finalization failure:",
                    recoveredURL.lastPathComponent
                )
                return recoveredURL
            }
            await completeManualRecordingCleanup(temporaryURL: temporaryURL)
            throw error
        }
    }

    /// Converts the finalized writer output to the selected container. The
    /// writer's MOV remains untouched until conversion succeeds; if conversion
    /// fails, it is promoted as a usable MOV instead of discarding the session.
    private func exportOrPreserveManualRecording(
        sourceURL: URL,
        duration: TimeInterval,
        container: CaptureContainer
    ) async -> URL {
        if container == .mov {
            return promoteManualMOV(sourceURL)
        }

        do {
            return try await exporter.exportAll(
                segments: [ReplaySegment(url: sourceURL, duration: duration)],
                container: container,
                outputFolder: manualOutputFolder
            )
        } catch {
            Self.logError(
                "Manual recording conversion failed; preserving finalized MOV",
                error
            )
            return promoteManualMOV(sourceURL)
        }
    }

    private func promoteManualMOV(_ sourceURL: URL) -> URL {
        let folder = manualOutputFolder ?? sourceURL.deletingLastPathComponent()
        let destination = folder.appendingPathComponent(
            "Rewind_\(UUID().uuidString).mov"
        )
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destination)
            return destination
        } catch {
            // The finalized source is still a valid recording. Returning it is
            // safer than deleting the user's only copy after a rename failure.
            Self.logError("Unable to rename finalized manual recording", error)
            return sourceURL
        }
    }

    /// A writer timeout or metadata read failure does not prove that the file is
    /// useless—the writer may finish moments later. Promote any non-empty source
    /// out of its hidden working name instead of deleting the user's only copy.
    private func preserveManualSourceIfPossible(_ sourceURL: URL) -> URL? {
        guard
            let size = (try? FileManager.default.attributesOfItem(
                atPath: sourceURL.path
            )[.size]) as? NSNumber,
            size.int64Value > 0
        else {
            return nil
        }
        return promoteManualMOV(sourceURL)
    }

    private func waitForStartToFinish() async {
        guard isStarting else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    private func finishStarting() {
        isStarting = false
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func waitForSaveToFinish() async {
        guard isSaving else { return }
        await withCheckedContinuation { continuation in
            saveWaiters.append(continuation)
        }
    }

    private func finishSaving() {
        isSaving = false
        let waiters = saveWaiters
        saveWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func waitForStopToFinish() async {
        guard isStopping else { return }
        await withCheckedContinuation { continuation in
            stopWaiters.append(continuation)
        }
    }

    private func finishStopping() {
        isStopping = false
        let waiters = stopWaiters
        stopWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func waitForRotationToFinish() async {
        guard isRotating else { return }
        await withCheckedContinuation { continuation in
            rotationWaiters.append(continuation)
        }
    }

    private func finishRotating() {
        isRotating = false
        let waiters = rotationWaiters
        rotationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func completeManualRecordingCleanup(temporaryURL: URL?) async {
        if let temporaryURL {
            removeFiles([temporaryURL])
        }
        if let standbySegmentURL {
            removeFiles([standbySegmentURL])
        }
        standbyWriter = nil
        standbySegmentURL = nil
        activeSegmentURL = nil
        let replayURLs = await replayBuffer.clear()
        removeFiles(replayURLs)
        cleanupTemporaryLiveSegments()
        isSaving = false
        isRunning = false
        sessionMode = nil
        captureGeneration = nil
        manualContainer = nil
        manualOutputFolder = nil
        manualStopTask = nil
        finishStopping()
    }

    private func removeFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let fm = FileManager.default
        for url in urls {
            try? fm.removeItem(at: url)
        }
    }

    private func cleanupTemporaryLiveSegments() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rewind", isDirectory: true)
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else {
            return
        }
        for url in urls where url.lastPathComponent.hasPrefix("Rewind_live_") {
            try? fm.removeItem(at: url)
        }
    }
}
