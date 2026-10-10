import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private let compositionRoot = AppCompositionRoot.shared

	func applicationDidFinishLaunching(_: Notification) {
		// Segments left behind by a previous quit or crash (can be GBs).
		LiveSegmentCleanup.removeAll()
		compositionRoot.lifecycleController.start()
		compositionRoot.appState.trackAppOpened()
	}

	func applicationWillTerminate(_: Notification) {
		compositionRoot.lifecycleController.stop()
		LiveSegmentCleanup.removeAll()
	}
}
