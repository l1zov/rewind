import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
  static let shared = OnboardingWindowController()

  private let shownKey = "ui.onboarding.shown.v1"
  private var window: NSWindow?

  func showIfNeeded() {
    guard UserDefaults.standard.bool(forKey: shownKey) == false else { return }
    UserDefaults.standard.set(true, forKey: shownKey)
    show()
  }

  private func show() {
    if window == nil {
      let view = OnboardingView(
        openSettings: {
          SettingsWindowController.shared.show()
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
