import AppKit

/// Starts and stops recording for the apps the user picked ("record while an app
/// is open"). The decision is `AppTriggerTracker`'s; this class gathers the
/// running apps and reacts to launch and quit events, plus a short tick so the
/// stop grace expires, background (`LSUIElement`) apps are noticed, and a
/// running capture follows the app when it moves to another display.
@MainActor
final class AppTriggerController {
	/// Wait before retrying a start that failed for a reason that can clear up
	/// (a transient capture error).
	static let startRetryCooldown: TimeInterval = 10
	/// Shorter wait when the app is open but has no visible window yet.
	static let noWindowCooldown: TimeInterval = 3
	private static let stopGrace: TimeInterval = 5
	private static let tickInterval: TimeInterval = 2

	var onStart: (() -> Void)?
	var onStop: (() -> Void)?
	/// The watched apps changed while recording (a new process, or a move to
	/// another display), so the capture needs a new filter.
	var onTargetChanged: (() -> Void)?

	private var tracker = AppTriggerTracker(stopGrace: AppTriggerController.stopGrace)
	private var targetMonitor = CaptureTargetMonitor()
	private var isEnabled = false
	private var watched: Set<String> = []
	private var cooldownUntil: Date?
	private var timer: Timer?
	private var observers: [NSObjectProtocol] = []

	var isRecording: Bool { tracker.isRecording }

	/// The processes and display the watched apps are on right now.
	func currentTarget() -> WatchedTarget {
		WatchedWindowLocator.target(forBundleIDs: watched)
	}

	func configure(enabled: Bool, watched: Set<String>) {
		self.watched = watched
		let wasEnabled = isEnabled
		isEnabled = enabled

		if enabled {
			if !wasEnabled { startObserving() }
			evaluate()
		} else if wasEnabled {
			stopObserving()
			let wasRecording = tracker.isRecording
			tracker = AppTriggerTracker(stopGrace: Self.stopGrace)
			targetMonitor.reset()
			cooldownUntil = nil
			if wasRecording { onStop?() }
		}
	}

	/// A capture is running for `target`; watch for the apps moving away from it.
	func captureStarted(for target: WatchedTarget) {
		targetMonitor.captureStarted(for: target)
	}

	/// No capture is running any more, so there is nothing to follow.
	func captureStopped() {
		targetMonitor.reset()
	}

	/// Tells the controller a start attempt failed. A retryable failure is tried
	/// again on a later tick, after `cooldown`. Anything else (for example a
	/// missing permission) waits until the watched app is reopened.
	func startFailed(retryable: Bool, cooldown: TimeInterval = AppTriggerController.startRetryCooldown) {
		targetMonitor.reset()
		guard retryable else { return }
		tracker.reset()
		cooldownUntil = Date().addingTimeInterval(cooldown)
	}

	private func evaluate(now: Date = Date()) {
		guard isEnabled else { return }
		if let cooldownUntil, now < cooldownUntil, !tracker.isRecording { return }

		let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))

		switch tracker.update(watched: watched, running: running, now: now) {
		case .start:
			onStart?()
		case .stop:
			targetMonitor.reset()
			onStop?()
		case .none:
			if tracker.isRecording, targetMonitor.isTracking, targetMonitor.needsRestart(for: currentTarget()) {
				onTargetChanged?()
			}
		}
	}

	private func startObserving() {
		let center = NSWorkspace.shared.notificationCenter
		let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
		observers = names.map { name in
			center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				Task { @MainActor in self?.evaluate() }
			}
		}
		timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
			Task { @MainActor in self?.evaluate() }
		}
	}

	private func stopObserving() {
		let center = NSWorkspace.shared.notificationCenter
		observers.forEach { center.removeObserver($0) }
		observers = []
		timer?.invalidate()
		timer = nil
	}
}
