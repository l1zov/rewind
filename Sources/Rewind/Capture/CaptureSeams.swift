@preconcurrency import AVFoundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// What `CaptureManager` needs from the screen/audio source. `ScreenCaptureService`
/// is the real implementation; tests substitute a fake so the manager's
/// start/stop/rotation behavior can be exercised without ScreenCaptureKit or
/// the Screen Recording permission.
protocol CaptureSource: AnyObject, Sendable {
	var displaySize: CGSize? { get }
	var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)? { get set }
	var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)? { get set }
	var onMicSampleBuffer: ((CMSampleBuffer) -> Void)? { get set }
	var onCaptureStopped: ((String?) -> Void)? { get set }

	func startCapture(
		contentFilter: UncheckedSendable<SCContentFilter>?,
		resolution: CaptureResolution?,
		quality: QualityPreset,
		frameRate: Int,
		recordMicrophone: Bool,
		recordDesktopAudio: Bool,
		microphoneDeviceID: String?
	) async throws
	func stopCapture() async
}

extension ScreenCaptureService: CaptureSource {}

/// One rolling segment file's writer. `ReplayWriter` is the real implementation.
protocol SegmentWriter: AnyObject, Sendable {
	func configureSegment(
		outputURL: URL,
		videoSize: CGSize,
		includeAudio: Bool,
		audioSettings: [String: Any]?,
		quality: QualityPreset,
		frameRate: Int,
		recordMicrophone: Bool,
		videoCodec: CaptureVideoCodec
	) throws
	func finishWriting() async throws -> URL
	func appendVideo(_ sampleBuffer: CMSampleBuffer)
	func appendAudio(_ sampleBuffer: CMSampleBuffer)
	func appendMic(_ sampleBuffer: CMSampleBuffer)
}

extension ReplayWriter: SegmentWriter {
	func configureSegment(
		outputURL: URL,
		videoSize: CGSize,
		includeAudio: Bool,
		audioSettings: [String: Any]?,
		quality: QualityPreset,
		frameRate: Int,
		recordMicrophone: Bool,
		videoCodec: CaptureVideoCodec
	) throws {
		try configure(
			outputURL: outputURL,
			videoSize: videoSize,
			includeAudio: includeAudio,
			audioSettings: audioSettings,
			videoMode: .pixelBufferEncode,
			quality: quality,
			frameRate: frameRate,
			recordMicrophone: recordMicrophone,
			videoCodec: videoCodec
		)
	}
}
