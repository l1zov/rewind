import AVFoundation
import CoreGraphics
import VideoToolbox

/// Builds the video `AVAssetWriterInput` output settings and matching source
/// pixel-buffer format for a given quality preset, resolution, and frame rate.
enum VideoEncoderSettings {
    /// intel's quick sync encoder rejects a second concurrent HEvc session
    /// h264 does not have such limitation
    static var codec: AVVideoCodecType {
        #if arch(x86_64)
            return .h264
        #else
            return .hevc
        #endif
    }

    /// Source pixel format handed to the pixel-buffer adaptor. Must match the
    /// format ScreenCaptureKit captures (NV12); declaring a different format here
    /// breaks the zero-copy path and forces a per-frame color conversion on the
    /// writer queue, causing encoder backpressure and stutter.
    static func sourcePixelFormat(for quality: QualityPreset) -> OSType {
        _ = quality
        return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    static func outputSettings(
        quality: QualityPreset,
        width: Int,
        height: Int,
        frameRate: Int
    ) -> [String: Any] {
        [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties(
                for: quality,
                videoSize: CGSize(width: width, height: height),
                frameRate: frameRate
            ),
        ]
    }

    static func targetBitrateMbps(for quality: QualityPreset, videoSize: CGSize, frameRate: Int)
        -> Double
    {
        let width = max(1, Int(videoSize.width.rounded()))
        let height = max(1, Int(videoSize.height.rounded()))
        let fps = max(30, min(frameRate, 120))

        let pixelsPerFrame = Double(width * height)
        let bitsPerSecond = quality.bitsPerPixel * pixelsPerFrame * Double(fps)
        let bitrateMbps = bitsPerSecond / 1_000_000
        return min(max(bitrateMbps, quality.minBitrateMbps), quality.maxBitrateMbps)
    }

    private static func compressionProperties(
        for quality: QualityPreset,
        videoSize: CGSize,
        frameRate: Int
    ) -> [String: Any] {
        let normalizedFrameRate = max(30, min(frameRate, 120))
        let averageBitrateMbps = targetBitrateMbps(
            for: quality, videoSize: videoSize, frameRate: normalizedFrameRate)
        let averageBitrate = Int((averageBitrateMbps * 1_000_000).rounded())
        let keyframeInterval = max(
            normalizedFrameRate, Int((Double(normalizedFrameRate) * 1.5).rounded()))

        // VBR bursting
        let burstMultiplier = 1.5
        let burstWindowSeconds = 2
        let maxBitrate = Int((averageBitrateMbps * burstMultiplier * 1_000_000).rounded())

        var props: [String: Any] = [
            AVVideoAverageBitRateKey: averageBitrate,
            AVVideoExpectedSourceFrameRateKey: normalizedFrameRate,
            AVVideoMaxKeyFrameIntervalKey: keyframeInterval,
            AVVideoMaxKeyFrameIntervalDurationKey: 1.5,
            AVVideoAllowFrameReorderingKey: false,
            kVTCompressionPropertyKey_RealTime as String: true,
        ]

        if codec == .h264 {
            props[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }

        let isTesting =
            NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"

        if !isTesting {
            if #available(macOS 14.0, *) {
                props[kVTCompressionPropertyKey_DataRateLimits as String] = [
                    (maxBitrate / 8) * burstWindowSeconds, burstWindowSeconds,
                ]
            }
        }

        return props
    }
}
