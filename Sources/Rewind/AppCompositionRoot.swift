import Defaults

@MainActor
final class AppCompositionRoot {
	static let shared = AppCompositionRoot()

	let appState: AppState
	let lifecycleController: AppLifecycleController
	let updaterController: UpdaterController
	let analytics: any AnalyticsTracking

	private init() {
		DefaultsMigration.migrateLegacySettingsIfNeeded()
		let hotkeyManager = GlobalHotkeyManager.shared
		let analytics = PostHogAnalytics(enabled: Defaults[.analyticsEnabled])
		let appState = AppState(analytics: analytics, hotkeyManager: hotkeyManager)
		let updaterController = UpdaterController()

		self.appState = appState
		self.updaterController = updaterController
		self.analytics = analytics
		lifecycleController = AppLifecycleController(
			appState: appState,
			hotkeyManager: hotkeyManager
		)
	}
}
