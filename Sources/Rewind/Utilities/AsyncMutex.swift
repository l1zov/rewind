import Foundation

/// A FIFO mutual-exclusion lock that can be held across `await`s.
///
/// Actors do not give mutual exclusion across suspension points: two calls into
/// the same actor can interleave at every `await`. Where a multi-step async
/// operation must not overlap with another (stream start/stop, writer rotation),
/// wrap it in `withLock`. Waiters are resumed in arrival order.
///
/// Not reentrant: acquiring it again from inside `withLock` deadlocks.
final class AsyncMutex: @unchecked Sendable {
	private let state = NSLock()
	private var locked = false
	private var waiters: [CheckedContinuation<Void, Never>] = []

	func lock() async {
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			state.lock()
			if locked {
				waiters.append(continuation)
				state.unlock()
			} else {
				locked = true
				state.unlock()
				continuation.resume()
			}
		}
	}

	func unlock() {
		state.lock()
		if waiters.isEmpty {
			locked = false
			state.unlock()
		} else {
			let next = waiters.removeFirst()
			state.unlock()
			// Ownership passes straight to the next waiter; `locked` stays true.
			next.resume()
		}
	}

	/// The body runs on the caller's actor (via `isolation`), so it can freely use
	/// that actor's state; only the lock itself is shared across isolation domains.
	func withLock<T>(
		isolation: isolated (any Actor)? = #isolation,
		_ body: () async throws -> T
	) async rethrows -> T {
		await lock()
		defer { unlock() }
		return try await body()
	}
}
