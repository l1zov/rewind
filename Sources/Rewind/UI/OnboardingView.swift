import AppKit
import SwiftUI

struct OnboardingView: View {
  let openSettings: () -> Void
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .frame(width: 56, height: 56)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        VStack(alignment: .leading, spacing: 4) {
          Text("Welcome to Rewind")
            .font(.title3.weight(.semibold))
          Text("Capture in the background and save your last moments any time.")
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        Label("Find Rewind in the menu bar at the top-right of your screen.", systemImage: "menubar.rectangle")
        Label("Click the Rewind icon to start recording, save clips, and access options.", systemImage: "record.circle")
        Label("Open Settings from the menu bar with \"Settings…\" or press \"⌘ + ,\".", systemImage: "gearshape")
        Label("Customize clip length, hotkeys, and sound feedback in Settings.", systemImage: "slider.horizontal.3")
      }
      .font(.system(size: 13))

      Spacer(minLength: 0)

      HStack {
        Button("Open Settings") {
          openSettings()
        }
        .buttonStyle(.bordered)

        Spacer()

        Button("Got it") {
          close()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(22)
    .frame(width: 520, height: 340)
  }
}
