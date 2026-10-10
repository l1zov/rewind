@testable import Rewind
import XCTest

final class RecordingModeTests: XCTestCase {
	func testRecordingModesAreStableAndInstantReplayRemainsDefault() {
		XCTAssertEqual(RecordingMode.default, .instantReplay)
		XCTAssertEqual(RecordingMode.options, [.instantReplay, .recording])
		XCTAssertEqual(Set(RecordingMode.options.map(\.id)).count, RecordingMode.options.count)
	}

	func testGeneratedStartAndStopDefaultsAvoidExistingShortcuts() {
		let save = Hotkey.default
		let start = Hotkey.startRecordingDefault(avoiding: [save])
		let stop = Hotkey.stopRecordingDefault(avoiding: [save, start])

		XCTAssertNotEqual(start, save)
		XCTAssertNotEqual(stop, save)
		XCTAssertNotEqual(stop, start)
	}

	func testStopDefaultFallsBackWhenItsPrimaryShortcutIsAlreadyUsed() {
		let resolved = Hotkey.stopRecordingDefault(
			avoiding: [.stopRecordingDefault, .startRecordingDefault]
		)

		XCTAssertNotEqual(resolved, .stopRecordingDefault)
		XCTAssertNotEqual(resolved, .startRecordingDefault)
	}
}
