import Defaults
@testable import Rewind
import XCTest

final class AppTriggerSettingsTests: XCTestCase {
	override func setUp() {
		super.setUp()
		Defaults.reset(.appTriggerEnabled, .watchedAppBundleIDs)
	}

	override func tearDown() {
		Defaults.reset(.appTriggerEnabled, .watchedAppBundleIDs)
		super.tearDown()
	}

	func testAppTriggerIsOffAndHasNoAppsByDefault() {
		XCTAssertFalse(Defaults[.appTriggerEnabled])
		XCTAssertEqual(Defaults[.watchedAppBundleIDs], [])
	}

	func testTheSettingsCanBeWrittenAndReadBack() {
		Defaults[.appTriggerEnabled] = true
		Defaults[.watchedAppBundleIDs] = ["com.apple.TextEdit", "com.example.game"]

		XCTAssertTrue(Defaults[.appTriggerEnabled])
		XCTAssertEqual(Defaults[.watchedAppBundleIDs], ["com.apple.TextEdit", "com.example.game"])
	}
}
