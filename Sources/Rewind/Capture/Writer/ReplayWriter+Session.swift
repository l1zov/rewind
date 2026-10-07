@preconcurrency import AVFoundation

extension ReplayWriter {
    // - Session start ---

    func startSessionIfNeeded() {
        guard !sessionStarted,
            let writer,
            let videoInput,
            writer.status == .unknown
        else { return }
        guard firstVideoPTS.isValid else { return }
        if !writer.startWriting() {
            AppLog.error(.writer, "ReplayWriter.startWriting failed", error: writer.error)
            acceptsMediaData = false
            return
        }

        let referencePTS = firstVideoPTS

        videoPTSOffset = .zero
        audioPTSOffsetValid = true

        sessionStartPTS = referencePTS
        writer.startSession(atSourceTime: referencePTS)
        sessionStarted = true
        audioBufferingEndPTS = CMTimeAdd(referencePTS, Constants.audioBufferingWindow)

        flushPendingVideoSamples(writer: writer, videoInput: videoInput)
        if let audioInput {
            flushPendingAudioSamples(audioInput: audioInput, writer: writer)
        }
        // Mic samples queued before the session started would otherwise sit
        // until the next mic buffer arrives (and be lost if delivery stalls).
        if let micInput {
            drainPendingMicWhileReady(micInput: micInput, writer: writer)
        }
    }

    // - Pending drain / flush ---

    func drainPendingAudioWhileReady(audioInput: AVAssetWriterInput, writer: AVAssetWriter) {
        guard writer.status == .writing, !pendingAudio.isEmpty else { return }
        while audioInput.isReadyForMoreMediaData, let sample = pendingAudio.dequeue() {
            if !appendAdjustedAudioSample(sample, to: audioInput, writer: writer) {
                break
            }
        }
    }

    func drainPendingMicWhileReady(micInput: AVAssetWriterInput, writer: AVAssetWriter) {
        guard writer.status == .writing, !pendingMic.isEmpty else { return }
        let minValidPTS = CMTimeSubtract(sessionStartPTS, Constants.audioSyncTolerance)
        while micInput.isReadyForMoreMediaData, let sample = pendingMic.dequeue() {
            if CMSampleBufferGetPresentationTimeStamp(sample) < minValidPTS { continue }
            if !appendMicSample(sample, to: micInput, writer: writer) { break }
        }
    }

    func drainPendingVideoIfReady(writer: AVAssetWriter, videoInput: AVAssetWriterInput) {
        guard !pendingVideo.isEmpty, writer.status == .writing, videoInput.isReadyForMoreMediaData
        else { return }
        while videoInput.isReadyForMoreMediaData, let sample = pendingVideo.dequeue() {
            appendVideoSample(sample, writer: writer, videoInput: videoInput)
            if !acceptsMediaData { break }
        }
    }

    func flushPendingAudioSamples(audioInput: AVAssetWriterInput, writer: AVAssetWriter) {
        guard !pendingAudio.isEmpty else { return }

        if firstAudioPTS.isValid, firstVideoPTS.isValid, firstAudioPTS < firstVideoPTS {
            let audioVideoOffset = CMTimeSubtract(firstVideoPTS, firstAudioPTS)
            AppLog.debug(
                .writer, "ReplayWriter: audio-video offset:", audioVideoOffset.seconds * 1000,
                "ms (audio started earlier)")
        }

        let minValidPTS = sessionStartPTS
        var droppedCount = 0
        var remaining: [CMSampleBuffer] = []
        for sample in pendingAudio.samples {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if pts < minValidPTS {
                droppedCount += 1
                continue
            }
            remaining.append(sample)
        }

        pendingAudio.replaceAll(remaining)
        if droppedCount > 0 {
            AppLog.debug(.writer, "ReplayWriter: flushed pending audio, dropped:", droppedCount)
        }
        drainPendingAudioWhileReady(audioInput: audioInput, writer: writer)
    }

    func flushPendingVideoSamples(writer: AVAssetWriter, videoInput: AVAssetWriterInput) {
        guard !pendingVideo.isEmpty else { return }
        let minValidPTS = CMTimeSubtract(sessionStartPTS, Constants.videoSyncTolerance)

        var appendedCount = 0
        var droppedCount = 0
        var remaining: [CMSampleBuffer] = []
        for sample in pendingVideo.samples {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if pts < minValidPTS {
                droppedCount += 1
                continue
            }
            if videoInput.isReadyForMoreMediaData {
                appendVideoSample(sample, writer: writer, videoInput: videoInput)
                if acceptsMediaData {
                    appendedCount += 1
                } else {
                    remaining.append(sample)
                    break
                }
            } else {
                remaining.append(sample)
            }
        }

        pendingVideo.replaceAll(remaining)
        if appendedCount > 0 || droppedCount > 0 {
            AppLog.debug(
                .writer, "ReplayWriter: flushed", appendedCount, "pending video samples, dropped:",
                droppedCount)
        }
    }

    // - Finish ---

    /// Finishes the current segment, giving up after `finishWritingTimeout`.
    ///
    /// The timeout used to race the real work in a task group, which could not
    /// work: a group awaits its children before propagating, and the child was
    /// suspended on a continuation that cancellation cannot resume. A wedged
    /// writer therefore hung forever instead of timing out. Both outcomes now
    /// share one continuation, resumed by whichever arrives first.
    func finishWriting() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)

            // Deliberately not scheduled on the writer queue: if that queue is the
            // thing that is stuck, a timer on it would never fire either.
            let timeout = DispatchWorkItem {
                AppLog.error(
                    .writer,
                    "ReplayWriter.finishWriting timed out after",
                    Constants.finishWritingTimeout,
                    "seconds"
                )
                once.resume(.failure(CaptureError.writerFinishTimedOut))
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + Constants.finishWritingTimeout, execute: timeout
            )

            self.finishWritingInternal { result in
                timeout.cancel()
                once.resume(result)
            }
        }
    }

    private func finishWritingInternal(_ completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.onQueue {
            guard let writer = self.writer, let outputURL = self.outputURL else {
                AppLog.debug(.writer, "ReplayWriter.finishWriting: writer unavailable.")
                completion(.failure(CaptureError.writerUnavailable))
                return
            }

            guard self.sessionStarted else {
                AppLog.debug(.writer, "ReplayWriter.finishWriting: no session started.")
                self.resetState()
                completion(.failure(CaptureError.noFramesCaptured))
                return
            }

            // AVAssetWriter raises an uncatchable NSInternalInconsistencyException
            // if finishWriting is called outside `.writing` — which is where a
            // failed append (disk full, encoder error) leaves it.
            guard writer.status == .writing else {
                let error = writer.error ?? CaptureError.exportFailed
                AppLog.error(
                    .writer,
                    "ReplayWriter.finishWriting: writer not writing. status: \(writer.status.rawValue)",
                    error: error)
                self.resetState()
                try? FileManager.default.removeItem(at: outputURL)
                completion(.failure(error))
                return
            }

            AppLog.debug(
                .writer, "ReplayWriter.finishWriting: start. status:", writer.status.rawValue)

            // Give any samples still queued from backpressure one last chance
            // to reach the writer before their inputs are marked finished —
            // otherwise they're silently dropped by resetState() below.
            if let videoInput = self.videoInput {
                self.drainPendingVideoIfReady(writer: writer, videoInput: videoInput)
            }
            if let audioInput = self.audioInput {
                self.drainPendingAudioWhileReady(audioInput: audioInput, writer: writer)
            }
            if let micInput = self.micInput {
                self.drainPendingMicWhileReady(micInput: micInput, writer: writer)
            }

            self.acceptsMediaData = false
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            self.micInput?.markAsFinished()
            let writerBox = UncheckedSendable(writer)
            writer.finishWriting { [self] in
                // dispatch back to our queue to safely access state
                self.onQueue {
                    let writer = writerBox.value
                    let error = writer.error
                    if let error {
                        AppLog.error(.writer, "ReplayWriter.finishWriting: failed.", error: error)
                    } else {
                        AppLog.debug(.writer, "ReplayWriter.finishWriting: success.")
                    }
                    self.resetState()

                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(outputURL))
                    }
                }
            }
        }
    }
}

/// Hands a continuation to exactly one of two racing callers.
///
/// `finishWriting` resumes either from the writer's completion handler or from the
/// timeout, and those run on different queues, so the guard needs its own lock.
/// Internal rather than private so the race it guards can be tested directly:
/// resuming a `CheckedContinuation` twice traps the process.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()

        pending?.resume(with: result)
    }
}
