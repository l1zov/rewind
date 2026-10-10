@preconcurrency import AVFoundation

extension ReplayWriter {
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        let buffer = UncheckedSendable(sampleBuffer)
        onQueue { [weak self] in
            self?.appendVideoOnQueue(buffer.value)
        }
    }

    private func appendVideoOnQueue(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard acceptsMediaData else { return }
        guard let writer, let videoInput else { return }

        if CMSampleBufferGetImageBuffer(sampleBuffer) == nil, !loggedNoPixelBufferFormat {
            if let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(format)
                AppLog.debug(
                    .writer, "ReplayWriter.appendVideo no CVPixelBuffer. mediaSubType:",
                    String(format: "0x%08X", mediaSubType))
            }
            loggedNoPixelBufferFormat = true
        }

        let pixelBufferForMode = CMSampleBufferGetImageBuffer(sampleBuffer)
        let desiredMode: VideoMode = (pixelBufferForMode != nil) ? .pixelBufferEncode : .passthrough
        if reconfigureForVideoModeIfNeeded(desiredMode: desiredMode, pixelBuffer: pixelBufferForMode) {
            return
        }
        if let pixelBuffer = pixelBufferForMode,
            reconfigureForBufferSizeIfNeeded(pixelBuffer: pixelBuffer)
        {
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !firstVideoPTS.isValid {
            firstVideoPTS = pts
        }

        if !sessionStarted {
            pendingVideo.enqueue(sampleBuffer)
            startSessionIfNeeded()
            return
        }

        if !pendingVideo.isEmpty {
            pendingVideo.enqueue(sampleBuffer)
            drainPendingVideoIfReady(writer: writer, videoInput: videoInput)
            return
        }

        if writer.status == .failed {
            logAppendFailure(
                label: "ReplayWriter.appendVideo writer failed",
                writer: writer,
                videoInput: videoInput,
                sampleBuffer: sampleBuffer
            )
            acceptsMediaData = false
            return
        }

        guard writer.status == .writing else { return }
        appendVideoSample(sampleBuffer, writer: writer, videoInput: videoInput)
        if let audioInput {
            drainPendingAudioWhileReady(audioInput: audioInput, writer: writer)
        }
    }

    private func reconfigureForVideoModeIfNeeded(desiredMode: VideoMode, pixelBuffer: CVPixelBuffer?)
        -> Bool
    {
        guard let writer,
            writer.status == .unknown,
            configuredVideoMode != desiredMode
        else { return false }

        reconfigureCount += 1
        AppLog.debug(
            .writer, "⚠️ ReplayWriter.appendVideo reconfigure #\(reconfigureCount) for mode:",
            desiredMode)
        guard let outputURL else { return true }

        let desiredSize: CGSize
        if let pixelBuffer {
            desiredSize = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            )
        } else {
            desiredSize = configuredVideoSize ?? .zero
        }

        do {
            try configureOnQueue(
                outputURL: outputURL,
                videoSize: desiredSize,
                includeAudio: includeAudio,
                audioSettings: configuredAudioSettings,
                videoMode: desiredMode,
                quality: configuredQuality,
                frameRate: configuredFrameRate,
                recordMicrophone: configuredRecordMicrophone,
                videoCodec: configuredVideoCodec
            )
        } catch {
            AppLog.error(.writer, "ReplayWriter.appendVideo reconfigure failed", error: error)
            acceptsMediaData = false
        }
        return true
    }

    private func reconfigureForBufferSizeIfNeeded(pixelBuffer: CVPixelBuffer) -> Bool {
        guard let writer,
            writer.status == .unknown,
            let configuredSize = configuredVideoSize
        else { return false }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bufferSize = CGSize(width: width, height: height)
        guard configuredSize != bufferSize else { return false }

        reconfigureCount += 1
        AppLog.debug(
            .writer, "⚠️ ReplayWriter.appendVideo reconfigure #\(reconfigureCount) for buffer size:",
            width, "x", height)
        guard let outputURL else { return true }

        do {
            try configureOnQueue(
                outputURL: outputURL,
                videoSize: bufferSize,
                includeAudio: includeAudio,
                audioSettings: configuredAudioSettings,
                videoMode: configuredVideoMode,
                quality: configuredQuality,
                frameRate: configuredFrameRate,
                recordMicrophone: configuredRecordMicrophone,
                videoCodec: configuredVideoCodec
            )
        } catch {
            AppLog.error(.writer, "ReplayWriter.appendVideo reconfigure failed", error: error)
            acceptsMediaData = false
        }
        return true
    }

    func appendVideoSample(
        _ sampleBuffer: CMSampleBuffer, writer: AVAssetWriter, videoInput: AVAssetWriterInput
    ) {
        guard let adjustedSample = SampleBufferTiming.quantizedVideo(
            sampleBuffer,
            offset: videoPTSOffset,
            sessionStartPTS: sessionStartPTS,
            lastVideoPTS: lastVideoPTS,
            defaultFrameRate: configuredFrameRate
        ) else {
            // The source is delivering faster than the configured frame rate: drop the
            // surplus frame rather than let the video timeline run behind real time.
            videoTimingDrops += 1
            if videoTimingDrops == 1 || videoTimingDrops % Constants.backpressureLogInterval == 0 {
                AppLog.debug(
                    .writer, "ReplayWriter.appendVideo dropped surplus frame (source faster than",
                    configuredFrameRate, "fps). count:", videoTimingDrops)
            }
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(adjustedSample)

        if pts < sessionStartPTS {
            AppLog.debug(
                .writer, "ReplayWriter.appendVideo dropping frame before session start. PTS:",
                pts.seconds, "start:", sessionStartPTS.seconds)
            return
        }

        if !loggedFirstVideoBuffer, let pixelBuffer = CMSampleBufferGetImageBuffer(adjustedSample) {
            let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
            let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
            let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
            AppLog.debug(
                .writer, "ReplayWriter.appendVideo first buffer:", bufferWidth, "x", bufferHeight,
                "format:", String(format: "0x%08X", format))

            if let configuredSize = configuredVideoSize {
                let configuredWidth = Int(configuredSize.width)
                let configuredHeight = Int(configuredSize.height)
                if bufferWidth != configuredWidth || bufferHeight != configuredHeight {
                    AppLog.debug(
                        .writer,
                        "ReplayWriter: source/encode size mismatch; dropping frame. buffer:",
                        bufferWidth, "x", bufferHeight, "configured:", configuredWidth, "x",
                        configuredHeight)
                } else {
                    AppLog.debug(.writer, "ReplayWriter: buffer size matches configured size ✓")
                }
            }

            loggedFirstVideoBuffer = true
        }
        if lastVideoPTS.isValid, pts < lastVideoPTS {
            AppLog.debug(
                .writer, "ReplayWriter.appendVideo non-monotonic PTS. last:", lastVideoPTS.seconds,
                "now:", pts.seconds)
        }
        lastVideoPTS = pts

        guard videoInput.isReadyForMoreMediaData else {
            // track backpressure drops; this indicates the encoder cant keep up
            videoBackpressureDrops += 1
            if videoBackpressureDrops == 1
                || videoBackpressureDrops % Constants.backpressureLogInterval == 0
            {
                AppLog.debug(
                    .writer, "ReplayWriter.appendVideo backpressure drop count:",
                    videoBackpressureDrops)
            }
            return
        }

        if configuredVideoMode == .passthrough {
            if !videoInput.append(adjustedSample) {
                logAppendFailure(
                    label: "ReplayWriter.appendVideo passthrough append failed",
                    writer: writer,
                    videoInput: videoInput,
                    sampleBuffer: adjustedSample
                )
                acceptsMediaData = false
            }
            return
        }

        guard let adaptor = videoAdaptor,
            let pixelBuffer = CMSampleBufferGetImageBuffer(adjustedSample)
        else {
            if missingAdaptorDrops < Constants.missingAdaptorLogLimit {
                let adaptorMissing = videoAdaptor == nil
                let pixelMissing = CMSampleBufferGetImageBuffer(adjustedSample) == nil
                AppLog.debug(
                    .writer, "ReplayWriter.appendVideo adaptor missing; dropping frame. adaptorNil:",
                    adaptorMissing, "pixelBufferNil:", pixelMissing)
            }
            missingAdaptorDrops += 1
            return
        }

        if let configuredSize = configuredVideoSize,
            CVPixelBufferGetWidth(pixelBuffer) != Int(configuredSize.width)
                || CVPixelBufferGetHeight(pixelBuffer) != Int(configuredSize.height)
        {
            missingAdaptorDrops += 1
            if missingAdaptorDrops <= Constants.missingAdaptorLogLimit {
                AppLog.debug(
                    .writer,
                    "ReplayWriter.appendVideo pixel buffer size mismatch; dropping frame. buffer:",
                    CVPixelBufferGetWidth(pixelBuffer), "x", CVPixelBufferGetHeight(pixelBuffer),
                    "configured:", Int(configuredSize.width), "x", Int(configuredSize.height))
            }
            return
        }

        if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
            logAppendFailure(
                label: "ReplayWriter.appendVideo pixelBuffer append failed",
                writer: writer,
                videoInput: videoInput,
                sampleBuffer: adjustedSample
            )
            acceptsMediaData = false
        }
    }

    func logAppendFailure(
        label: String,
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        sampleBuffer: CMSampleBuffer
    ) {
        AppLog.error(
            .writer, label, "status:", writer.status.rawValue, "ready:",
            videoInput.isReadyForMoreMediaData)
        AppLog.error(.writer, "ReplayWriter.appendVideo writer.error", error: writer.error)
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastVideoPTS.isValid {
            AppLog.error(
                .writer, "ReplayWriter.appendVideo PTS last:", lastVideoPTS.seconds, "now:",
                pts.seconds)
        } else {
            AppLog.error(.writer, "ReplayWriter.appendVideo PTS now:", pts.seconds)
        }
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
            AppLog.error(
                .writer, "ReplayWriter.appendVideo buffer:", width, "x", height, "format:", format)
        }
    }
}
