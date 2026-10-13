import CoreGraphics

/// Decides when a running app-triggered capture has to be rebuilt because the
/// watched apps changed: a new process appeared (a relaunch, a second window
/// owner), the app moved to another display, or its display changed size.
///
/// Rebuilding is what makes the recording take the new display's resolution and
/// aspect ratio. A move to another display (or a resolution change) has to hold
/// for `displayConfirmations` consecutive checks, so dragging a window across the
/// screens doesn't restart the capture (which restarts the rolling buffer) on
/// every step.
struct CaptureTargetMonitor {
	/// A display together with its size, so another monitor on the same port and a
	/// resolution change on the same display both count as a change.
	private struct DisplayKey: Equatable {
		let id: CGDirectDisplayID
		let pixelSize: CGSize?
	}

	let displayConfirmations: Int
	private var applied: WatchedTarget?
	private var pendingDisplay: DisplayKey?
	private var pendingCount = 0

	init(displayConfirmations: Int = 2) {
		self.displayConfirmations = displayConfirmations
	}

	/// Whether a running capture is being followed. Lets callers skip the (not
	/// free) lookup of the apps' current target while nothing is recording.
	var isTracking: Bool { applied != nil }

	/// The capture was (re)built for `target`.
	mutating func captureStarted(for target: WatchedTarget) {
		applied = target
		clearPending()
	}

	/// No capture is running; stop watching for changes.
	mutating func reset() {
		applied = nil
		clearPending()
	}

	/// - Returns: true when the running capture should be rebuilt for `target`.
	///   The monitor then adopts `target`, so one change is reported once.
	mutating func needsRestart(for target: WatchedTarget) -> Bool {
		guard let applied, !target.processIDs.isEmpty else { return false }

		// A process we aren't capturing has appeared. Losing one while others
		// remain needs nothing: the filter still covers the survivors.
		if !target.processIDs.isSubset(of: applied.processIDs) {
			adopt(target)
			return true
		}

		guard let display = Self.displayKey(of: target), display != Self.displayKey(of: applied) else {
			clearPending()
			return false
		}
		if display == pendingDisplay {
			pendingCount += 1
		} else {
			pendingDisplay = display
			pendingCount = 1
		}
		guard pendingCount >= displayConfirmations else { return false }
		adopt(target)
		return true
	}

	private static func displayKey(of target: WatchedTarget) -> DisplayKey? {
		target.displayID.map { DisplayKey(id: $0, pixelSize: target.displayPixelSize) }
	}

	private mutating func adopt(_ target: WatchedTarget) {
		applied = target
		clearPending()
	}

	private mutating func clearPending() {
		pendingDisplay = nil
		pendingCount = 0
	}
}
