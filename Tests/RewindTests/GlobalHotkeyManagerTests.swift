@testable import Rewind
import XCTest

@MainActor
final class GlobalHotkeyManagerTests: XCTestCase {
	func testDispatchesByHotKeyIDWithoutNeedingTheOriginalEvent() {
		let manager = GlobalHotkeyManager()
		var saves = 0
		var toggles = 0
		manager.configureActions(onSaveReplay: { saves += 1 }, onRecordToggle: { toggles += 1 })

		manager.handleHotKey(signature: manager.hotKeySignature, id: 1)
		manager.handleHotKey(signature: manager.hotKeySignature, id: 2)
		manager.handleHotKey(signature: manager.hotKeySignature, id: 2)

		XCTAssertEqual(saves, 1)
		XCTAssertEqual(toggles, 2)
	}

	func testIgnoresForeignSignaturesAndUnknownIDs() {
		let manager = GlobalHotkeyManager()
		var fired = 0
		manager.configureActions(onSaveReplay: { fired += 1 }, onRecordToggle: { fired += 1 })

		manager.handleHotKey(signature: manager.hotKeySignature &+ 1, id: 1)
		manager.handleHotKey(signature: manager.hotKeySignature, id: 99)

		XCTAssertEqual(fired, 0)
	}
}
