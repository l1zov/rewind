import SwiftUI

@main
struct RewindApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      SettingsView()
        .environmentObject(AppState.shared)
    }
  }
}
