import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
  private let shownKey = "ui.onboarding.shown.v1"
  private let settingsWindowController: SettingsWindowController
  private let userDefaults: UserDefaults
  private var window: NSWindow?

  init(
    settingsWindowController: SettingsWindowController,
    userDefaults: UserDefaults = .standard
  ) {
    self.settingsWindowController = settingsWindowController
    self.userDefaults = userDefaults
    super.init()
  }

  func showIfNeeded() {
    guard userDefaults.bool(forKey: shownKey) == false else { return }
    userDefaults.set(true, forKey: shownKey)
    show()
  }

  private func show() {
    if window == nil {
      let view = OnboardingView(
        openSettings: {
          self.settingsWindowController.show()
        },
        close: { [weak self] in
          self?.window?.close()
        }
      )
      let hostingController = NSHostingController(rootView: view)

      let window = NSWindow(contentViewController: hostingController)
      window.title = "Onboarding"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 520, height: 340))
      window.center()
      window.delegate = self
      self.window = window
    }

    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
