import CoreGraphics
@testable import Rewind
import XCTest

final class CaptureTargetMonitorTests: XCTestCase {
	private func target(_ pids: [pid_t], display: CGDirectDisplayID?, size: CGSize? = nil) -> WatchedTarget {
		WatchedTarget(processIDs: Set(pids), displayID: display, displayPixelSize: size)
	}

	private let macbook = CGSize(width: 3024, height: 1964)
	private let monitor1440 = CGSize(width: 2560, height: 1440)
	private let ultrawide = CGSize(width: 3440, height: 1440)

	func testNeverRestartsBeforeACaptureStarted() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)

		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 1)))
	}

	func testSameTargetNeverRestarts() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1))

		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 1)))
		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 1)))
	}

	func testANewProcessRestartsImmediately() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1))

		XCTAssertTrue(monitor.needsRestart(for: target([10, 11], display: 1)))
	}

	func testARelaunchedProcessWithTheSameBundleRestarts() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1))

		XCTAssertTrue(monitor.needsRestart(for: target([12], display: 1)))
	}

	func testLosingOneOfSeveralProcessesDoesNotRestart() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10, 11], display: 1))

		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 1)))
	}

	func testNoWindowsDoesNotRestart() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1))

		XCTAssertFalse(monitor.needsRestart(for: target([], display: nil)))
	}

	func testMovingToAnotherDisplayNeedsConsecutiveConfirmations() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1))

		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 2)))
		XCTAssertTrue(monitor.needsRestart(for: target([10], display: 2)))
	}

	func testMovingToADisplayWithAnotherAspectRatioRestarts() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1, size: macbook))

		let onUltrawide = target([10], display: 2, size: ultrawide)
		XCTAssertFalse(monitor.needsRestart(for: onUltrawide))
		XCTAssertTrue(monitor.needsRestart(for: onUltrawide))
	}

	func testAResolutionChangeOnTheSameDisplayRestartsOnceItHolds() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1, size: macbook))

		let changed = target([10], display: 1, size: monitor1440)
		XCTAssertFalse(monitor.needsRestart(for: changed))
		XCTAssertTrue(monitor.needsRestart(for: changed))
	}

	func testTheSamePixelSizeOnTheSameDisplayNeverRestarts() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1, size: macbook))

		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 1, size: macbook)))
		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 1, size: macbook)))
	}

	func testASizeThatKeepsChangingNeverSettles() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1, size: macbook))

		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 1, size: monitor1440)))
		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 1, size: ultrawide)))
	}

	func testDraggingAcrossDisplaysDoesNotRestartUntilItSettles() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1))

		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 2)))
		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 1)))
		XCTAssertFalse(monitor.needsRestart(for: target([10], display: 2)))
	}

	func testARestartAdoptsTheNewTargetSoItFiresOnlyOnce() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1))
		XCTAssertTrue(monitor.needsRestart(for: target([10, 11], display: 1)))

		XCTAssertFalse(monitor.needsRestart(for: target([10, 11], display: 1)))
	}

	func testIsTrackingOnlyBetweenStartAndReset() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		XCTAssertFalse(monitor.isTracking)

		monitor.captureStarted(for: target([10], display: 1))
		XCTAssertTrue(monitor.isTracking)

		monitor.reset()
		XCTAssertFalse(monitor.isTracking)
	}

	func testResetForgetsTheAppliedTarget() {
		var monitor = CaptureTargetMonitor(displayConfirmations: 2)
		monitor.captureStarted(for: target([10], display: 1))

		monitor.reset()

		XCTAssertFalse(monitor.needsRestart(for: target([11], display: 2)))
	}
}
