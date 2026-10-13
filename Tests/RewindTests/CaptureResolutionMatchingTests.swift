@testable import Rewind
import XCTest

final class CaptureResolutionMatchingTests: XCTestCase {
	func testNativeFollowsTheCapturedDisplayNotTheOneItWasPickedOn() {
		let macbookNative = CaptureResolution.native(width: 3024, height: 1964)

		let matched = macbookNative.matching(nativeWidth: 2560, nativeHeight: 1440)

		XCTAssertTrue(matched.isNative)
		XCTAssertEqual(matched.width, 2560)
		XCTAssertEqual(matched.height, 1440)
	}

	func testAScaledPresetKeepsItsHeightAndTakesTheTargetsAspectRatio() {
		let preset = CaptureResolution.scaled(label: "1080p", width: 1662, height: 1080)

		let matched = preset.matching(nativeWidth: 2560, nativeHeight: 1440)

		XCTAssertFalse(matched.isNative)
		XCTAssertEqual(matched.width, 1920)
		XCTAssertEqual(matched.height, 1080)
		XCTAssertTrue(matched.label.hasPrefix("1080p"))
	}

	func testAPresetOnTheSameDisplayIsUnchanged() {
		let preset = CaptureResolution.scaled(label: "1080p", width: 1662, height: 1080)

		let matched = preset.matching(nativeWidth: 3024, nativeHeight: 1964)

		XCTAssertEqual(matched.width, 1662)
		XCTAssertEqual(matched.height, 1080)
	}

	func testAPresetTallerThanTheTargetFallsBackToItsNative() {
		let preset = CaptureResolution.scaled(label: "QHD", width: 2304, height: 1440)

		let matched = preset.matching(nativeWidth: 1920, nativeHeight: 1080)

		XCTAssertTrue(matched.isNative)
		XCTAssertEqual(matched.width, 1920)
		XCTAssertEqual(matched.height, 1080)
	}

	func testAPresetAsTallAsTheTargetFallsBackToItsNative() {
		let preset = CaptureResolution.scaled(label: "1080p", width: 1662, height: 1080)

		XCTAssertTrue(preset.matching(nativeWidth: 1920, nativeHeight: 1080).isNative)
	}

	func testScaledWidthIsAlignedToAnEvenNumber() {
		let preset = CaptureResolution.scaled(label: "720p", width: 1108, height: 720)

		let matched = preset.matching(nativeWidth: 1366, nativeHeight: 768)

		XCTAssertEqual(matched.height, 720)
		XCTAssertEqual(matched.width % 2, 0)
		XCTAssertEqual(matched.width, 1280)
	}
}
