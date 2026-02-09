import AppKit
import SwiftUI

@MainActor
final class LowStorageWarningWindowController: NSObject, NSWindowDelegate {
  static let shared = LowStorageWarningWindowController()

  private var window: NSWindow?

  func show(warningMessage: String) {
    if window == nil {
      let view = LowStorageWarningView(
        warningMessage: warningMessage,
        openSettings: {
          SettingsWindowController.shared.show()
        },
        close: { [weak self] in
          self?.window?.close()
        }
      )
      let hostingController = NSHostingController(rootView: view)

      let window = NSWindow(contentViewController: hostingController)
      window.title = "Warning"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 520, height: 340))
      window.center()
      window.delegate = self
      self.window = window
    } else if let hostingController = window?.contentViewController as? NSHostingController<LowStorageWarningView> {
      hostingController.rootView = LowStorageWarningView(
        warningMessage: warningMessage,
        openSettings: {
          SettingsWindowController.shared.show()
        },
        close: { [weak self] in
          self?.window?.close()
        }
      )
    }

    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func closeIfNeeded() {
    window?.close()
  }
}
