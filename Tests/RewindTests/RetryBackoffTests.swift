import Foundation
@testable import Rewind
import XCTest

final class RetryBackoffTests: XCTestCase {
	func testDelayDoublesFromTheBaseAndCaps() {
		XCTAssertEqual(RetryBackoff.delay(forAttempt: 1, base: 2, cap: 60), 2)
		XCTAssertEqual(RetryBackoff.delay(forAttempt: 2, base: 2, cap: 60), 4)
		XCTAssertEqual(RetryBackoff.delay(forAttempt: 5, base: 2, cap: 60), 32)
		XCTAssertEqual(RetryBackoff.delay(forAttempt: 6, base: 2, cap: 60), 60)
		XCTAssertEqual(RetryBackoff.delay(forAttempt: 10_000, base: 2, cap: 60), 60)
		XCTAssertEqual(RetryBackoff.delay(forAttempt: 0, base: 2, cap: 60), 2)
		XCTAssertEqual(RetryBackoff.delay(forAttempt: -3, base: 5, cap: 30), 5)
	}

	func testCaptureRetryPolicyStillUsesTheSameCurve() {
		XCTAssertEqual(CaptureRetryPolicy.delay(forAttempt: 3), RetryBackoff.delay(forAttempt: 3, base: 2, cap: 60))
	}

	func testDiscordPresenceRetryBacksOffUpToThirtySeconds() {
		XCTAssertEqual(DiscordPresenceRetry.delay(forAttempt: 1), 2)
		XCTAssertEqual(DiscordPresenceRetry.delay(forAttempt: 3), 8)
		XCTAssertEqual(DiscordPresenceRetry.delay(forAttempt: 20), 30)
	}
}
