@testable import Rewind
import XCTest

final class TCCResetTests: XCTestCase {
	private final class Recorder: @unchecked Sendable {
		private let lock = NSLock()
		private var _calls: [[String]] = []
		var calls: [[String]] { lock.withLock { _calls } }
		func record(_ arguments: [String]) { lock.withLock { _calls.append(arguments) } }
	}

	func testBuildsTheTccutilArgumentsForTheMicrophoneService() {
		XCTAssertEqual(
			TCCReset.arguments(service: .microphone, bundleID: "com.example.Rewind"),
			["reset", "Microphone", "com.example.Rewind"])
	}

	func testResetMicrophoneRunsTccutilForThisAppOnly() {
		let recorder = Recorder()
		let ok = TCCReset.resetMicrophone(bundleID: "com.example.Rewind") { arguments in
			recorder.record(arguments)
			return 0
		}
		XCTAssertTrue(ok)
		XCTAssertEqual(recorder.calls, [["reset", "Microphone", "com.example.Rewind"]])
	}

	func testDoesNothingWithoutABundleIdentifier() {
		let recorder = Recorder()
		let ok = TCCReset.resetMicrophone(bundleID: nil) { arguments in
			recorder.record(arguments)
			return 0
		}
		XCTAssertFalse(ok)
		XCTAssertTrue(recorder.calls.isEmpty, "Without a bundle ID tccutil would reset every app's permission")
	}

	func testReportsFailureWhenTccutilFailsOrThrows() {
		XCTAssertFalse(TCCReset.resetMicrophone(bundleID: "com.example.Rewind") { _ in 1 })
		XCTAssertFalse(TCCReset.resetMicrophone(bundleID: "com.example.Rewind") { _ in
			throw CocoaError(.fileNoSuchFile)
		})
	}

	func testRefusesAnEmptyBundleIdentifier() {
		let recorder = Recorder()
		XCTAssertFalse(TCCReset.resetMicrophone(bundleID: "") { arguments in
			recorder.record(arguments)
			return 0
		})
		XCTAssertTrue(recorder.calls.isEmpty)
	}
}
