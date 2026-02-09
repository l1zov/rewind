import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var menuBarController: MenuBarController?
  private let hotkeyManager = GlobalHotkeyManager.shared
  private var appActiveObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()
  private var lowStorageWarningActive = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    menuBarController = MenuBarController(appState: AppState.shared)
    hotkeyManager.register(
      saveReplayHotkey: AppState.shared.hotkey,
      recordToggleHotkey: AppState.shared.startRecordingHotkey
    )
    OnboardingWindowController.shared.showIfNeeded()
    appActiveObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        AppState.shared.refreshPermissions()
      }
    }

    AppState.shared.$lowStorageWarningMessage
      .receive(on: DispatchQueue.main)
      .sink { [weak self] warningMessage in
        guard let self else { return }
        if let warningMessage {
          if lowStorageWarningActive == false {
            lowStorageWarningActive = true
            LowStorageWarningWindowController.shared.show(warningMessage: warningMessage)
          }
        } else {
          lowStorageWarningActive = false
          LowStorageWarningWindowController.shared.closeIfNeeded()
        }
      }
      .store(in: &cancellables)
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let appActiveObserver {
      NotificationCenter.default.removeObserver(appActiveObserver)
    }
  }
}
