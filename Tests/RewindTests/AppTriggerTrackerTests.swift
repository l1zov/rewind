@testable import Rewind
import XCTest

final class AppTriggerTrackerTests: XCTestCase {
	private let t0 = Date(timeIntervalSince1970: 1_000)
	private let game = "com.example.game"
	private let other = "com.example.other"

	func testNothingWatchedNeverStarts() {
		var tracker = AppTriggerTracker(stopGrace: 5)

		XCTAssertEqual(tracker.update(watched: [], running: [game], now: t0), .none)
		XCTAssertFalse(tracker.isRecording)
	}

	func testStartsWhenWatchedAppIsRunning() {
		var tracker = AppTriggerTracker(stopGrace: 5)

		XCTAssertEqual(tracker.update(watched: [game], running: [game], now: t0), .start)
		XCTAssertTrue(tracker.isRecording)
	}

	func testUnwatchedAppDoesNotStart() {
		var tracker = AppTriggerTracker(stopGrace: 5)

		XCTAssertEqual(tracker.update(watched: [game], running: [other], now: t0), .none)
		XCTAssertFalse(tracker.isRecording)
	}

	func testStartsOnlyOnce() {
		var tracker = AppTriggerTracker(stopGrace: 5)

		XCTAssertEqual(tracker.update(watched: [game], running: [game], now: t0), .start)
		XCTAssertEqual(tracker.update(watched: [game], running: [game], now: t0.addingTimeInterval(1)), .none)
	}

	func testStopsOnlyAfterTheGracePeriod() {
		var tracker = AppTriggerTracker(stopGrace: 5)
		_ = tracker.update(watched: [game], running: [game], now: t0)

		XCTAssertEqual(tracker.update(watched: [game], running: [], now: t0.addingTimeInterval(1)), .none)
		XCTAssertEqual(tracker.update(watched: [game], running: [], now: t0.addingTimeInterval(5)), .none)
		XCTAssertEqual(tracker.update(watched: [game], running: [], now: t0.addingTimeInterval(6)), .stop)
		XCTAssertFalse(tracker.isRecording)
	}

	func testQuickRelaunchInsideTheGraceDoesNotChurn() {
		var tracker = AppTriggerTracker(stopGrace: 5)
		_ = tracker.update(watched: [game], running: [game], now: t0)

		XCTAssertEqual(tracker.update(watched: [game], running: [], now: t0.addingTimeInterval(1)), .none)
		XCTAssertEqual(tracker.update(watched: [game], running: [game], now: t0.addingTimeInterval(3)), .none)
		XCTAssertEqual(tracker.update(watched: [game], running: [game], now: t0.addingTimeInterval(20)), .none)
		XCTAssertTrue(tracker.isRecording)
	}

	func testStopIsEmittedOnceWhenTheAppStaysClosed() {
		var tracker = AppTriggerTracker(stopGrace: 5)
		_ = tracker.update(watched: [game], running: [game], now: t0)
		_ = tracker.update(watched: [game], running: [], now: t0.addingTimeInterval(1))

		XCTAssertEqual(tracker.update(watched: [game], running: [], now: t0.addingTimeInterval(7)), .stop)
		XCTAssertEqual(tracker.update(watched: [game], running: [], now: t0.addingTimeInterval(8)), .none)
	}

	func testASecondWatchedAppDoesNotRestartRecording() {
		var tracker = AppTriggerTracker(stopGrace: 5)
		_ = tracker.update(watched: [game, other], running: [game], now: t0)

		XCTAssertEqual(tracker.update(watched: [game, other], running: [game, other], now: t0.addingTimeInterval(1)), .none)
		XCTAssertTrue(tracker.isRecording)
	}

	func testResetAllowsAFailedStartToBeAttemptedAgain() {
		var tracker = AppTriggerTracker(stopGrace: 5)
		XCTAssertEqual(tracker.update(watched: [game], running: [game], now: t0), .start)

		tracker.reset()

		XCTAssertFalse(tracker.isRecording)
		XCTAssertEqual(tracker.update(watched: [game], running: [game], now: t0.addingTimeInterval(2)), .start)
	}

	func testRecordingContinuesWhileAnyWatchedAppIsStillOpen() {
		var tracker = AppTriggerTracker(stopGrace: 5)
		_ = tracker.update(watched: [game, other], running: [game], now: t0)

		XCTAssertEqual(tracker.update(watched: [game, other], running: [other], now: t0.addingTimeInterval(1)), .none)
		XCTAssertEqual(tracker.update(watched: [game, other], running: [], now: t0.addingTimeInterval(2)), .none)
		XCTAssertEqual(tracker.update(watched: [game, other], running: [], now: t0.addingTimeInterval(6)), .none)
		XCTAssertEqual(tracker.update(watched: [game, other], running: [], now: t0.addingTimeInterval(7)), .stop)
	}
}
