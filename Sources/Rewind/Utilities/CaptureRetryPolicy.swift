import Foundation

/// When and how long to wait before automatically retrying a failed capture start.
enum CaptureRetryPolicy {
	static let baseDelay: TimeInterval = 2
	static let maxDelay: TimeInterval = 60

	/// 2s, 4s, 8s ... capped at 60s. `attempt` counts consecutive failures, from 1.
	static func delay(forAttempt attempt: Int) -> TimeInterval {
		let exponent = min(max(attempt, 1) - 1, 10)
		return min(baseDelay * pow(2, Double(exponent)), maxDelay)
	}

	/// A missing Screen Recording grant can't fix itself while the app is running
	/// (macOS only applies a new grant after a relaunch), so retrying is pointless
	/// and just spams the permission prompt, logs and analytics.
	static func shouldRetry(after error: Error) -> Bool {
		if case PermissionError.screenRecordingDenied = error { return false }
		return true
	}
}
