@preconcurrency import AVFoundation
import Foundation

/// Stitches capture segments into one passthrough clip. Replay exports select a
/// trailing duration; manual exports preserve the composition's full duration.
struct ReplayExporter {
    func export(
        segments: [ReplaySegment],
        seconds: TimeInterval,
        container: CaptureContainer
    ) async throws -> URL {
        try await export(
            segments: segments,
            trailingSeconds: seconds,
            container: container
        )
    }

    /// Exports every frame in `segments` rather than applying the replay
    /// buffer's trailing-duration trim. Manual recordings use this path so a
    /// session is never capped by the replay buffer's five-minute window.
    func exportAll(
        segments: [ReplaySegment],
        container: CaptureContainer,
        outputFolder: URL? = nil
    ) async throws -> URL {
        try await export(
            segments: segments,
            trailingSeconds: nil,
            container: container,
            outputFolder: outputFolder
        )
    }

    private func export(
        segments: [ReplaySegment],
        trailingSeconds: TimeInterval?,
        container: CaptureContainer,
        outputFolder: URL? = nil
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
        let clipSeconds: TimeInterval
        if let trailingSeconds {
            clipSeconds = max(0, min(trailingSeconds, totalSeconds))
        } else {
            clipSeconds = totalSeconds
        }
        guard clipSeconds > 0 else {
            throw CaptureError.noFramesCaptured
        }
        let timescale = cursor.timescale == 0 ? CMTimeScale(600) : cursor.timescale
        let startTime = CMTime(
            seconds: trailingSeconds == nil ? 0 : max(totalSeconds - clipSeconds, 0),
            preferredTimescale: timescale)
        let timeRange = CMTimeRange(
            start: startTime, duration: CMTime(seconds: clipSeconds, preferredTimescale: timescale))

        let folder = outputFolder ?? ClipStorageLocation.current()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let exportURL = folder.appendingPathComponent(
            "Rewind_\(UUID().uuidString).\(container.fileExtension)")
        try? FileManager.default.removeItem(at: exportURL)

        do {
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
        exportSession.shouldOptimizeForNetworkUse = false

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
}
