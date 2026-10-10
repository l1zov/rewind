import Combine
import Defaults
import Foundation
import Sparkle

@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {
	private var _updaterController: SPUStandardUpdaterController!

	var updater: SPUUpdater {
		_updaterController.updater
	}

	override init() {
		super.init()
		_updaterController = SPUStandardUpdaterController(
			startingUpdater: true,
			updaterDelegate: self,
			userDriverDelegate: nil
		)
	}

	func checkForUpdates() {
		_updaterController.checkForUpdates(nil)
	}

	/// Opts into the `beta` channel when the user has enabled beta updates. Sparkle
	/// always includes the default channel, so an empty set means stable-only. Read
	/// from storage so toggling takes effect on the next check.
	nonisolated func allowedChannels(for _: SPUUpdater) -> Set<String> {
		Defaults[.betaUpdatesEnabled] ? ["beta"] : []
	}

	nonisolated func updater(_: SPUUpdater, willInstallUpdate _: SUAppcastItem) {
		if let bundleID = Bundle.main.bundleIdentifier {
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
			process.arguments = ["reset", "All", bundleID]
			do {
				try process.run()
				process.waitUntilExit()
				AppLog.info(.app, "Reset TCC permissions for", bundleID)
			} catch {
				AppLog.error(.app, "Could not reset TCC permissions", error: error)
			}
		}
	}
}
