import AppKit
@preconcurrency import AVFoundation
import Combine
import Defaults
@preconcurrency import ScreenCaptureKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
	static let supportsMicrophoneCapture = ProcessInfo.processInfo.isOperatingSystemAtLeast(
		OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
	)

	static let supportsCaptureTargetPrompt = ProcessInfo.processInfo.isOperatingSystemAtLeast(
		OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
	)

	@Published private(set) var isCapturing = false
	@Published var replayDuration: TimeInterval = 30 {
		didSet {
			guard !isRestoringSettings else { return }
			let clamped = min(
				max(replayDuration, AppSettings.replayDurationRange.lowerBound),
				AppSettings.replayDurationRange.upperBound
			)
			if clamped != replayDuration {
				replayDuration = clamped
				return
			}
			persistSettings()
		}
	}

	@Published private(set) var lastClip: Clip?

	@Published var clipToOpen: Clip?

	/// Login-item state lives in the system (via `SMAppService`), not in app
	/// settings, so this is initialized from and written straight to that store.
	@Published var launchAtLoginEnabled: Bool = LaunchAtLogin.isEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard launchAtLoginEnabled != oldValue else { return }
			do {
				try LaunchAtLogin.setEnabled(launchAtLoginEnabled)
			} catch {
				AppLog.error(.app, "Failed to update launch at login:", error)
				isRestoringSettings = true
				launchAtLoginEnabled = oldValue
				isRestoringSettings = false
			}
		}
	}

	@Published private(set) var permissionState = PermissionState()
	@Published private(set) var availableResolutions: [CaptureResolution] = []
	@Published private(set) var isLoadingResolutions = false
	@Published private(set) var resolutionLoadingMessage: String?
	@Published var selectedResolution: CaptureResolution? {
		didSet {
			guard !isRestoringSettings else { return }
			guard selectedResolution != oldValue else { return }
			preferredResolutionID = selectedResolution?.id
			if oldValue == nil {
				restartCaptureSilently()
				return
			}
			persistSettings()
			restartCaptureSilently()
		}
	}

	@Published private(set) var availableMicrophones: [MicrophoneDevice] = []
	/// nil = system default input
	@Published var selectedMicrophoneDeviceID: String? {
		didSet {
			guard !isRestoringSettings else { return }
			guard selectedMicrophoneDeviceID != oldValue else { return }
			persistSettings()
			restartCaptureSilently()
		}
	}

	@Published var selectedQuality: QualityPreset = .default {
		didSet {
			guard !isRestoringSettings else { return }
			guard selectedQuality != oldValue else { return }
			persistSettings()
			restartCaptureSilently()
		}
	}

	@Published var selectedFrameRate: CaptureFrameRate = .default {
		didSet {
			guard !isRestoringSettings else { return }
			guard selectedFrameRate != oldValue else { return }
			persistSettings()
			restartCaptureSilently()
		}
	}

	@Published var selectedContainer: CaptureContainer = .default {
		didSet {
			guard !isRestoringSettings else { return }
			guard selectedContainer != oldValue else { return }
			persistSettings()
		}
	}

	@Published var selectedAudioCodec: CaptureAudioCodec = .default {
		didSet {
			guard !isRestoringSettings else { return }
			guard selectedAudioCodec != oldValue else { return }
			persistSettings()
			restartCaptureSilently()
		}
	}

	/// Mix level (0...1) of desktop audio in saved clips. Applied when a clip is
	/// saved, so changing it needs no capture restart.
	@Published var desktopAudioVolume = AppSettings.default.desktopAudioVolume {
		didSet {
			guard !isRestoringSettings else { return }
			guard desktopAudioVolume != oldValue else { return }
			persistSettings()
		}
	}

	/// Mix level (0...1) of the microphone in saved clips.
	@Published var microphoneVolume = AppSettings.default.microphoneVolume {
		didSet {
			guard !isRestoringSettings else { return }
			guard microphoneVolume != oldValue else { return }
			persistSettings()
		}
	}

	@Published var hotkey: Hotkey = .default {
		didSet {
			guard !isRestoringSettings else { return }
			guard hotkey != oldValue else { return }
			persistSettings()
			updateGlobalHotkeys()
		}
	}

	@Published var startRecordingHotkey: Hotkey = .startRecordingDefault {
		didSet {
			guard !isRestoringSettings else { return }
			guard startRecordingHotkey != oldValue else { return }
			persistSettings()
			updateGlobalHotkeys()
		}
	}

	@Published var alwaysRecordEnabled = AppSettings.default.alwaysRecordEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard alwaysRecordEnabled != oldValue else { return }
			persistSettings()
			if alwaysRecordEnabled {
				startCapture(reason: .alwaysRecord)
			}
		}
	}

	@Published var saveFeedbackEnabled = AppSettings.default.saveFeedbackEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard saveFeedbackEnabled != oldValue else { return }
			persistSettings()
		}
	}

	@Published var saveFeedbackVolume = AppSettings.default.saveFeedbackVolume {
		didSet {
			guard !isRestoringSettings else { return }
			guard saveFeedbackVolume != oldValue else { return }
			let clamped = min(
				max(saveFeedbackVolume, AppSettings.saveFeedbackVolumeRange.lowerBound),
				AppSettings.saveFeedbackVolumeRange.upperBound
			)
			if clamped != saveFeedbackVolume {
				saveFeedbackVolume = clamped
				return
			}
			persistSettings()
		}
	}

	@Published var saveFeedbackSound: FeedbackSound = .default {
		didSet {
			guard !isRestoringSettings else { return }
			guard saveFeedbackSound != oldValue else { return }
			soundFeedback.invalidate(.saved)
			persistSettings()
		}
	}

	@Published var recordingStartFeedbackEnabled = AppSettings.default.recordingStartFeedbackEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard recordingStartFeedbackEnabled != oldValue else { return }
			persistSettings()
		}
	}

	@Published var recordingStartFeedbackVolume = AppSettings.default.recordingStartFeedbackVolume {
		didSet {
			guard !isRestoringSettings else { return }
			guard recordingStartFeedbackVolume != oldValue else { return }
			let clamped = min(
				max(recordingStartFeedbackVolume, AppSettings.saveFeedbackVolumeRange.lowerBound),
				AppSettings.saveFeedbackVolumeRange.upperBound
			)
			if clamped != recordingStartFeedbackVolume {
				recordingStartFeedbackVolume = clamped
				return
			}
			persistSettings()
		}
	}

	@Published var recordingStartFeedbackSound: FeedbackSound = .defaultStart {
		didSet {
			guard !isRestoringSettings else { return }
			guard recordingStartFeedbackSound != oldValue else { return }
			soundFeedback.invalidate(.recordingStart)
			persistSettings()
		}
	}

	@Published var recordingEndFeedbackEnabled = AppSettings.default.recordingEndFeedbackEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard recordingEndFeedbackEnabled != oldValue else { return }
			persistSettings()
		}
	}

	@Published var recordingEndFeedbackVolume = AppSettings.default.recordingEndFeedbackVolume {
		didSet {
			guard !isRestoringSettings else { return }
			guard recordingEndFeedbackVolume != oldValue else { return }
			let clamped = min(
				max(recordingEndFeedbackVolume, AppSettings.saveFeedbackVolumeRange.lowerBound),
				AppSettings.saveFeedbackVolumeRange.upperBound
			)
			if clamped != recordingEndFeedbackVolume {
				recordingEndFeedbackVolume = clamped
				return
			}
			persistSettings()
		}
	}

	@Published var recordingEndFeedbackSound: FeedbackSound = .defaultEnd {
		didSet {
			guard !isRestoringSettings else { return }
			guard recordingEndFeedbackSound != oldValue else { return }
			soundFeedback.invalidate(.recordingEnd)
			persistSettings()
		}
	}

	@Published var errorFeedbackEnabled = AppSettings.default.errorFeedbackEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard errorFeedbackEnabled != oldValue else { return }
			persistSettings()
		}
	}

	@Published var errorFeedbackVolume = AppSettings.default.errorFeedbackVolume {
		didSet {
			guard !isRestoringSettings else { return }
			guard errorFeedbackVolume != oldValue else { return }
			let clamped = min(
				max(errorFeedbackVolume, AppSettings.saveFeedbackVolumeRange.lowerBound),
				AppSettings.saveFeedbackVolumeRange.upperBound
			)
			if clamped != errorFeedbackVolume {
				errorFeedbackVolume = clamped
				return
			}
			persistSettings()
			playErrorFeedback()
		}
	}

	@Published var errorFeedbackSound: FeedbackSound = .defaultError {
		didSet {
			guard !isRestoringSettings else { return }
			guard errorFeedbackSound != oldValue else { return }
			soundFeedback.invalidate(.error)
			persistSettings()
			playErrorFeedback()
		}
	}

	@Published var discordRPCEnabled = AppSettings.default.discordRPCEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard discordRPCEnabled != oldValue else { return }
			persistSettings()
			Task {
				await discordRPCClient.setEnabled(discordRPCEnabled)
				if discordRPCEnabled {
					self.publishDiscordPresenceWithRetry(for: self.discordActivityState)
					// The poller exits as soon as it observes discordRPCEnabled == false
					// (see startGamePresenceUpdates), so re-enabling mid-recording must
					// restart it explicitly or presence stays frozen on the stale game.
					if self.isCapturing, self.discordActivityState.isRecording, self.gamePresenceTask == nil {
						self.startGamePresenceUpdates()
					}
				} else {
					discordPresenceRetryTask?.cancel()
					discordPresenceRetryTask = nil
				}
			}
		}
	}

	@Published var shareGamePresenceEnabled = AppSettings.default.shareGamePresenceEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard shareGamePresenceEnabled != oldValue else { return }
			persistSettings()
			refreshGamePresenceIfRecording()
		}
	}

	@Published var shareRobloxExperienceEnabled = AppSettings.default.shareRobloxExperienceEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard shareRobloxExperienceEnabled != oldValue else { return }
			persistSettings()
			refreshGamePresenceIfRecording()
		}
	}

	@Published var recordMicrophoneEnabled = AppSettings.default.recordMicrophoneEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard recordMicrophoneEnabled != oldValue else { return }

			if recordMicrophoneEnabled, !Self.supportsMicrophoneCapture {
				recordMicrophoneEnabled = false
				return
			}

			persistSettings()

			if recordMicrophoneEnabled {
				Task {
					do {
						try await PermissionManager.ensureMicrophoneAccess()
						permissionState = PermissionManager.currentState()
					} catch {
						AppLog.error(.app, "Microphone access denied:", error)
						// The user just answered the system prompt; resetting would only
						// make it ask again straight away.
						// (Only when the toggle is still on: otherwise the assignment is a
						// no-op, nothing would clear the flag, and the next real "off" would
						// skip its reset.)
						if recordMicrophoneEnabled {
							skipMicrophonePermissionReset = true
							recordMicrophoneEnabled = false
						}
					}
					restartCaptureSilently()
				}
			} else if skipMicrophonePermissionReset {
				skipMicrophonePermissionReset = false
				restartCaptureSilently()
			} else {
				restartCaptureThenResetMicrophonePermission()
			}
		}
	}

	@Published var recordDesktopAudioEnabled = AppSettings.default.recordDesktopAudioEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard recordDesktopAudioEnabled != oldValue else { return }
			persistSettings()
			restartCaptureSilently()
		}
	}

	/// only affects the next manual start's picker prompt, so no capture restart here
	@Published var captureTargetPromptEnabled = AppSettings.default.captureTargetPromptEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard captureTargetPromptEnabled != oldValue else { return }
			persistSettings()
		}
	}

	@Published var fileLoggingEnabled = AppSettings.default.fileLoggingEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard fileLoggingEnabled != oldValue else { return }
			AppLog.fileLoggingEnabled = fileLoggingEnabled
			persistSettings()
		}
	}

	@Published var analyticsEnabled = AppSettings.default.analyticsEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard analyticsEnabled != oldValue else { return }
			persistSettings()
			let enabled = analyticsEnabled
			Task { await analytics.setEnabled(enabled) }
		}
	}

	/// opt-in to the sparkle `beta` channel
	@Published var betaUpdatesEnabled = AppSettings.default.betaUpdatesEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard betaUpdatesEnabled != oldValue else { return }
			persistSettings()
		}
	}

	@Published var enabledUploadProviderIDs = AppSettings.default.enabledUploadProviderIDs {
		didSet {
			guard !isRestoringSettings else { return }
			guard enabledUploadProviderIDs != oldValue else { return }
			persistSettings()
		}
	}

	/// Enabled hosts in catalog order, which is the order the share menu uses.
	var enabledUploadProviders: [ClipUploadProvider] {
		ClipUploadProvider.providers.filter { enabledUploadProviderIDs.contains($0.id) }
	}

	func isUploadProviderEnabled(_ provider: ClipUploadProvider) -> Bool {
		enabledUploadProviderIDs.contains(provider.id)
	}

	func setUploadProvider(_ provider: ClipUploadProvider, enabled: Bool) {
		if enabled {
			guard !enabledUploadProviderIDs.contains(provider.id) else { return }
			enabledUploadProviderIDs.append(provider.id)
		} else {
			enabledUploadProviderIDs.removeAll { $0 == provider.id }
		}
	}

	@Published var outputDirectoryPath: String? {
		didSet {
			guard !isRestoringSettings else { return }
			guard outputDirectoryPath != oldValue else { return }
			persistSettings()
			// a new folder may be on a different volume, so re-evaluate now
			refreshStorageWarning()
		}
	}

	@Published private(set) var lowStorageWarningMessage: String?
	@Published private(set) var isAsleep = false

	var isDisplayOrSystemAsleep: Bool {
		isAsleep || CGDisplayIsAsleep(CGMainDisplayID()) != 0
	}

	private let captureManager: CaptureManager
	let clipLibrary: ClipLibrary
	private let discordRPCClient: DiscordRPCClient
	private let analytics: any AnalyticsTracking
	private let hotkeyManager: GlobalHotkeyManager
	private let soundFeedback = SoundFeedbackController()
	private var storageMonitor: StorageMonitor!
	private var discordActivityState: DiscordActivityState = .idle
	private var discordPresenceRetryTask: Task<Void, Never>?
	private let dotaGSIServer: DotaGSIServer?
	private let gameDetector: GamePresenceDetector
	private var gamePresenceTask: Task<Void, Never>?
	private var automaticCaptureRetryTask: Task<Void, Never>?
	/// Keeps the system content picker alive while it is presented (it is only an
	/// observer, so it must be retained). Created lazily on macOS 14+.
	private var contentPicker: Any?
	/// The most recent content selection, reused for silent restarts and automatic
	/// retries so the user is not re-prompted mid-session.
	private var lastContentFilter: UncheckedSendable<SCContentFilter>?
	/// Consecutive automatic-restart failures with the current `lastContentFilter`.
	/// If the picked window/app/display has gone away, every retry fails identically
	/// forever; once this crosses the threshold we drop the stale filter so the next
	/// attempt falls back to full-display capture instead of looping forever.
	private var automaticRestartFailureCount = 0
	/// Consecutive failed automatic starts, for retry backoff. Unlike
	/// `automaticRestartFailureCount` it is not reset by the full-display fallback.
	private var automaticRetryAttempt = 0
	private let silentRestartCoalescer = RestartCoalescer()
	private static let maxAutomaticRestartFailuresBeforeFallback = 3
	private var awaitingScreenGrant = false
	private var screenGrantPollTask: Task<Void, Never>?
	private var preferredResolutionID: String?
	private var isRestoringSettings = false
	private var skipMicrophonePermissionReset = false
	/// Whether the last Discord presence publish succeeded (i.e. Discord is reachable).
	private var discordPresenceConnected = false
	private var cancellables = Set<AnyCancellable>()

	init(
		captureManager: CaptureManager = CaptureManager(),
		clipLibrary: ClipLibrary = ClipLibrary(),
		discordRPCClient: DiscordRPCClient = DiscordRPCClient(),
		analytics: any AnalyticsTracking = NoopAnalytics(),
		hotkeyManager: GlobalHotkeyManager = .shared
	) {
		self.captureManager = captureManager
		self.clipLibrary = clipLibrary
		self.discordRPCClient = discordRPCClient
		self.analytics = analytics
		self.hotkeyManager = hotkeyManager

		let dotaGSIAuthToken = DotaGSIAuthToken.current()
		let dotaGSIServer = DotaGSIServer(port: DotaGSIServer.defaultPort, authToken: dotaGSIAuthToken)
		self.dotaGSIServer = dotaGSIServer
		gameDetector = GamePresenceDetector(dotaGSI: dotaGSIServer)
		dotaGSIServer?.start()
		Task.detached(priority: .utility) {
			DotaGSIConfigInstaller.install(port: DotaGSIServer.defaultPort, authToken: dotaGSIAuthToken)
		}

		clipLibrary.objectWillChange.sink { [weak self] _ in
			self?.objectWillChange.send()
		}.store(in: &cancellables)

		permissionState = PermissionManager.currentState()
		let settings = AppSettingsStorage.load()
		isRestoringSettings = true
		replayDuration = settings.replayDuration
		selectedQuality = settings.qualityPreset
		selectedFrameRate = settings.frameRateOption
		selectedContainer = settings.container
		selectedAudioCodec = settings.audioCodec
		desktopAudioVolume = settings.desktopAudioVolume
		microphoneVolume = settings.microphoneVolume
		preferredResolutionID = settings.resolutionID
		hotkey = settings.hotkey
		startRecordingHotkey = settings.startRecordingHotkey
		alwaysRecordEnabled = settings.alwaysRecordEnabled
		saveFeedbackEnabled = settings.saveFeedbackEnabled
		saveFeedbackVolume = settings.saveFeedbackVolume
		saveFeedbackSound = settings.saveFeedbackSound
		recordingStartFeedbackEnabled = settings.recordingStartFeedbackEnabled
		recordingStartFeedbackVolume = settings.recordingStartFeedbackVolume
		recordingStartFeedbackSound = settings.recordingStartFeedbackSound
		recordingEndFeedbackEnabled = settings.recordingEndFeedbackEnabled
		recordingEndFeedbackVolume = settings.recordingEndFeedbackVolume
		recordingEndFeedbackSound = settings.recordingEndFeedbackSound
		errorFeedbackEnabled = settings.errorFeedbackEnabled
		errorFeedbackVolume = settings.errorFeedbackVolume
		errorFeedbackSound = settings.errorFeedbackSound
		discordRPCEnabled = settings.discordRPCEnabled
		shareGamePresenceEnabled = settings.shareGamePresenceEnabled
		shareRobloxExperienceEnabled = settings.shareRobloxExperienceEnabled
		fileLoggingEnabled = settings.fileLoggingEnabled
		analyticsEnabled = settings.analyticsEnabled
		betaUpdatesEnabled = settings.betaUpdatesEnabled
		enabledUploadProviderIDs = settings.enabledUploadProviderIDs
		recordMicrophoneEnabled = settings.recordMicrophoneEnabled
		recordDesktopAudioEnabled = settings.recordDesktopAudioEnabled
		captureTargetPromptEnabled = settings.captureTargetPromptEnabled
		selectedMicrophoneDeviceID = settings.microphoneDeviceID
		outputDirectoryPath = settings.outputDirectoryPath
		isRestoringSettings = false
		refreshMicrophones()
		AppLog.fileLoggingEnabled = fileLoggingEnabled
		Task { [weak self] in
			await self?.captureManager.setOnCaptureInterruptedHandler { [weak self] error in
				self?.handleCaptureInterrupted(error)
			}
		}
		Task { await loadAvailableResolutions() }
		storageMonitor = StorageMonitor { [weak self] message in
			guard let self else { return }
			let warningWasVisible = lowStorageWarningMessage != nil
			lowStorageWarningMessage = message
			if !warningWasVisible, message != nil {
				Task { await analytics.lowStorageWarningShown() }
			}
		}
		storageMonitor.start()
		Task {
			await discordRPCClient.setEnabled(discordRPCEnabled)
			self.publishDiscordPresenceWithRetry(for: self.discordActivityState)
		}
		setupDefaultsObservers()
	}

	private func setupDefaultsObservers() {
		Defaults.observe(.analyticsEnabled) { [weak self] change in
			guard let self else { return }
			Task { @MainActor in
				await self.analytics.setEnabled(change.newValue)
			}
		}.tieToLifetime(of: self)

		Defaults.observe(.fileLoggingEnabled) { change in
			AppLog.fileLoggingEnabled = change.newValue
		}.tieToLifetime(of: self)

		Defaults.observe(.discordRPCEnabled) { [weak self] change in
			guard let self else { return }
			Task { @MainActor in
				await self.discordRPCClient.setEnabled(change.newValue)
				if change.newValue {
					self.publishDiscordPresenceWithRetry(for: self.discordActivityState)
					if self.isCapturing, self.discordActivityState.isRecording, self.gamePresenceTask == nil {
						self.startGamePresenceUpdates()
					}
				} else {
					self.discordPresenceRetryTask?.cancel()
					self.discordPresenceRetryTask = nil
				}
			}
		}.tieToLifetime(of: self)

		Defaults.observe(.shareGamePresenceEnabled) { [weak self] _ in
			Task { @MainActor [weak self] in
				self?.refreshGamePresenceIfRecording()
			}
		}.tieToLifetime(of: self)

		Defaults.observe(.shareRobloxExperienceEnabled) { [weak self] _ in
			Task { @MainActor [weak self] in
				self?.refreshGamePresenceIfRecording()
			}
		}.tieToLifetime(of: self)
	}

	func resetToDefaults() {
		let settings = AppSettings.default
		let wasAlwaysRecording = alwaysRecordEnabled

		isRestoringSettings = true
		replayDuration = settings.replayDuration
		selectedQuality = settings.qualityPreset
		selectedFrameRate = settings.frameRateOption
		selectedContainer = settings.container
		selectedAudioCodec = settings.audioCodec
		desktopAudioVolume = settings.desktopAudioVolume
		microphoneVolume = settings.microphoneVolume
		preferredResolutionID = settings.resolutionID
		selectedResolution = availableResolutions.first(where: { $0.isNative })
			?? availableResolutions.first
		hotkey = settings.hotkey
		startRecordingHotkey = settings.startRecordingHotkey
		alwaysRecordEnabled = settings.alwaysRecordEnabled
		saveFeedbackEnabled = settings.saveFeedbackEnabled
		saveFeedbackVolume = settings.saveFeedbackVolume
		saveFeedbackSound = settings.saveFeedbackSound
		recordingStartFeedbackEnabled = settings.recordingStartFeedbackEnabled
		recordingStartFeedbackVolume = settings.recordingStartFeedbackVolume
		recordingStartFeedbackSound = settings.recordingStartFeedbackSound
		recordingEndFeedbackEnabled = settings.recordingEndFeedbackEnabled
		recordingEndFeedbackVolume = settings.recordingEndFeedbackVolume
		recordingEndFeedbackSound = settings.recordingEndFeedbackSound
		errorFeedbackEnabled = settings.errorFeedbackEnabled
		errorFeedbackVolume = settings.errorFeedbackVolume
		errorFeedbackSound = settings.errorFeedbackSound
		discordRPCEnabled = settings.discordRPCEnabled
		shareGamePresenceEnabled = settings.shareGamePresenceEnabled
		shareRobloxExperienceEnabled = settings.shareRobloxExperienceEnabled
		fileLoggingEnabled = settings.fileLoggingEnabled
		analyticsEnabled = settings.analyticsEnabled
		betaUpdatesEnabled = settings.betaUpdatesEnabled
		enabledUploadProviderIDs = settings.enabledUploadProviderIDs
		recordMicrophoneEnabled = settings.recordMicrophoneEnabled
		recordDesktopAudioEnabled = settings.recordDesktopAudioEnabled
		captureTargetPromptEnabled = settings.captureTargetPromptEnabled
		selectedMicrophoneDeviceID = settings.microphoneDeviceID
		outputDirectoryPath = settings.outputDirectoryPath
		isRestoringSettings = false

		persistSettings()
		AppLog.fileLoggingEnabled = fileLoggingEnabled
		let shouldEnableAnalytics = analyticsEnabled
		Task { await analytics.setEnabled(shouldEnableAnalytics) }
		updateGlobalHotkeys()
		Task { await discordRPCClient.setEnabled(discordRPCEnabled) }
		if wasAlwaysRecording, !alwaysRecordEnabled, isCapturing {
			Task { await stopCaptureAsync() }
		} else {
			restartCaptureSilently()
		}
	}

	func startCapture(isAutomatic: Bool = false) {
		startCapture(reason: isAutomatic ? .retry : .manual)
	}

	func startAlwaysRecording(isAutomatic: Bool = true) {
		guard alwaysRecordEnabled else { return }
		if isDisplayOrSystemAsleep {
			return
		}
		startCapture(reason: isAutomatic ? .alwaysRecord : .manual)
	}

	func stopCapture() {
		guard !alwaysRecordEnabled else { return }
		Task { await stopCaptureAsync() }
	}

	func saveReplay() {
		Task { await saveReplayAsync() }
	}

	func trackAppOpened() {
		let settings = analyticsSettingsSnapshot
		Task { await analytics.appOpened(settings: settings) }
	}

	func trackClipAction(action: String, result: String = "success", provider: String? = nil) {
		Task { await analytics.clipAction(action: action, result: result, provider: provider) }
	}

	func toggleCapture() {
		if isCapturing {
			guard !alwaysRecordEnabled else { return }
			stopCapture()
		} else {
			startCapture(isAutomatic: false)
		}
	}

	func refreshPermissions() {
		Task { await refreshPermissionsAsync() }
	}

	/// Opens the Screen Recording settings pane and watches for the grant, then
	/// relaunches automatically so the user never has to quit and reopen the app.
	func requestScreenRecordingAccess() {
		PermissionManager.openSystemSettings()
		awaitingScreenGrant = true
		screenGrantPollTask?.cancel()
		screenGrantPollTask = Task { @MainActor [weak self] in
			// Back up the app-becomes-active refresh in case the user grants
			// while Rewind is still frontmost. Give up after a few minutes.
			for _ in 0 ..< 200 {
				try? await Task.sleep(nanoseconds: 1_500_000_000)
				guard let self, self.awaitingScreenGrant else { return }
				if PermissionManager.currentState().screenRecording {
					self.relaunchForScreenGrant()
					return
				}
			}
		}
	}

	private func relaunchForScreenGrant() {
		guard awaitingScreenGrant else { return }
		awaitingScreenGrant = false
		screenGrantPollTask?.cancel()
		screenGrantPollTask = nil
		PermissionManager.relaunch()
	}

	func refreshResolutions() {
		Task { await loadAvailableResolutions() }
	}

	/// enumeration is instant, so this stays synchronous unlike resolutions.
	/// a selected-but-now-disconnected mic reconciles back to the system default.
	func refreshMicrophones() {
		let devices = MicrophoneDeviceProvider.availableDevices()
		availableMicrophones = devices
		if let selected = selectedMicrophoneDeviceID,
		   !devices.contains(where: { $0.id == selected })
		{
			selectedMicrophoneDeviceID = nil
		}
	}

	private func loadAvailableResolutions() async {
		guard !isLoadingResolutions else { return }

		isLoadingResolutions = true
		resolutionLoadingMessage = nil
		defer { isLoadingResolutions = false }

		let resolutions = await CaptureResolutionProvider.availableResolutions()
		if !resolutions.isEmpty {
			availableResolutions = resolutions

			if let selectedResolutionID = selectedResolution?.id,
			   let currentSelection = resolutions.first(where: { $0.id == selectedResolutionID })
			{
				if selectedResolution != currentSelection {
					selectedResolution = currentSelection
				}
				preferredResolutionID = currentSelection.id
				return
			}

			if let preferredResolutionID,
			   let preferredResolution = resolutions.first(where: {
			   	$0.id == preferredResolutionID
			   })
			{
				selectedResolution = preferredResolution
				return
			}

			if let native = resolutions.first(where: { $0.isNative }) {
				selectedResolution = native
			} else {
				selectedResolution = resolutions.first
			}
			return
		}

		permissionState = PermissionManager.currentState()
		if !permissionState.screenRecording {
			availableResolutions = []
			resolutionLoadingMessage = "Screen recording permission required"
			return
		}

		availableResolutions = []
		resolutionLoadingMessage = "Could not load resolutions"
		AppLog.error(.app, "Resolutions did not load after multiple tries")
	}

	private func startCapture(reason: AnalyticsCaptureStartReason) {
		Task { await startCaptureAsync(reason: reason) }
	}

	private func startCaptureAsync(reason: AnalyticsCaptureStartReason) async {
		let isAutomatic = reason != .manual
		if isDisplayOrSystemAsleep {
			return
		}
		if !isAutomatic {
			automaticCaptureRetryTask?.cancel()
		}
		do {
			try await PermissionManager.ensureScreenAccess(prompt: !isAutomatic)
			permissionState = PermissionManager.currentState()

			// On a manual start, let the user choose what to capture. Automatic
			// starts (retries) silently reuse the last selection so recording can
			// resume without interrupting the user.
			let contentFilter: UncheckedSendable<SCContentFilter>?
			if isAutomatic {
				contentFilter = lastContentFilter
			} else if captureTargetPromptEnabled, #available(macOS 14.0, *) {
				do {
					contentFilter = try await presentContentPicker()
					lastContentFilter = contentFilter
				} catch is ContentSharingPicker.Cancelled {
					// User dismissed the picker; abort the start without an error.
					return
				}
			} else {
				contentFilter = nil
			}

			try await captureManager.start(
				contentFilter: contentFilter,
				resolution: selectedResolution,
				quality: selectedQuality,
				frameRate: selectedFrameRate.framesPerSecond,
				audioCodec: selectedAudioCodec,
				recordMicrophoneEnabled: recordMicrophoneEnabled,
				recordDesktopAudioEnabled: recordDesktopAudioEnabled,
				microphoneDeviceID: selectedMicrophoneDeviceID
			)
			isCapturing = true
			let settings = analyticsSettingsSnapshot
			Task { await analytics.captureSessionStarted(reason: reason, settings: settings) }
			automaticRestartFailureCount = 0
			automaticRetryAttempt = 0
			updateDiscordActivity(.recording(game: nil, joinURL: nil, artURL: nil))
			if !isAutomatic {
				playRecordingStartFeedback()
			}
			automaticCaptureRetryTask?.cancel()
		} catch {
			isCapturing = false
			updateDiscordActivity(.idle)
			if case PermissionError.screenRecordingDenied = error {
				// Refresh so the menu-bar permission banner reflects reality.
				permissionState = PermissionManager.currentState()
			}
			let category = analyticsErrorCategory(error)
			let willRetry = isAutomatic && CaptureRetryPolicy.shouldRetry(after: error)
			Task {
				await analytics.captureStartFailed(
					reason: reason,
					category: category,
					retrying: willRetry
				)
			}

			if isAutomatic {
				if isDisplayOrSystemAsleep {
					return
				}
				AppLog.error(.app, "Automatic capture start failed", error)
				guard CaptureRetryPolicy.shouldRetry(after: error) else {
					AppLog.error(.app, "Not retrying automatic capture: Screen Recording permission is missing")
					return
				}
				automaticRestartFailureCount += 1
				if automaticRestartFailureCount >= Self.maxAutomaticRestartFailuresBeforeFallback {
					AppLog.error(
						.app,
						"Automatic capture repeatedly failed with the previous capture target; falling back to full-display capture."
					)
					lastContentFilter = nil
					automaticRestartFailureCount = 0
				}
				scheduleCaptureRetry()
				return
			}

			playErrorFeedback()

			let alert = NSAlert()
			alert.messageText = "Rewind failed to start capture"
			alert.informativeText =
				"Rewind could not start recording: \(error.localizedDescription)"
			alert.alertStyle = .critical
			alert.addButton(withTitle: "OK")

			NSApp.activate(ignoringOtherApps: true)
			alert.runModal()
		}
	}

	private func stopCaptureAsync(reason: AnalyticsCaptureEndReason = .manual) async {
		automaticCaptureRetryTask?.cancel()
		await captureManager.stop()
		isCapturing = false
		Task { await analytics.captureSessionEnded(reason: reason) }
		updateDiscordActivity(.idle)
		if reason == .manual {
			playRecordingEndFeedback()
		}
	}

	/// Presents the macOS content picker and returns the chosen filter, boxed so it
	/// can cross into the capture actor. Retains the picker for the presentation.
	@available(macOS 14.0, *)
	private func presentContentPicker() async throws -> UncheckedSendable<SCContentFilter> {
		let picker = ContentSharingPicker()
		contentPicker = picker
		defer { contentPicker = nil }
		return try await picker.pick()
	}

	private func restartCaptureSilently() {
		guard isCapturing else { return }
		if isDisplayOrSystemAsleep {
			return
		}
		// Settings often change in bursts (quality then frame rate, ...). Coalesce
		// them so restarts never overlap and the last one uses the latest settings.
		silentRestartCoalescer.request { [weak self] in
			await self?.performSilentRestart()
		}
	}

	/// Turning the microphone off should also remove Rewind's macOS Microphone
	/// permission. Capture is restarted without the mic first, so the permission
	/// isn't pulled out from under a running mic stream.
	private func restartCaptureThenResetMicrophonePermission() {
		// If the user switched the mic back on in the meantime, capture is (or is
		// about to be) using it: resetting the permission now would pull it out
		// from under the stream, so re-check at the last moment.
		let reset: @MainActor () -> Void = { [weak self] in
			guard let self, !self.recordMicrophoneEnabled else { return }
			Task.detached(priority: .utility) { [weak self] in
				let stillOff = await MainActor.run { self.map { !$0.recordMicrophoneEnabled } ?? false }
				guard stillOff else { return }
				TCCReset.resetMicrophone()
				await MainActor.run { [weak self] in
					self?.permissionState = PermissionManager.currentState()
				}
			}
		}
		guard isCapturing, !isDisplayOrSystemAsleep else {
			reset()
			return
		}
		silentRestartCoalescer.request({ [weak self] in
			await self?.performSilentRestart()
		}, completion: reset)
	}

	private func performSilentRestart() async {
		guard isCapturing, !isDisplayOrSystemAsleep else { return }
		await captureManager.stop()
		// The user may have pressed Stop, or the system gone to sleep, while the
		// stop above was in flight; don't bring capture back in that case.
		guard isCapturing, !isDisplayOrSystemAsleep else { return }
		do {
			try await captureManager.start(
				contentFilter: lastContentFilter,
				resolution: selectedResolution,
				quality: selectedQuality,
				frameRate: selectedFrameRate.framesPerSecond,
				audioCodec: selectedAudioCodec,
				recordMicrophoneEnabled: recordMicrophoneEnabled,
				recordDesktopAudioEnabled: recordDesktopAudioEnabled,
				microphoneDeviceID: selectedMicrophoneDeviceID
			)
		} catch {
			isCapturing = false
			updateDiscordActivity(.idle)
			playErrorFeedback()
			AppLog.error(.app, "Silent restart failed:", error)
		}
	}

	/// Clears `lastClip` if it points at a clip that was just deleted, so
	/// "Open Last Clip" doesn't stay enabled and try to open a missing file.
	func clipWasDeleted(_ clip: Clip) {
		if lastClip?.id == clip.id {
			lastClip = nil
		}
	}

	private func saveReplayAsync() async {
		let requestedDuration = replayDuration
		let requestedContainerID = selectedContainer.id
		let startedAt = Date()
		Task {
			await analytics.replaySaveRequested(
				duration: requestedDuration,
				containerID: requestedContainerID
			)
		}
		do {
			let url = try await captureManager.saveReplay(
				seconds: replayDuration, container: selectedContainer,
				desktopAudioVolume: desktopAudioVolume, microphoneVolume: microphoneVolume
			)
			let clipDuration = try await resolvedClipDuration(for: url)
			let clip = try await clipLibrary.addClip(url: url, duration: clipDuration)
			lastClip = clip
			let processingMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
			Task {
				await analytics.replaySaved(
					duration: requestedDuration,
					containerID: requestedContainerID,
					processingMilliseconds: processingMilliseconds
				)
			}
			playReplaySavedFeedback()
			refreshStorageWarning()
		} catch {
			AppLog.error(.app, "Save replay failed:", error)
			let category = analyticsErrorCategory(error)
			Task { await analytics.replaySaveFailed(category: category) }
			playErrorFeedback()
		}
	}

	private func updateDiscordActivity(_ state: DiscordActivityState) {
		let previous = discordActivityState
		guard previous != state else { return }
		discordActivityState = state
		publishDiscordPresenceWithRetry(for: state)

		// Only manage the game poller on the idle<->recording transition, not
		// when the poller itself refines the game name (recording -> recording).
		if state.isRecording, !previous.isRecording {
			startGamePresenceUpdates()
		} else if !state.isRecording, previous.isRecording {
			gamePresenceTask?.cancel()
			gamePresenceTask = nil
		}
	}

	/// While recording, periodically look up the game being played and fold it
	/// into the Discord presence so it reads "Clipping <game>".
	private func startGamePresenceUpdates() {
		// (Only resolves the running game once Discord has accepted a presence,
		// since enumerating every running app is wasted work when nothing can show it.)
		gamePresenceTask?.cancel()
		gamePresenceTask = Task { @MainActor [weak self] in
			while !Task.isCancelled {
				guard let self, self.isCapturing, self.discordRPCEnabled,
				      self.discordActivityState.isRecording else { return }
				guard self.discordPresenceConnected else {
					try? await Task.sleep(nanoseconds: 10_000_000_000)
					continue
				}
				// Respect the privacy toggle: when game sharing is off, show only a
				// generic recording status instead of resolving the running game.
				let presence = self.shareGamePresenceEnabled
					? await self.gameDetector.currentGame(enrichRoblox: self.shareRobloxExperienceEnabled)
					: nil
				if self.discordActivityState.isRecording {
					self.updateDiscordActivity(.recording(game: presence?.name, joinURL: presence?.joinURL, artURL: presence?.artURL))
				}
				try? await Task.sleep(nanoseconds: 10_000_000_000)
			}
		}
	}

	private func refreshGamePresenceIfRecording() {
		guard isCapturing, discordRPCEnabled, discordActivityState.isRecording else { return }
		startGamePresenceUpdates()
	}

	private func publishDiscordPresenceWithRetry(for state: DiscordActivityState) {
		guard discordRPCEnabled else { return }

		discordPresenceRetryTask?.cancel()
		discordPresenceRetryTask = Task { @MainActor [weak self] in
			guard let self else { return }

			var failedAttempts = 0
			while !Task.isCancelled {
				guard self.discordRPCEnabled, self.discordActivityState == state else { return }
				let published = await self.discordRPCClient.publish(state: state)
				self.discordPresenceConnected = published
				if published { return }
				failedAttempts += 1
				let delay = DiscordPresenceRetry.delay(forAttempt: failedAttempts)
				try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
			}
		}
	}

	func playReplaySavedFeedback() {
		soundFeedback.play(
			.saved,
			enabled: saveFeedbackEnabled,
			volume: saveFeedbackVolume,
			sound: saveFeedbackSound,
			defaultSoundName: "save"
		)
	}

	func playRecordingStartFeedback() {
		soundFeedback.play(
			.recordingStart,
			enabled: recordingStartFeedbackEnabled,
			volume: recordingStartFeedbackVolume,
			sound: recordingStartFeedbackSound,
			defaultSoundName: "start"
		)
	}

	func playRecordingEndFeedback() {
		soundFeedback.play(
			.recordingEnd,
			enabled: recordingEndFeedbackEnabled,
			volume: recordingEndFeedbackVolume,
			sound: recordingEndFeedbackSound,
			defaultSoundName: "end"
		)
	}

	func playErrorFeedback() {
		soundFeedback.play(
			.error,
			enabled: errorFeedbackEnabled,
			volume: errorFeedbackVolume,
			sound: errorFeedbackSound,
			defaultSoundName: "error"
		)
	}

	private func resolvedClipDuration(for url: URL) async throws -> TimeInterval {
		let asset = AVURLAsset(url: url)
		do {
			let duration = try await asset.load(.duration)
			let seconds = CMTimeGetSeconds(duration)
			if seconds.isFinite, seconds > 0 {
				return seconds
			}
		} catch {
			AppLog.info(.app, "Couldnt read export clip duration", error)
			throw error
		}
		throw CaptureError.invalidDuration
	}

	private func refreshPermissionsAsync() async {
		permissionState = PermissionManager.currentState()
		// If the user just granted Screen Recording (typically detected when the
		// app becomes active again), relaunch to apply it.
		if awaitingScreenGrant, permissionState.screenRecording {
			relaunchForScreenGrant()
		}
	}

	func handleSleep() {
		guard !isAsleep else { return }
		AppLog.info(.app, "System going to sleep")
		isAsleep = true
		automaticCaptureRetryTask?.cancel()
		automaticCaptureRetryTask = nil
		automaticRetryAttempt = 0
		if isCapturing {
			// Flip the flag first: if the system wakes while the stop is still in
			// flight, the wake's start (queued behind the stop) sets it back to
			// true afterwards instead of this task clobbering it.
			isCapturing = false
			updateDiscordActivity(.idle)
			Task {
				await captureManager.stop()
				await analytics.captureSessionEnded(reason: .sleep)
			}
		}
	}

	func handleWake() {
		guard isAsleep else { return }
		AppLog.info(.app, "System waking up")
		isAsleep = false
		automaticRetryAttempt = 0
		if alwaysRecordEnabled, !isDisplayOrSystemAsleep {
			startCapture(reason: .wake)
		}
	}

	private func handleCaptureInterrupted(_ error: Error) {
		isCapturing = false
		updateDiscordActivity(.idle)
		if isDisplayOrSystemAsleep {
			return
		}
		if !alwaysRecordEnabled {
			playErrorFeedback()
		}
		AppLog.error(.app, "Capture interrupted:", error)
		let category = analyticsErrorCategory(error)
		Task {
			await analytics.captureInterrupted(category: category, retrying: true)
			await analytics.captureSessionEnded(reason: .interrupted)
		}
		scheduleCaptureRetry()
	}

	private func scheduleCaptureRetry() {
		automaticCaptureRetryTask?.cancel()
		automaticRetryAttempt += 1
		let delay = CaptureRetryPolicy.delay(forAttempt: automaticRetryAttempt)
		automaticCaptureRetryTask = Task { @MainActor [weak self] in
			guard let self else { return }
			try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
			if Task.isCancelled { return }
			if self.isDisplayOrSystemAsleep {
				return
			}
			if !self.isCapturing {
				self.startCapture(reason: .retry)
			}
		}
	}

	private var analyticsSettingsSnapshot: AnalyticsSettingsSnapshot {
		AnalyticsSettingsSnapshot(
			replayDurationBucket: PostHogAnalytics.durationBucket(for: replayDuration),
			resolution: selectedResolution?.id ?? preferredResolutionID ?? "unknown",
			quality: selectedQuality.id,
			frameRate: selectedFrameRate.framesPerSecond,
			container: selectedContainer.id,
			audioCodec: selectedAudioCodec.id,
			alwaysRecordEnabled: alwaysRecordEnabled,
			microphoneEnabled: recordMicrophoneEnabled,
			desktopAudioEnabled: recordDesktopAudioEnabled,
			captureTargetPromptEnabled: captureTargetPromptEnabled,
			discordRPCEnabled: discordRPCEnabled,
			gamePresenceEnabled: shareGamePresenceEnabled,
			robloxExperienceEnabled: shareRobloxExperienceEnabled,
			// Kept as two booleans so the existing analytics schema stays intact,
			// even though uploads are now a list of providers.
			catboxEnabled: enabledUploadProviderIDs.contains(ClipUploadProvider.catboxID),
			litterboxEnabled: enabledUploadProviderIDs.contains(ClipUploadProvider.litterboxID),
			launchAtLoginEnabled: launchAtLoginEnabled,
			betaUpdatesEnabled: betaUpdatesEnabled,
			customOutputDirectory: outputDirectoryPath != nil
		)
	}

	private func analyticsErrorCategory(_ error: Error) -> String {
		if let captureError = error as? CaptureError {
			switch captureError {
			case .noDisplay:
				return "no_display"
			case .noAudioDevice:
				return "no_audio_device"
			case .writerUnavailable:
				return "writer_unavailable"
			case .noFramesCaptured:
				return "no_frames"
			case .exportFailed:
				return "export_failed"
			case .saveInProgress:
				return "save_in_progress"
			case .invalidDuration:
				return "invalid_duration"
			case .writerFinishTimedOut:
				return "writer_timeout"
			case let .streamStopped(reason):
				// Split these apart deliberately. A stop with no error at all is the
				// signature of the macOS 14.7–15.3 ScreenCaptureKit bug, so counting
				// it separately shows how often that fires in the wild. Only the
				// fixed category is reported, never the reason text.
				return reason == nil ? "stream_stopped_null_error" : "stream_stopped"
			}
		}

		return "unknown"
	}

	private func updateGlobalHotkeys() {
		hotkeyManager.updateHotkeys(
			saveReplay: hotkey,
			recordToggle: startRecordingHotkey
		)
	}

	private func persistSettings() {
		let settings = analyticsSettingsSnapshot
		Task { await analytics.settingsUpdated(settings) }
	}

	private func refreshStorageWarning() {
		storageMonitor.refresh()
	}
}
