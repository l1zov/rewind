import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
  @ObservedObject var appState: AppState
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

  private var settingsLocked: Bool {
    !appState.permissionState.screenRecording
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if settingsLocked {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
              .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
              Text("Settings are locked until screen recording permission is granted.")
                .font(.system(size: 12, weight: .medium))
              Button("Open System Settings") {
                PermissionManager.openSystemSettings()
              }
              .buttonStyle(.link)
            }
          }
          .padding(.bottom, 4)
        }

        Group {
          sectionHeader("Capture")

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

                if appState.isLoadingResolutions {
                  ProgressView()
                    .controlSize(.small)
                } else {
                  Text(appState.resolutionLoadingMessage ?? "Resolution unavailable")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                  Button("Reload") {
                    appState.refreshResolutions()
                  }
                  .buttonStyle(.link)
                }
              }
            } else {
              HStack(spacing: 0) {
                Spacer(minLength: 0)
                Picker("Resolution", selection: $appState.selectedResolution) {
                  ForEach(appState.availableResolutions) { resolution in
                    Text(resolution.label).tag(Optional(resolution))
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

          settingsRow("Audio codec") {
            HStack(spacing: 0) {
              Spacer(minLength: 0)
              Picker("Audio codec", selection: $appState.selectedAudioCodec) {
                ForEach(CaptureAudioCodec.options) { option in
                  Text(option.label).tag(option)
                }
              }
              .frame(width: 180)
              .labelsHidden()
              .pickerStyle(.menu)
            }
          }

          settingsRow("Always record") {
            Toggle("", isOn: $appState.alwaysRecordEnabled)
              .labelsHidden()
              .toggleStyle(.switch)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }

          Divider()

          sectionHeader("Hotkeys")

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

          sectionHeader("Feedback")

          settingsRow("Save feedback") {
            Toggle("", isOn: $appState.saveFeedbackEnabled)
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

          Divider()

          sectionHeader("Integrations")

          settingsRow("Discord RPC") {
            Toggle("", isOn: $appState.discordRPCEnabled)
              .labelsHidden()
              .toggleStyle(.switch)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }
        }
        .disabled(settingsLocked)

        Divider()

        sectionHeader("About")

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
      appState.refreshPermissions()
      if appState.availableResolutions.isEmpty, !appState.isLoadingResolutions {
        appState.refreshResolutions()
      }
    }
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

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
      .tracking(0.4)
      .padding(.top, 2)
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
