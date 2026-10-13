import Foundation

/// Decides when "record while an app is open" should start and stop recording.
///
/// Pure state machine, no AppKit: the caller feeds in the watched bundle IDs and
/// the bundle IDs that are running right now, and acts on the returned action.
/// Stopping waits `stopGrace` seconds after the last watched app closes, so a
/// quick relaunch (a crash, an update, a launcher restarting the game) doesn't
/// cut the recording into pieces.
struct AppTriggerTracker {
	enum Action: Equatable {
		case start
		case stop
		case none
	}

	let stopGrace: TimeInterval
	private(set) var isRecording = false
	private var closedSince: Date?

	init(stopGrace: TimeInterval) {
		self.stopGrace = stopGrace
	}

	/// - Parameters:
	///   - watched: bundle IDs the user chose to record while open.
	///   - running: bundle IDs of running apps right now.
	///   - now: the current time, passed in so tests can control it.
	mutating func update(watched: Set<String>, running: Set<String>, now: Date) -> Action {
		let wanted = !watched.isDisjoint(with: running)

		if wanted {
			closedSince = nil
			guard !isRecording else { return .none }
			isRecording = true
			return .start
		}

		guard isRecording else { return .none }
		guard let since = closedSince else {
			closedSince = now
			return .none
		}
		guard now.timeIntervalSince(since) >= stopGrace else { return .none }

		isRecording = false
		closedSince = nil
		return .stop
	}

	/// Forgets that recording started, so the next update can start it again.
	/// Used when a start attempt fails.
	mutating func reset() {
		isRecording = false
		closedSince = nil
	}
}
