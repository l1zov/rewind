import SwiftUI

@main
struct RewindApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let compositionRoot = AppCompositionRoot.shared

  var body: some Scene {
    Settings {
      SettingsView(appState: compositionRoot.appState)
    }
  }
}
