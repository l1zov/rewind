import CoreGraphics
@testable import Rewind
import XCTest

final class DisplaySelectionTests: XCTestCase {
	/// The MacBook screen is the main display; the external monitor sits to its right.
	private let main = DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
	private let external = DisplayGeometry(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))
	private var displays: [DisplayGeometry] { [main, external] }

	func testWindowOnTheMainDisplayPicksIt() {
		let window = CGRect(x: 100, y: 100, width: 800, height: 600)

		XCTAssertEqual(DisplaySelection.displayID(forWindows: [window], displays: displays), 1)
	}

	func testWindowOnTheExternalDisplayPicksItEvenThoughMainComesFirst() {
		let window = CGRect(x: 2000, y: 100, width: 1600, height: 900)

		XCTAssertEqual(DisplaySelection.displayID(forWindows: [window], displays: displays), 2)
	}

	func testWindowStraddlingTwoDisplaysPicksTheOneHoldingMostOfIt() {
		let mostlyExternal = CGRect(x: 1212, y: 100, width: 1000, height: 600)
		let mostlyMain = CGRect(x: 800, y: 100, width: 1000, height: 600)

		XCTAssertEqual(DisplaySelection.displayID(forWindows: [mostlyExternal], displays: displays), 2)
		XCTAssertEqual(DisplaySelection.displayID(forWindows: [mostlyMain], displays: displays), 1)
	}

	func testTheFrontmostSubstantialWindowDecidesWhenWindowsAreOnDifferentDisplays() {
		let onMain = CGRect(x: 100, y: 100, width: 1000, height: 700)
		let onExternal = CGRect(x: 2000, y: 100, width: 1200, height: 800)

		// The list is front to back, so the first window is the focused one.
		XCTAssertEqual(DisplaySelection.displayID(forWindows: [onExternal, onMain], displays: displays), 2)
		XCTAssertEqual(DisplaySelection.displayID(forWindows: [onMain, onExternal], displays: displays), 1)
	}

	func testASmallOverlayInFrontDoesNotDecideTheDisplay() {
		let overlay = CGRect(x: 20, y: 20, width: 200, height: 100)
		let game = CGRect(x: 1600, y: 0, width: 2400, height: 1350)

		XCTAssertEqual(DisplaySelection.displayID(forWindows: [overlay, game], displays: displays), 2)
	}

	func testExactTieFavorsTheEarlierDisplay() {
		let window = CGRect(x: 1012, y: 100, width: 1000, height: 600)

		XCTAssertEqual(DisplaySelection.displayID(forWindows: [window], displays: displays), 1)
	}

	func testNoWindowsGivesNil() {
		XCTAssertNil(DisplaySelection.displayID(forWindows: [], displays: displays))
	}

	func testNoDisplaysGivesNil() {
		let window = CGRect(x: 100, y: 100, width: 800, height: 600)

		XCTAssertNil(DisplaySelection.displayID(forWindows: [window], displays: []))
	}

	func testWindowOffEveryDisplayGivesNil() {
		let window = CGRect(x: -5000, y: -5000, width: 800, height: 600)

		XCTAssertNil(DisplaySelection.displayID(forWindows: [window], displays: displays))
	}

	func testZeroSizedWindowsAreIgnored() {
		let empty = CGRect(x: 2000, y: 100, width: 0, height: 0)
		let real = CGRect(x: 100, y: 100, width: 800, height: 600)

		XCTAssertEqual(DisplaySelection.displayID(forWindows: [empty, real], displays: displays), 1)
	}
}
