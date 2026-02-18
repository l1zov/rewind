import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let compositionRoot = AppCompositionRoot.shared

  func applicationDidFinishLaunching(_ notification: Notification) {
    compositionRoot.lifecycleController.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    compositionRoot.lifecycleController.stop()
  }
}
