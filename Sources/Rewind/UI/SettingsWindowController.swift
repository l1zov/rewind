import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  private let appState: AppState
  private var window: NSWindow?

  init(appState: AppState) {
    self.appState = appState
    super.init()
  }

  func show() {
    if window == nil {
      let settingsView = SettingsView(appState: appState)
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
