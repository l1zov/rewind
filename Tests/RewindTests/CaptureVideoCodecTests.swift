import AVFoundation
@testable import Rewind
import XCTest

final class CaptureVideoCodecTests: XCTestCase {
	func testH264IsTheDefaultBecauseDiscordAndBrowsersPlayItEverywhere() {
		XCTAssertEqual(CaptureVideoCodec.default.id, "h264")
		XCTAssertEqual(CaptureVideoCodec.default.avCodec, .h264)
	}

	func testHEVCIsAnOptionOnAppleSilicon() {
		#if arch(arm64)
			XCTAssertTrue(CaptureVideoCodec.options.contains(.hevc))
		#else
			XCTAssertEqual(CaptureVideoCodec.options, [.h264], "Intel's encoder can't run a second HEVC session")
		#endif
	}

	func testUnknownIDFallsBackToDefault() {
		XCTAssertEqual(CaptureVideoCodec.resolve(id: "av1"), .default)
		XCTAssertEqual(CaptureVideoCodec.resolve(id: "h264"), .h264)
	}

	func testEncoderSettingsUseTheRequestedCodec() {
		let h264 = VideoEncoderSettings.outputSettings(
			quality: .default, width: 1920, height: 1080, frameRate: 60, codec: .h264)
		XCTAssertEqual(h264[AVVideoCodecKey] as? AVVideoCodecType, .h264)
		let h264Props = h264[AVVideoCompressionPropertiesKey] as? [String: Any]
		XCTAssertEqual(h264Props?[AVVideoProfileLevelKey] as? String, AVVideoProfileLevelH264HighAutoLevel)

		let hevc = VideoEncoderSettings.outputSettings(
			quality: .default, width: 1920, height: 1080, frameRate: 60, codec: .hevc)
		XCTAssertEqual(hevc[AVVideoCodecKey] as? AVVideoCodecType, .hevc)
		let hevcProps = hevc[AVVideoCompressionPropertiesKey] as? [String: Any]
		XCTAssertNil(hevcProps?[AVVideoProfileLevelKey])
	}
}
