@testable import Rewind
import CoreGraphics
import XCTest

final class DisplayFollowerTests: XCTestCase {
	private let builtIn = (id: CGDirectDisplayID(1), bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
	private let external = (id: CGDirectDisplayID(2), bounds: CGRect(x: 1512, y: -200, width: 2560, height: 1440))

	func testPicksDisplayContainingWindow() {
		let window = CGRect(x: 1700, y: 100, width: 800, height: 600)
		XCTAssertEqual(DisplayFollower.bestDisplay(for: window, among: [builtIn, external]), 2)
	}

	func testPicksDisplayWithLargestOverlapForStraddlingWindow() {
		let mostlyBuiltIn = CGRect(x: 1000, y: 100, width: 600, height: 400)
		XCTAssertEqual(DisplayFollower.bestDisplay(for: mostlyBuiltIn, among: [builtIn, external]), 1)

		let mostlyExternal = CGRect(x: 1400, y: 100, width: 600, height: 400)
		XCTAssertEqual(DisplayFollower.bestDisplay(for: mostlyExternal, among: [builtIn, external]), 2)
	}

	func testReturnsNilForOffscreenWindow() {
		let offscreen = CGRect(x: -5000, y: -5000, width: 100, height: 100)
		XCTAssertNil(DisplayFollower.bestDisplay(for: offscreen, among: [builtIn, external]))
	}
}

final class DisplaySwitchDebouncerTests: XCTestCase {
	private let start = DisplayFollowLocation(pid: 10, displayID: 1)
	private let external = DisplayFollowLocation(pid: 10, displayID: 2)

	func testSwitchesAfterTwoConsecutiveSamples() {
		var debouncer = DisplaySwitchDebouncer(current: start)
		XCTAssertNil(debouncer.observe(external))
		XCTAssertEqual(debouncer.observe(external), external)
	}

	func testSingleSampleBlipDoesNotSwitch() {
		var debouncer = DisplaySwitchDebouncer(current: start)
		XCTAssertNil(debouncer.observe(external))
		XCTAssertNil(debouncer.observe(start))
		XCTAssertNil(debouncer.observe(external))
	}

	func testUnknownLocationResetsPending() {
		var debouncer = DisplaySwitchDebouncer(current: start)
		XCTAssertNil(debouncer.observe(external))
		XCTAssertNil(debouncer.observe(nil))
		XCTAssertNil(debouncer.observe(external))
		XCTAssertEqual(debouncer.observe(external), external)
	}

	func testNoSwitchBackAfterSwitchIsRecorded() {
		var debouncer = DisplaySwitchDebouncer(current: start)
		_ = debouncer.observe(external)
		let next = debouncer.observe(external)
		XCTAssertEqual(next, external)
		debouncer.didSwitch(to: external)
		XCTAssertNil(debouncer.observe(external))
		XCTAssertNil(debouncer.observe(external))
	}

	func testFailedSwitchIsRetried() {
		var debouncer = DisplaySwitchDebouncer(current: start)
		_ = debouncer.observe(external)
		XCTAssertEqual(debouncer.observe(external), external)
		// updateContentFilter failed, so didSwitch was not called: try again.
		XCTAssertNil(debouncer.observe(external))
		XCTAssertEqual(debouncer.observe(external), external)
	}

	func testRelaunchedAppOnSameDisplaySwitchesProcess() {
		var debouncer = DisplaySwitchDebouncer(current: start)
		let relaunched = DisplayFollowLocation(pid: 99, displayID: 1)
		XCTAssertNil(debouncer.observe(relaunched))
		XCTAssertEqual(debouncer.observe(relaunched), relaunched)
	}
}
