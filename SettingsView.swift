import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
	@ObservedObject var appState: AppState
	@ObservedObject var updaterController: UpdaterController
	@State private var didApplyWindowSizing = false

	private var settingsLocked: Bool {
		!appState.permissionState.screenRecording
	}

	var body: some View {
		TabView {
			GeneralSettingsPane(appState: appState, updaterController: updaterController)
				.tabItem { Label("General", systemImage: "gearshape") }

			CaptureSettingsPane(appState: appState, settingsLocked: settingsLocked)
				.tabItem { Label("Capture", systemImage: "record.circle") }

			HotkeysSettingsPane(appState: appState, settingsLocked: settingsLocked)
				.tabItem { Label("Hotkeys", systemImage: "keyboard") }

			FeedbackSettingsPane(appState: appState, settingsLocked: settingsLocked)
				.tabItem { Label("Feedback", systemImage: "speaker.wave.2") }

			IntegrationsSettingsPane(appState: appState, settingsLocked: settingsLocked)
				.tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }

			AboutSettingsPane()
				.tabItem { Label("About", systemImage: "info.circle") }
		}
		.frame(minWidth: 440, minHeight: 440)
		.safeAreaInset(edge: .top, spacing: 0) {
			if settingsLocked {
				PermissionCallout(appState: appState)
			}
		}
		.background(
			WindowAccessor { window in
				applyNaturalWindowSizeIfNeeded(window)
			}
		)
		.onAppear {
			appState.refreshPermissions()
			if appState.availableResolutions.isEmpty, !appState.isLoadingResolutions {
				appState.refreshResolutions()
			}
			appState.refreshMicrophones()
		}
	}

	private func applyNaturalWindowSizeIfNeeded(_ window: NSWindow) {
		guard !didApplyWindowSizing else { return }
		didApplyWindowSizing = true

		let naturalSize = NSSize(width: 520, height: 440)
		window.contentMinSize = naturalSize
		window.setContentSize(naturalSize)
	}
}

private struct GeneralSettingsPane: View {
	@ObservedObject var appState: AppState
	@ObservedObject var updaterController: UpdaterController
	@State private var showingResetConfirmation = false

	var body: some View {
		Form {
			Section("Startup") {
				LabeledContent {
					Toggle("", isOn: $appState.launchAtLoginEnabled)
						.labelsHidden()
						.toggleStyle(.switch)
				} label: {
					HelpLabel("Open on login", help: "Automatically launch Rewind when you log in to your Mac.")
				}
			}

			Section("Updates") {
				Button("Check for Updates...") {
					updaterController.checkForUpdates()
				}
				.disabled(!updaterController.updater.canCheckForUpdates)

				Toggle(isOn: $appState.betaUpdatesEnabled) {
					HelpLabel("Receive beta updates", help: "Opt in to early beta releases. Betas may be less stable. Turn off to return to stable releases on the next update.")
				}
			}

			Section("Privacy") {
				Toggle(isOn: $appState.analyticsEnabled) {
					HelpLabel(
						"Share anonymous analytics",
						help: "Sends anonymous app-open, recording, and replay-save events to help improve Rewind. Never includes recordings, screenshots, file paths, game names, or error details."
					)
				}
			}

			Section("Diagnostics") {
				Toggle(isOn: $appState.fileLoggingEnabled) {
					HelpLabel("Enable verbose file logging", help: "Writes detailed debug logs to disk for troubleshooting.")
				}

				Button("Reveal Log File in Finder") {
					if let url = AppLog.logFileURL {
						NSWorkspace.shared.activateFileViewerSelecting([url])
					}
				}
			}

			Section("Advanced") {
				Button("Reset to Defaults...", role: .destructive) {
					showingResetConfirmation = true
				}
				.disabled(appState.isCapturing || appState.isCaptureTransitioning)
			}
		}
		.formStyle(.grouped)
		.confirmationDialog(
			"Reset all settings to their defaults?",
			isPresented: $showingResetConfirmation,
			titleVisibility: .visible
		) {
			Button("Reset to Defaults", role: .destructive) {
				appState.resetToDefaults()
			}
			Button("Cancel", role: .cancel) {}
		}
	}
}

private struct CaptureSettingsPane: View {
	@ObservedObject var appState: AppState
	let settingsLocked: Bool

	private var replayDurationRange: ClosedRange<Int> {
		Int(AppSettings.replayDurationRange.lowerBound) ... Int(AppSettings.replayDurationRange.upperBound)
	}

	private var manualCaptureConfigurationLocked: Bool {
		appState.selectedRecordingMode == .recording
			&& (appState.isCapturing || appState.isCaptureTransitioning)
	}

	private var replayDurationStep: Int {
		max(1, Int(AppSettings.replayDurationStep))
	}

	private var replayDurationSecondsBinding: Binding<Int> {
		Binding(
			get: { Int(appState.replayDuration) },
			set: { newValue in
				let clampedValue = min(max(newValue, replayDurationRange.lowerBound), replayDurationRange.upperBound)
				appState.replayDuration = TimeInterval(clampedValue)
			}
		)
	}

	var body: some View {
		Form {
			Section("Recording") {
				LabeledContent {
					Picker("", selection: $appState.selectedRecordingMode) {
						ForEach(RecordingMode.options) { mode in
							Text(mode.label).tag(mode)
						}
					}
					.labelsHidden()
					.pickerStyle(.segmented)
					.frame(width: 230)
					.disabled(appState.isCapturing || appState.isCaptureTransitioning)
				} label: {
					HelpLabel(
						"Mode",
						help: "Instant Replay saves the recent past. Recording saves everything from Start until Stop, like OBS."
					)
				}

				LabeledContent {
					Toggle("", isOn: $appState.captureTargetPromptEnabled)
						.labelsHidden()
						.toggleStyle(.switch)
						.disabled(!AppState.supportsCaptureTargetPrompt)
				} label: {
					HelpLabel(
						"Choose what to record",
						help: AppState.supportsCaptureTargetPrompt
							? "When you start recording manually, macOS asks which display, window or app to capture. Turn off to always record the main display."
							: "Choosing a display, window, or app to capture requires macOS 14 or later."
					)
				}

				if appState.selectedRecordingMode == .instantReplay {
					LabeledContent {
						Stepper(
							value: replayDurationSecondsBinding,
							in: replayDurationRange,
							step: replayDurationStep
						) {
							Text(Int(appState.replayDuration).formattedDuration)
								.foregroundStyle(.secondary)
						}
						.frame(width: 200, alignment: .trailing)
					} label: {
						HelpLabel("Clip length", help: "Determines how many seconds of video to save when capturing.")
					}

					LabeledContent {
						Toggle("", isOn: $appState.alwaysRecordEnabled)
							.labelsHidden()
							.toggleStyle(.switch)
					} label: {
						HelpLabel("Always record", help: "Starts the Instant Replay buffer automatically when Rewind opens.")
					}
				}
			}
			.disabled(settingsLocked)

			Section("Video") {
				LabeledContent("Resolution") {
					resolutionControl
						.frame(width: 200, alignment: .trailing)
				}

				Picker(selection: $appState.selectedQuality) {
					ForEach(QualityPreset.presets) { preset in
						Text(defaultTaggedLabel(preset.label, isDefault: preset.isDefault)).tag(preset)
					}
				} label: {
					HelpLabel("Quality", help: "Higher quality increases file size but produces clearer video.")
				}
				.pickerStyle(.menu)

				Picker(selection: $appState.selectedFrameRate) {
					ForEach(CaptureFrameRate.options) { option in
						Text(defaultTaggedLabel(option.label, isDefault: option.isDefault)).tag(option)
					}
				} label: {
					HelpLabel("Frame rate", help: "Higher frame rates produce smoother video but use more system resources.")
				}
				.pickerStyle(.menu)
			}
			.disabled(settingsLocked || manualCaptureConfigurationLocked)

			Section("Audio") {
				LabeledContent {
					Toggle("", isOn: $appState.recordDesktopAudioEnabled)
						.labelsHidden()
						.toggleStyle(.switch)
				} label: {
					HelpLabel("Record desktop audio", help: "Captures system/app audio playing on your Mac.")
				}

				LabeledContent {
					Toggle("", isOn: $appState.recordMicrophoneEnabled)
						.labelsHidden()
						.toggleStyle(.switch)
						.disabled(!AppState.supportsMicrophoneCapture)
				} label: {
					HelpLabel(
						"Record Microphone",
						help: AppState.supportsMicrophoneCapture
							? "Captures microphone audio. Requires microphone permissions."
							: "Captures microphone audio. Requires macOS 15 or later."
					)
				}

				if AppState.supportsMicrophoneCapture {
					Picker(selection: $appState.selectedMicrophoneDeviceID) {
						Text("System Default").tag(String?.none)
						ForEach(appState.availableMicrophones) { device in
							Text(device.name).tag(Optional(device.id))
						}
					} label: {
						HelpLabel("Microphone", help: "Which microphone to capture. System Default follows your Mac's input device.")
					}
					.pickerStyle(.menu)
					.disabled(!appState.recordMicrophoneEnabled)
				}
			}
			.disabled(settingsLocked || manualCaptureConfigurationLocked)

			Section("Output") {
				LabeledContent("Save location") {
					HStack(spacing: 8) {
						Text(appState.outputDirectoryPath ?? "Movies/Rewind")
							.lineLimit(1)
							.truncationMode(.middle)
							.foregroundStyle(.secondary)
							.frame(maxWidth: 160, alignment: .trailing)

						Button("Change...") {
							let panel = NSOpenPanel()
							panel.canChooseFiles = false
							panel.canChooseDirectories = true
							panel.canCreateDirectories = true
							if panel.runModal() == .OK, let url = panel.url {
								appState.outputDirectoryPath = url.path
							}
						}
						.controlSize(.small)
					}
				}

				Picker(selection: $appState.selectedContainer) {
					ForEach(CaptureContainer.options) { option in
						Text(defaultTaggedLabel(option.label, isDefault: option.isDefault)).tag(option)
					}
				} label: {
					HelpLabel("Container", help: "Video file format for saved clips (.mp4 or .mov).")
				}
				.pickerStyle(.menu)
			}
			.disabled(settingsLocked || manualCaptureConfigurationLocked)
		}
		.formStyle(.grouped)
	}

	@ViewBuilder
	private var resolutionControl: some View {
		if appState.availableResolutions.isEmpty {
			if appState.isLoadingResolutions {
				ProgressView()
					.controlSize(.small)
			} else {
				HStack(spacing: 8) {
					Text(appState.resolutionLoadingMessage ?? "Resolution unavailable")
						.foregroundStyle(.secondary)
					Button("Reload") {
						appState.refreshResolutions()
					}
					.buttonStyle(.link)
				}
			}
		} else {
			Picker("Resolution", selection: $appState.selectedResolution) {
				ForEach(appState.availableResolutions) { resolution in
					Text(defaultTaggedLabel(resolution.label, isDefault: resolution.isNative))
							.tag(Optional(resolution))
				}
			}
			.labelsHidden()
			.pickerStyle(.menu)
		}
	}
}

private struct HotkeysSettingsPane: View {
	@ObservedObject var appState: AppState
	let settingsLocked: Bool

	var body: some View {
		Form {
			Section {
				HotkeyRecorderRow(title: "Start recording", hotkey: $appState.startRecordingHotkey)
				HotkeyRecorderRow(title: "Stop recording", hotkey: $appState.stopRecordingHotkey)
				if appState.selectedRecordingMode == .instantReplay {
					HotkeyRecorderRow(title: "Save last clip", hotkey: $appState.hotkey)
				}
			} header: {
				Text("Shortcuts")
			} footer: {
				VStack(alignment: .leading, spacing: 4) {
					Text("Press Escape to cancel shortcut recording.")
					if let message = appState.hotkeyConflictMessage {
						Text(message)
							.foregroundStyle(.red)
					}
				}
			}
			.disabled(settingsLocked)
		}
		.formStyle(.grouped)
	}
}

private struct FeedbackSection: View {
	let title: String
	let toggleLabel: String
	@Binding var enabled: Bool
	@Binding var sound: FeedbackSound
	@Binding var volume: Double
	let settingsLocked: Bool
	let onPlay: () -> Void

	private var feedbackVolumeRange: ClosedRange<Int> {
		Int(AppSettings.saveFeedbackVolumeRange.lowerBound) ... Int(AppSettings.saveFeedbackVolumeRange.upperBound)
	}

	private var volumeBinding: Binding<Int> {
		Binding(
			get: { Int(volume.rounded()) },
			set: { newValue in
				let clamped = min(max(newValue, feedbackVolumeRange.lowerBound), feedbackVolumeRange.upperBound)
				volume = Double(clamped)
			}
		)
	}

	var body: some View {
		Section(title) {
			Toggle(toggleLabel, isOn: $enabled)

			Picker("Feedback sound", selection: $sound) {
				ForEach(FeedbackSound.options) { soundOption in
					Text(soundOption.label).tag(soundOption)
				}
			}
			.pickerStyle(.menu)
			.disabled(!enabled)

			LabeledContent("Feedback volume") {
				HStack(spacing: 6) {
					TextField("", value: volumeBinding, format: .number.grouping(.never))
						.textFieldStyle(.roundedBorder)
						.multilineTextAlignment(.trailing)
						.frame(width: 64)
						.help("Range: \(feedbackVolumeRange.lowerBound)-\(feedbackVolumeRange.upperBound)")
						.disabled(!enabled)

					Text("%")
						.foregroundStyle(.secondary)

					Button {
						onPlay()
					} label: {
						Image(systemName: "play.circle")
					}
					.buttonStyle(.plain)
					.padding(.leading, 4)
					.disabled(!enabled)
				}
			}
		}
		.disabled(settingsLocked)
	}
}

private struct FeedbackSettingsPane: View {
	@ObservedObject var appState: AppState
	let settingsLocked: Bool

	var body: some View {
		Form {
			FeedbackSection(
				title: "Save Feedback",
				toggleLabel: "Enable save feedback",
				enabled: $appState.saveFeedbackEnabled,
				sound: $appState.saveFeedbackSound,
				volume: $appState.saveFeedbackVolume,
				settingsLocked: settingsLocked,
				onPlay: { appState.playReplaySavedFeedback() }
			)

			FeedbackSection(
				title: "Recording Start Feedback",
				toggleLabel: "Enable start feedback",
				enabled: $appState.recordingStartFeedbackEnabled,
				sound: $appState.recordingStartFeedbackSound,
				volume: $appState.recordingStartFeedbackVolume,
				settingsLocked: settingsLocked,
				onPlay: { appState.playRecordingStartFeedback() }
			)

			FeedbackSection(
				title: "Recording End Feedback",
				toggleLabel: "Enable end feedback",
				enabled: $appState.recordingEndFeedbackEnabled,
				sound: $appState.recordingEndFeedbackSound,
				volume: $appState.recordingEndFeedbackVolume,
				settingsLocked: settingsLocked,
				onPlay: { appState.playRecordingEndFeedback() }
			)

			FeedbackSection(
				title: "Error Feedback",
				toggleLabel: "Enable error feedback",
				enabled: $appState.errorFeedbackEnabled,
				sound: $appState.errorFeedbackSound,
				volume: $appState.errorFeedbackVolume,
				settingsLocked: settingsLocked,
				onPlay: { appState.playErrorFeedback() }
			)
		}
		.formStyle(.grouped)
	}
}

private struct WindowAccessor: NSViewRepresentable {
	let onResolve: (NSWindow) -> Void

	func makeNSView(context _: Context) -> NSView {
		let view = NSView()
		DispatchQueue.main.async {
			if let window = view.window {
				onResolve(window)
			}
		}
		return view
	}

	func updateNSView(_ nsView: NSView, context _: Context) {
		DispatchQueue.main.async {
			if let window = nsView.window {
				onResolve(window)
			}
		}
	}
}

private struct IntegrationsSettingsPane: View {
	@ObservedObject var appState: AppState
	let settingsLocked: Bool
	@State private var streamableEmail = ""
	@State private var streamablePassword = ""
	@State private var savedStreamableEmail: String?
	@State private var streamableCredentialError: String?
	@State private var isLoadingStreamableAccount = true
	@State private var isSavingStreamableAccount = false

	var body: some View {
		Form {
			Section("Connections") {
				Toggle(isOn: $appState.discordRPCEnabled) {
					HelpLabel("Enable Discord RPC", help: "Shows your recording status on your Discord profile.")
				}
				Toggle(isOn: $appState.shareGamePresenceEnabled) {
					HelpLabel("Show the game you're playing", help: "Adds the game you're playing to your Discord status. Turn this off to show only that you're recording, without naming the game.")
				}
				.disabled(!appState.discordRPCEnabled)
				Toggle(isOn: $appState.shareRobloxExperienceEnabled) {
					HelpLabel("Show your Roblox experience", help: "Shows exactly which Roblox experience you're in, with a button friends can use to join you. Turn this off to show just \"Roblox\".")
				}
				.disabled(!appState.discordRPCEnabled || !appState.shareGamePresenceEnabled)
			}
			.disabled(settingsLocked)

			Section {
				ForEach(ClipUploadProvider.providers) { provider in
					Toggle(isOn: uploadProviderBinding(for: provider)) {
						HelpLabel(provider.displayName, help: provider.summary)
					}
					.disabled(
						provider.authentication == .streamableBasic
							&& (isLoadingStreamableAccount || savedStreamableEmail == nil)
					)
				}
			} header: {
				Text("Upload Providers")
			} footer: {
				Text("By enabling a provider, you agree to their respective Terms of Service and Privacy Policy.")
			}
			.disabled(settingsLocked)

			Section {
				LabeledContent("Email") {
					TextField("name@example.com", text: $streamableEmail)
						.textFieldStyle(.roundedBorder)
						.frame(width: 240)
				}

				LabeledContent("Password") {
					SecureField("Streamable password", text: $streamablePassword)
						.textFieldStyle(.roundedBorder)
						.frame(width: 240)
				}

				HStack {
					Button(savedStreamableEmail == nil ? "Save Account" : "Update Account") {
						saveStreamableAccount()
					}
					.disabled(
						isSavingStreamableAccount
							|| streamableEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
							|| streamablePassword.isEmpty
					)

					if savedStreamableEmail != nil {
						Button("Forget Account", role: .destructive) {
							forgetStreamableAccount()
						}
					}
				}

				if let savedStreamableEmail {
					Label("Connected as \(savedStreamableEmail)", systemImage: "checkmark.circle.fill")
						.foregroundStyle(.green)
						.font(.caption)
				}

				if let streamableCredentialError {
					Text(streamableCredentialError)
						.foregroundStyle(.red)
						.font(.caption)
				}

				Link("Create or manage your Streamable account", destination: URL(string: "https://streamable.com")!)
			}
			header: {
				Text("Streamable Account")
			}
			footer: {
				Text("Required for Streamable cloud uploads. Your password is stored in the macOS Keychain and is only sent to api.streamable.com.")
			}
			.disabled(settingsLocked || isLoadingStreamableAccount)
		}
		.formStyle(.grouped)
		.task {
			await loadStreamableAccount()
		}
	}

	private func uploadProviderBinding(for provider: ClipUploadProvider) -> Binding<Bool> {
		Binding(
			get: { appState.isUploadProviderEnabled(provider) },
			set: { appState.setUploadProvider(provider, enabled: $0) }
		)
	}

	private func loadStreamableAccount() async {
		do {
			let email = try await StreamableCredentialStore.shared.accountEmail()
			savedStreamableEmail = email
			if streamableEmail.isEmpty {
				streamableEmail = email ?? ""
			}
			streamableCredentialError = nil
		} catch {
			streamableCredentialError = error.localizedDescription
		}
		isLoadingStreamableAccount = false
	}

	private func saveStreamableAccount() {
		let email = streamableEmail
		let password = streamablePassword
		isSavingStreamableAccount = true
		streamableCredentialError = nil

		Task { @MainActor in
			do {
				let credentials = try StreamableCredentials(email: email, password: password)
				try await StreamableCredentialStore.shared.save(credentials)
				savedStreamableEmail = credentials.email
				streamableEmail = credentials.email
				streamablePassword = ""
			} catch {
				streamableCredentialError = error.localizedDescription
			}
			isSavingStreamableAccount = false
		}
	}

	private func forgetStreamableAccount() {
		isSavingStreamableAccount = true
		streamableCredentialError = nil

		Task { @MainActor in
			do {
				try await StreamableCredentialStore.shared.delete()
				savedStreamableEmail = nil
				streamableEmail = ""
				streamablePassword = ""
				if let provider = ClipUploadProvider.provider(id: ClipUploadProvider.streamableID) {
					appState.setUploadProvider(provider, enabled: false)
				}
			} catch {
				streamableCredentialError = error.localizedDescription
			}
			isSavingStreamableAccount = false
		}
	}
}

private struct AboutSettingsPane: View {
	private var appVersion: String {
		let shortVersion = normalizedVersion(
			Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		) ?? normalizedVersion(ProcessInfo.processInfo.environment["REWIND_VERSION"])

		let buildVersion = normalizedVersion(
			Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		)

		if let shortVersion {
			if let buildVersion, buildVersion != shortVersion {
				return "\(shortVersion) (\(buildVersion))"
			}
			return shortVersion
		}

		if let buildVersion {
			return buildVersion
		}

		return "Dev"
	}

	private func normalizedVersion(_ value: String?) -> String? {
		guard let value else { return nil }
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}

	var body: some View {
		Form {
			Section("Rewind") {
				LabeledContent("Version") {
					Text(appVersion)
				}
			}
		}
		.formStyle(.grouped)
	}
}

private func defaultTaggedLabel(_ label: String, isDefault: Bool) -> String {
	isDefault ? "\(label) (Default)" : label
}

private struct HelpLabel: View {
	let title: String
	let help: String
	@State private var isHovering = false
	@State private var hoverTask: Task<Void, Never>?

	init(_ title: String, help: String) {
		self.title = title
		self.help = help
	}

	var body: some View {
		HStack(spacing: 4) {
			Text(title)
			Image(systemName: "questionmark.circle")
				.foregroundStyle(isHovering ? .primary : .secondary)
				.onHover { hovering in
					hoverTask?.cancel()
					if hovering {
						hoverTask = Task {
							try? await Task.sleep(nanoseconds: 500_000_000)
							if !Task.isCancelled {
								isHovering = true
							}
						}
					} else {
						isHovering = false
					}
				}
				.popover(isPresented: $isHovering, arrowEdge: .top) {
					Text(help)
						.lineLimit(nil)
						.frame(width: 220, alignment: .leading)
						.padding(10)
				}
		}
	}
}

private struct PermissionCallout: View {
	@ObservedObject var appState: AppState

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: "lock.fill")
				.font(.title3)
				.foregroundStyle(.secondary)

			VStack(alignment: .leading, spacing: 2) {
				Text("Screen recording permission required")
					.font(.callout.weight(.medium))
				Text("Grant access to change capture settings.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Spacer(minLength: 8)

			Button("Open System Settings") {
				appState.requestScreenRecordingAccess()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.small)
		}
		.padding(12)
		.background(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(.ultraThinMaterial)
		)
		.overlay(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
		)
		.padding(.horizontal)
		.padding(.top, 8)
	}
}

private struct HotkeyRecorderRow: View {
	let title: String
	@Binding var hotkey: Hotkey
	@State private var isRecording = false
	@State private var monitor: Any?

	var body: some View {
		LabeledContent(title) {
			HStack(spacing: 10) {
				Text(isRecording ? "Press keys..." : hotkey.displayString)
					.foregroundStyle(.secondary)
					.monospaced()

				Button(isRecording ? "Cancel" : "Record") {
					if isRecording {
						stopRecording()
					} else {
						startRecording()
					}
				}
				.controlSize(.small)
			}
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
