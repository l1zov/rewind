import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var appState: AppState
  private let rowLabelWidth: CGFloat = 130
  private let durationFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.allowsFloats = false
    formatter.minimum = NSNumber(value: AppSettings.replayDurationRange.lowerBound)
    formatter.maximum = NSNumber(value: AppSettings.replayDurationRange.upperBound)
    return formatter
  }()
  private let feedbackVolumeFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.allowsFloats = false
    formatter.minimum = NSNumber(value: AppSettings.saveFeedbackVolumeRange.lowerBound)
    formatter.maximum = NSNumber(value: AppSettings.saveFeedbackVolumeRange.upperBound)
    return formatter
  }()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        settingsRow("Clip length") {
          HStack(spacing: 8) {
            Spacer(minLength: 0)

            TextField("Seconds", value: $appState.replayDuration, formatter: durationFormatter)
              .frame(width: 64)
              .textFieldStyle(.roundedBorder)
            Text("seconds")
              .foregroundStyle(.secondary)
          }
        }

        settingsRow("Resolution") {
          if appState.availableResolutions.isEmpty {
            HStack(spacing: 8) {
              Spacer(minLength: 0)

              Text(appState.isLoadingResolutions ? "Loading…" : (appState.resolutionLoadingMessage ?? "Unavailable"))
                .foregroundStyle(.secondary)
              if !appState.isLoadingResolutions {
                Button("Retry") {
                  appState.refreshResolutions()
                }
                .buttonStyle(.borderless)
              }
            }
          } else {
            HStack(spacing: 0) {
              Spacer(minLength: 0)
              Picker("Resolution", selection: resolutionBinding) {
                ForEach(appState.availableResolutions) { resolution in
                  Text(resolution.label).tag(resolution)
                }
              }
              .frame(width: 180)
              .labelsHidden()
              .pickerStyle(.menu)
            }
          }
        }

        settingsRow("Quality") {
          HStack(spacing: 0) {
            Spacer(minLength: 0)
            Picker("Quality", selection: $appState.selectedQuality) {
              ForEach(QualityPreset.presets) { preset in
                Text(preset.label).tag(preset)
              }
            }
            .frame(width: 180)
            .labelsHidden()
            .pickerStyle(.menu)
          }
        }

        settingsRow("Frame Rate") {
          HStack(spacing: 0) {
            Spacer(minLength: 0)
            Picker("Frame Rate", selection: $appState.selectedFrameRate) {
              ForEach(CaptureFrameRate.options) { option in
                Text(option.label).tag(option)
              }
            }
            .frame(width: 180)
            .labelsHidden()
            .pickerStyle(.menu)
          }
        }

        settingsRow("Container") {
          HStack(spacing: 0) {
            Spacer(minLength: 0)
            Picker("Container", selection: $appState.selectedContainer) {
              ForEach(CaptureContainer.options) { option in
                Text(option.label).tag(option)
              }
            }
            .frame(width: 180)
            .labelsHidden()
            .pickerStyle(.menu)
          }
        }

        Divider()

        HotkeyRecorderView(
          title: "Start/Stop recording",
          hotkey: $appState.startRecordingHotkey,
          labelWidth: rowLabelWidth
        )

        HotkeyRecorderView(
          title: "Save last clip",
          hotkey: $appState.hotkey,
          labelWidth: rowLabelWidth
        )

        Divider()

        settingsRow("Save feedback") {
          Toggle("", isOn: $appState.saveFeedbackEnabled)
            .labelsHidden()
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }

        settingsRow("Discord RPC") {
          Toggle("", isOn: $appState.discordRPCEnabled)
            .labelsHidden()
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }

        settingsRow("Feedback sound") {
          HStack(spacing: 0) {
            Spacer(minLength: 0)
            Picker("Feedback sound", selection: $appState.saveFeedbackSound) {
              ForEach(SaveFeedbackSound.options) { sound in
                Text(sound.label).tag(sound)
              }
            }
            .frame(width: 180)
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(!appState.saveFeedbackEnabled)
          }
        }

        settingsRow("Feedback volume") {
          HStack(spacing: 8) {
            Spacer(minLength: 0)

            TextField("1-100", value: $appState.saveFeedbackVolume, formatter: feedbackVolumeFormatter)
              .frame(width: 52)
              .textFieldStyle(.roundedBorder)
              .disabled(!appState.saveFeedbackEnabled)

            Text("/ 100")
              .font(.system(size: 12, weight: .medium, design: .monospaced))
              .foregroundStyle(.secondary)
              .frame(width: 40, alignment: .leading)
          }
        }

        HStack(spacing: 10) {
          Text("Credits")
            .frame(width: rowLabelWidth, alignment: .topLeading)

          Spacer(minLength: 0)

          VStack(alignment: .trailing, spacing: 2) {
            Text("Built with ❤️ by lzov")
          }
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minWidth: 460, minHeight: 500)
    .onAppear {
      if appState.availableResolutions.isEmpty, !appState.isLoadingResolutions {
        appState.refreshResolutions()
      }
    }
  }

  private var resolutionBinding: Binding<CaptureResolution> {
    Binding(
      get: {
        if let selected = appState.selectedResolution,
           appState.availableResolutions.contains(selected) {
          return selected
        }
        return appState.availableResolutions.first
          ?? CaptureResolution.native(width: 1920, height: 1080)
      },
      set: { newValue in
        appState.selectedResolution = newValue
      }
    )
  }

  private func settingsRow<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title)
        .frame(width: rowLabelWidth, alignment: .leading)
      content()
      Spacer(minLength: 0)
    }
  }
}

private struct HotkeyRecorderView: View {
  let title: String
  @Binding var hotkey: Hotkey
  let labelWidth: CGFloat
  @State private var isRecording = false
  @State private var monitor: Any?

  var body: some View {
    HStack(spacing: 12) {
      Text(title)
        .frame(width: labelWidth, alignment: .leading)
      Spacer()
      Text(isRecording ? "Press keys…" : hotkey.displayString)
        .foregroundStyle(.secondary)
      Button(isRecording ? "Cancel" : "Change") {
        if isRecording {
          stopRecording()
        } else {
          startRecording()
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .onDisappear {
      stopRecording()
    }
  }

  private func startRecording() {
    isRecording = true
    if monitor != nil { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
      guard isRecording else { return event }
      if event.keyCode == UInt16(kVK_Escape) {
        stopRecording()
        return nil
      }
      let relevantFlags = event.modifierFlags.intersection([.command, .shift, .option, .control])
      if relevantFlags.isEmpty {
        return nil
      }
      hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: relevantFlags.carbonModifiers)
      stopRecording()
      return nil
    }
  }

  private func stopRecording() {
    isRecording = false
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }
}
