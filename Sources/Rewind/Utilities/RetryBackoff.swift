import Foundation

/// Exponential backoff: `base`, 2x`base`, 4x`base` ... capped at `cap` seconds.
/// `attempt` counts consecutive failures, starting at 1.
enum RetryBackoff {
	static func delay(forAttempt attempt: Int, base: TimeInterval, cap: TimeInterval) -> TimeInterval {
		let exponent = min(max(attempt, 1) - 1, 10)
		return min(base * pow(2, Double(exponent)), cap)
	}
}

/// How long to wait before retrying a failed Discord Rich Presence publish. A
/// fixed 2 s retry used to hammer the local IPC sockets and loopback WebSocket
/// ports forever when Discord isn't running.
enum DiscordPresenceRetry {
	static func delay(forAttempt attempt: Int) -> TimeInterval {
		RetryBackoff.delay(forAttempt: attempt, base: 2, cap: 30)
	}
}
