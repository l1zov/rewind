import CoreGraphics
@testable import Rewind
import XCTest

final class WatchedWindowLocatorTests: XCTestCase {
	private let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

	/// A window dictionary shaped like the ones `CGWindowListCopyWindowInfo` returns.
	private func entry(
		pid: Int32,
		frame: CGRect,
		layer: Int = 0,
		alpha: Double = 1,
		onScreen: Bool = true
	) -> [String: Any] {
		[
			kCGWindowOwnerPID as String: pid,
			kCGWindowLayer as String: layer,
			kCGWindowAlpha as String: alpha,
			kCGWindowIsOnscreen as String: onScreen,
			kCGWindowBounds as String: frame.dictionaryRepresentation,
		]
	}

	func testKeepsOnlyWindowsOwnedByTheGivenProcesses() {
		let info = [entry(pid: 10, frame: frame), entry(pid: 99, frame: frame)]

		let windows = WatchedWindowLocator.windows(in: info, ownedBy: [10])

		XCTAssertEqual(windows, [WatchedWindow(processID: 10, frame: frame)])
	}

	func testKeepsTheFrontToBackOrder() {
		let front = CGRect(x: 2000, y: 100, width: 900, height: 700)
		let back = CGRect(x: 100, y: 100, width: 900, height: 700)
		let info = [entry(pid: 10, frame: front), entry(pid: 11, frame: back)]

		let windows = WatchedWindowLocator.windows(in: info, ownedBy: [10, 11])

		XCTAssertEqual(windows.map(\.frame), [front, back])
	}

	func testIgnoresWindowsAboveTheNormalLayer() {
		let info = [entry(pid: 10, frame: frame, layer: 25)]

		XCTAssertEqual(WatchedWindowLocator.windows(in: info, ownedBy: [10]), [])
	}

	func testIgnoresInvisibleAndOffScreenWindows() {
		let info = [
			entry(pid: 10, frame: frame, alpha: 0),
			entry(pid: 10, frame: frame, onScreen: false),
		]

		XCTAssertEqual(WatchedWindowLocator.windows(in: info, ownedBy: [10]), [])
	}

	func testIgnoresTinyWindows() {
		let tiny = CGRect(x: 100, y: 100, width: 20, height: 20)
		let info = [entry(pid: 10, frame: tiny)]

		XCTAssertEqual(WatchedWindowLocator.windows(in: info, ownedBy: [10]), [])
	}

	func testSkipsEntriesWithoutUsableBounds() {
		let info: [[String: Any]] = [
			[kCGWindowOwnerPID as String: Int32(10), kCGWindowLayer as String: 0],
			[kCGWindowOwnerPID as String: Int32(10), kCGWindowLayer as String: 0, kCGWindowBounds as String: "nope"],
		]

		XCTAssertEqual(WatchedWindowLocator.windows(in: info, ownedBy: [10]), [])
	}
}
