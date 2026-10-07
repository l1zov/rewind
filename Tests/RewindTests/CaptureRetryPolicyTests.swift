@testable import Rewind
import XCTest

final class CaptureRetryPolicyTests: XCTestCase {
	func testDelayBacksOffExponentiallyAndCaps() {
		XCTAssertEqual(CaptureRetryPolicy.delay(forAttempt: 1), 2)
		XCTAssertEqual(CaptureRetryPolicy.delay(forAttempt: 2), 4)
		XCTAssertEqual(CaptureRetryPolicy.delay(forAttempt: 3), 8)
		XCTAssertEqual(CaptureRetryPolicy.delay(forAttempt: 6), 60)
		XCTAssertEqual(CaptureRetryPolicy.delay(forAttempt: 500), 60)
		XCTAssertEqual(CaptureRetryPolicy.delay(forAttempt: 0), 2)
	}

	func testDoesNotRetryWhenScreenRecordingIsDenied() {
		XCTAssertFalse(CaptureRetryPolicy.shouldRetry(after: PermissionError.screenRecordingDenied))
	}

	func testRetriesOtherFailures() {
		XCTAssertTrue(CaptureRetryPolicy.shouldRetry(after: CaptureError.noDisplay))
		XCTAssertTrue(CaptureRetryPolicy.shouldRetry(after: CaptureError.streamStopped(reason: nil)))
		XCTAssertTrue(CaptureRetryPolicy.shouldRetry(after: URLError(.timedOut)))
	}
}
