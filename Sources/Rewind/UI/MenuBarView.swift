import SwiftUI

struct MenuBarView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    VStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Rewind")
          .font(.system(size: 18, weight: .semibold))
        Text(appState.isCapturing ? "Recording" : "Idle")
          .foregroundStyle(appState.isCapturing ? .red : .secondary)
          .font(.system(size: 12, weight: .medium))
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 10) {
        Button(recordingButtonTitle) {
          appState.toggleCapture()
        }
        .buttonStyle(.borderedProminent)
        .disabled(appState.alwaysRecordEnabled && appState.isCapturing)

        Button("Save Last \(Int(appState.replayDuration))s") {
          appState.saveReplay()
        }
        .buttonStyle(.bordered)
        .disabled(!appState.isCapturing)
      }

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Replay")
            .font(.system(size: 12, weight: .medium))
          Spacer()
          Text("\(Int(appState.replayDuration))s")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        Slider(
          value: $appState.replayDuration,
          in: AppSettings.replayDurationRange,
          step: AppSettings.replayDurationStep
        )
      }

      VStack(alignment: .leading, spacing: 6) {
        if let clip = appState.lastClip {
          Text("Saved")
            .font(.system(size: 12, weight: .medium))
          Text(clip.url.lastPathComponent)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else {
          Text("No recent clips")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack {
        Button("Permissions") {
          appState.refreshPermissions()
        }
        .buttonStyle(.borderless)

        Spacer()

        Button("Quit") {
          NSApp.terminate(nil)
        }
        .buttonStyle(.borderless)
      }
      .font(.system(size: 12))
    }
    .padding(16)
  }

  private var recordingButtonTitle: String {
    if appState.alwaysRecordEnabled {
      return appState.isCapturing ? "Recording (Always)" : "Start"
    }
    return appState.isCapturing ? "Stop" : "Start"
  }
}
