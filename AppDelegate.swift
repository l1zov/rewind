import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private let compositionRoot = AppCompositionRoot.shared
	private var terminationIsReady = false
	private var terminationTask: Task<Void, Never>?

	func applicationDidFinishLaunching(_: Notification) {
		compositionRoot.lifecycleController.start()
		compositionRoot.appState.trackAppOpened()
	}

	func applicationWillTerminate(_: Notification) {
		compositionRoot.lifecycleController.stop()
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		if terminationIsReady || !compositionRoot.appState.needsCaptureShutdown {
			return .terminateNow
		}
		guard terminationTask == nil else { return .terminateLater }

		terminationTask = Task { @MainActor [weak self, weak sender] in
			guard let self else { return }
			await compositionRoot.appState.prepareForTermination()
			terminationIsReady = true
			terminationTask = nil
			sender?.reply(toApplicationShouldTerminate: true)
		}
		return .terminateLater
	}
}
