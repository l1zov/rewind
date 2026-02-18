import AppKit
import Combine

@MainActor
final class AppLifecycleController {
  private let appState: AppState
  private let hotkeyManager: GlobalHotkeyManager
  private var windowCoordinator: WindowCoordinator?
  private var menuBarController: MenuBarController?

  private var appActiveObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()
  private var lowStorageWarningActive = false
  private var hasStarted = false

  init(
    appState: AppState,
    hotkeyManager: GlobalHotkeyManager
  ) {
    self.appState = appState
    self.hotkeyManager = hotkeyManager
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true

    NSApp.setActivationPolicy(.accessory)
    ensureUIControllers()
    configureHotkeys()
    observeApplicationState()

    windowCoordinator?.showOnboardingIfNeeded()
    appState.startAlwaysRecording()
  }

  func stop() {
    guard hasStarted else { return }
    hasStarted = false

    if let appActiveObserver {
      NotificationCenter.default.removeObserver(appActiveObserver)
      self.appActiveObserver = nil
    }

    hotkeyManager.configureActions(onSaveReplay: nil, onRecordToggle: nil)
    hotkeyManager.unregister()
    windowCoordinator?.closeLowStorageWarningIfNeeded()
    cancellables.removeAll()
    menuBarController = nil
    windowCoordinator = nil
  }

  private func ensureUIControllers() {
    guard windowCoordinator == nil else { return }

    let windowCoordinator = WindowCoordinator(appState: appState)
    self.windowCoordinator = windowCoordinator
    menuBarController = MenuBarController(
      appState: appState,
      onOpenSettings: {
        windowCoordinator.showSettings()
      }
    )
  }

  private func configureHotkeys() {
    hotkeyManager.configureActions(
      onSaveReplay: { [weak appState] in
        appState?.saveReplay()
      },
      onRecordToggle: { [weak appState] in
        appState?.toggleCapture()
      }
    )

    hotkeyManager.register(
      saveReplayHotkey: appState.hotkey,
      recordToggleHotkey: appState.startRecordingHotkey
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
  }
}
