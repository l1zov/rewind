import Foundation

/// Runs an async job one at a time, collapsing requests that arrive while it is
/// running into a single follow-up run.
///
/// Used for silent capture restarts: changing two settings in quick succession
/// would otherwise start two overlapping stop/start sequences. Because the
/// follow-up run happens after the in-flight one finishes, it reads the latest
/// settings.
@MainActor
final class RestartCoalescer {
	private var isRunning = false
	private var hasPendingRequest = false
	private var completions: [@MainActor () -> Void] = []

	/// - Parameter completion: called once the run that covers this request has
	///   finished (for a merged request, that is the follow-up run).
	func request(
		_ work: @escaping @MainActor () async -> Void,
		completion: (@MainActor () -> Void)? = nil
	) {
		if let completion { completions.append(completion) }
		if isRunning {
			hasPendingRequest = true
			return
		}
		isRunning = true
		Task { @MainActor in
			repeat {
				hasPendingRequest = false
				await work()
			} while hasPendingRequest
			isRunning = false
			let finished = completions
			completions = []
			finished.forEach { $0() }
		}
	}
}
