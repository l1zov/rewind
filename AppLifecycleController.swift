import AppKit
import Combine

@MainActor
final class AppLifecycleController: NSObject {
	private let appState: AppState
	private let hotkeyManager: GlobalHotkeyManager
	private var windowCoordinator: WindowCoordinator?

	private var appActiveObserver: NSObjectProtocol?
	private var sleepObservers: [NSObjectProtocol] = []
	private var dockRelevantWindows = Set<ObjectIdentifier>()
	private var cancellables = Set<AnyCancellable>()
	private var lowStorageWarningActive = false
	private var hasStarted = false

	init(
		appState: AppState,
		hotkeyManager: GlobalHotkeyManager
	) {
		self.appState = appState
		self.hotkeyManager = hotkeyManager
		super.init()
	}

	func start() {
		guard !hasStarted else { return }
		hasStarted = true

		ensureUIControllers()
		configureHotkeys()
		observeApplicationState()
		observeWindowState()

		if windowCoordinator?.shouldShowOnboarding == true {
			windowCoordinator?.showOnboardingIfNeeded(onDismiss: { [weak self] in
				self?.appState.startAlwaysRecording()
			})
		} else {
			NSApp.setActivationPolicy(.accessory)
			appState.startAlwaysRecording()
		}
	}

	func showOnboarding() {
		ensureUIControllers()
		windowCoordinator?.showOnboarding()
	}

	func stop() {
		guard hasStarted else { return }
		hasStarted = false

		if let appActiveObserver {
			NotificationCenter.default.removeObserver(appActiveObserver)
			self.appActiveObserver = nil
		}
		for observer in sleepObservers {
			NSWorkspace.shared.notificationCenter.removeObserver(observer)
		}
		sleepObservers.removeAll()
		NotificationCenter.default.removeObserver(
			self,
			name: NSWindow.didBecomeKeyNotification,
			object: nil
		)
		NotificationCenter.default.removeObserver(
			self,
			name: NSWindow.willCloseNotification,
			object: nil
		)

		hotkeyManager.configureActions(
			onSaveReplay: nil,
			onStartRecording: nil,
			onStopRecording: nil
		)
		hotkeyManager.unregister()
		windowCoordinator?.closeLowStorageWarningIfNeeded()
		cancellables.removeAll()
		windowCoordinator = nil
		dockRelevantWindows.removeAll()
		NSApp.setActivationPolicy(.accessory)
	}

	private func ensureUIControllers() {
		guard windowCoordinator == nil else { return }
		windowCoordinator = WindowCoordinator()
	}

	private func configureHotkeys() {
		hotkeyManager.configureActions(
			onSaveReplay: { [weak appState] in
				appState?.saveReplay()
			},
			onStartRecording: { [weak appState] in
				appState?.startRecording()
			},
			onStopRecording: { [weak appState] in
				appState?.stopRecording()
			}
		)

		hotkeyManager.register(
			saveReplayHotkey: appState.hotkey,
			startRecordingHotkey: appState.startRecordingHotkey,
			stopRecordingHotkey: appState.stopRecordingHotkey
		)
	}

	private func observeApplicationState() {
		appActiveObserver = NotificationCenter.default.addObserver(
			forName: NSApplication.didBecomeActiveNotification,
			object: nil,
			queue: .main
		) { [weak appState] _ in
			Task { @MainActor in
				appState?.refreshPermissions()
			}
		}

		appState.$lowStorageWarningMessage
			.receive(on: DispatchQueue.main)
			.sink { [weak self] warningMessage in
				guard let self else { return }

				if let warningMessage {
					if !lowStorageWarningActive {
						lowStorageWarningActive = true
						windowCoordinator?.showLowStorageWarning(warningMessage)
					}
				} else {
					lowStorageWarningActive = false
					windowCoordinator?.closeLowStorageWarningIfNeeded()
				}
			}
			.store(in: &cancellables)

		let wsCenter = NSWorkspace.shared.notificationCenter

		let sleepNames: [NSNotification.Name] = [
			NSWorkspace.willSleepNotification,
			NSWorkspace.screensDidSleepNotification
		]
		let wakeNames: [NSNotification.Name] = [
			NSWorkspace.didWakeNotification,
			NSWorkspace.screensDidWakeNotification
		]

		for name in sleepNames {
			sleepObservers.append(
				wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak appState] _ in
					Task { @MainActor in appState?.handleSleep() }
				}
			)
		}
		for name in wakeNames {
			sleepObservers.append(
				wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak appState] _ in
					Task { @MainActor in appState?.handleWake() }
				}
			)
		}
	}

	private func observeWindowState() {
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleWindowDidBecomeKey(_:)),
			name: NSWindow.didBecomeKeyNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleWindowWillClose(_:)),
			name: NSWindow.willCloseNotification,
			object: nil
		)
	}

	@objc
	private func handleWindowDidBecomeKey(_ notification: Notification) {
		guard let window = notification.object as? NSWindow else { return }
		guard window.styleMask.contains(.titled) else { return }
		dockRelevantWindows.insert(ObjectIdentifier(window))
		updateActivationPolicyForWindowVisibility()
	}

	@objc
	private func handleWindowWillClose(_ notification: Notification) {
		guard let window = notification.object as? NSWindow else { return }
		dockRelevantWindows.remove(ObjectIdentifier(window))
		updateActivationPolicyForWindowVisibility()
	}

	private func updateActivationPolicyForWindowVisibility() {
		let targetPolicy: NSApplication.ActivationPolicy = dockRelevantWindows.isEmpty ? .accessory : .regular
		guard NSApp.activationPolicy() != targetPolicy else { return }
		NSApp.setActivationPolicy(targetPolicy)
	}
}
