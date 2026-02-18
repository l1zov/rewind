import AppKit

@MainActor
final class WindowCoordinator {
  private let settingsWindowController: SettingsWindowController
  private let onboardingWindowController: OnboardingWindowController
  private let lowStorageWarningWindowController: LowStorageWarningWindowController

  init(appState: AppState) {
    let settingsWindowController = SettingsWindowController(appState: appState)
    self.settingsWindowController = settingsWindowController
    onboardingWindowController = OnboardingWindowController(
      settingsWindowController: settingsWindowController
    )
    lowStorageWarningWindowController = LowStorageWarningWindowController(
      settingsWindowController: settingsWindowController
    )
  }

  func showSettings() {
    settingsWindowController.show()
  }

  func showOnboardingIfNeeded() {
    onboardingWindowController.showIfNeeded()
  }

  func showLowStorageWarning(_ warningMessage: String) {
    lowStorageWarningWindowController.show(warningMessage: warningMessage)
  }

  func closeLowStorageWarningIfNeeded() {
    lowStorageWarningWindowController.closeIfNeeded()
  }
}
