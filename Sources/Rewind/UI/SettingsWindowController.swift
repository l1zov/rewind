import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  static let shared = SettingsWindowController()

  private var window: NSWindow?

  func show() {
    if window == nil {
      let settingsView = SettingsView()
        .environmentObject(AppState.shared)
      let hostingController = NSHostingController(rootView: settingsView)

      let window = NSWindow(contentViewController: hostingController)
      window.title = "Settings"
      window.styleMask = [.titled, .closable, .miniaturizable]
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 460, height: 580))
      window.center()
      window.delegate = self
      self.window = window
    }

    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
