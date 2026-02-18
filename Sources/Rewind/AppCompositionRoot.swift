@MainActor
final class AppCompositionRoot {
  static let shared = AppCompositionRoot()

  let appState: AppState
  let lifecycleController: AppLifecycleController

  private init() {
    let hotkeyManager = GlobalHotkeyManager.shared
    let appState = AppState(hotkeyManager: hotkeyManager)

    self.appState = appState
    lifecycleController = AppLifecycleController(
      appState: appState,
      hotkeyManager: hotkeyManager
    )
  }
}
