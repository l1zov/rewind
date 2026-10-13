import Defaults
@testable import Rewind
import XCTest

@MainActor
final class AppTriggerModeTests: XCTestCase {
	override func setUp() {
		super.setUp()
		Defaults.reset(.appTriggerEnabled, .watchedAppBundleIDs)
	}

	override func tearDown() {
		Defaults.reset(.appTriggerEnabled, .watchedAppBundleIDs)
		super.tearDown()
	}

	/// Asleep, so enabling a mode never starts a real capture during the test.
	private func makeAppState() -> AppState {
		let appState = AppState()
		appState.handleSleep()
		return appState
	}

	func testEnablingTheAppTriggerTurnsAlwaysRecordOff() {
		let appState = makeAppState()
		appState.alwaysRecordEnabled = true

		appState.appTriggerEnabled = true

		XCTAssertTrue(appState.appTriggerEnabled)
		XCTAssertFalse(appState.alwaysRecordEnabled)
		appState.appTriggerEnabled = false
	}

	func testEnablingAlwaysRecordTurnsTheAppTriggerOff() {
		let appState = makeAppState()
		appState.appTriggerEnabled = true

		appState.alwaysRecordEnabled = true

		XCTAssertTrue(appState.alwaysRecordEnabled)
		XCTAssertFalse(appState.appTriggerEnabled)
	}

	func testStopIsLockedWhileAlwaysRecordIsOn() {
		let appState = makeAppState()
		XCTAssertFalse(appState.isStopLocked)

		appState.alwaysRecordEnabled = true

		XCTAssertTrue(appState.isStopLocked)
	}

	func testTheAppTriggerOwnsItsOwnStartsAndAutomaticOnesWhileItIsRecording() {
		XCTAssertTrue(AppState.appTriggerOwns(reason: .appTrigger, triggerIsRecording: false))
		for reason in [AnalyticsCaptureStartReason.retry, .wake, .alwaysRecord] {
			XCTAssertTrue(AppState.appTriggerOwns(reason: reason, triggerIsRecording: true))
			XCTAssertFalse(AppState.appTriggerOwns(reason: reason, triggerIsRecording: false))
		}
	}

	func testAManualStartIsNeverOwnedByTheAppTrigger() {
		XCTAssertFalse(AppState.appTriggerOwns(reason: .manual, triggerIsRecording: true))
	}

	func testTheAppTriggerAndItsAppsArePersisted() {
		let appState = makeAppState()
		appState.watchedAppBundleIDs = ["com.example.game"]
		appState.appTriggerEnabled = true

		XCTAssertTrue(Defaults[.appTriggerEnabled])
		XCTAssertEqual(Defaults[.watchedAppBundleIDs], ["com.example.game"])
		appState.appTriggerEnabled = false
	}

	func testANewAppStatePicksTheSavedSettingsUp() {
		Defaults[.watchedAppBundleIDs] = ["com.example.game"]
		Defaults[.appTriggerEnabled] = true

		let appState = makeAppState()

		XCTAssertTrue(appState.appTriggerEnabled)
		XCTAssertEqual(appState.watchedAppBundleIDs, ["com.example.game"])
		appState.appTriggerEnabled = false
	}
}
