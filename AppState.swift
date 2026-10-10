import AppKit
@preconcurrency import AVFoundation
import Combine
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
	@Published private(set) var isStartingCapture = false
	@Published private(set) var isStoppingCapture = false
	@Published private(set) var isRestartingCapture = false
	@Published private(set) var isSavingReplay = false
	@Published private(set) var hotkeyConflictMessage: String?

	var isCaptureTransitioning: Bool {
		isStartingCapture || isStoppingCapture || isRestartingCapture
	}
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

	@Published var selectedRecordingMode: RecordingMode = .default {
		didSet {
			guard !isRestoringSettings else { return }
			guard selectedRecordingMode != oldValue else { return }
			guard !isCapturing, !isCaptureTransitioning else {
				isRestoringSettings = true
				selectedRecordingMode = oldValue
				isRestoringSettings = false
				return
			}
			automaticCaptureRetryTask?.cancel()
			automaticCaptureRetryTask = nil
			if selectedRecordingMode != .instantReplay {
				resumeAlwaysRecordingAfterStop = false
			}
			persistSettings()
			if selectedRecordingMode == .instantReplay, alwaysRecordEnabled {
				startCapture(reason: .alwaysRecord)
			}
		}
	}

	@Published var hotkey: Hotkey = .default {
		didSet {
			guard !isRestoringSettings else { return }
			guard hotkey != oldValue else { return }
			guard hotkey != startRecordingHotkey, hotkey != stopRecordingHotkey else {
				rejectHotkeyChange(
					message: "Save Last Clip must use a different shortcut from Start and Stop."
				) { hotkey = oldValue }
				return
			}
			hotkeyConflictMessage = nil
			persistSettings()
			updateGlobalHotkeys()
		}
	}

	@Published var startRecordingHotkey: Hotkey = .startRecordingDefault {
		didSet {
			guard !isRestoringSettings else { return }
			guard startRecordingHotkey != oldValue else { return }
			guard startRecordingHotkey != hotkey,
			      startRecordingHotkey != stopRecordingHotkey
			else {
				rejectHotkeyChange(
					message: "Start Recording must use a unique shortcut."
				) { startRecordingHotkey = oldValue }
				return
			}
			hotkeyConflictMessage = nil
			persistSettings()
			updateGlobalHotkeys()
		}
	}

	@Published var stopRecordingHotkey: Hotkey = .stopRecordingDefault {
		didSet {
			guard !isRestoringSettings else { return }
			guard stopRecordingHotkey != oldValue else { return }
			guard stopRecordingHotkey != hotkey,
			      stopRecordingHotkey != startRecordingHotkey
			else {
				rejectHotkeyChange(
					message: "Stop Recording must use a unique shortcut."
				) { stopRecordingHotkey = oldValue }
				return
			}
			hotkeyConflictMessage = nil
			persistSettings()
			updateGlobalHotkeys()
		}
	}

	@Published var alwaysRecordEnabled = AppSettings.default.alwaysRecordEnabled {
		didSet {
			guard !isRestoringSettings else { return }
			guard alwaysRecordEnabled != oldValue else { return }
			persistSettings()
			if alwaysRecordEnabled, selectedRecordingMode == .instantReplay {
				startCapture(reason: .alwaysRecord)
			} else if !alwaysRecordEnabled {
				resumeAlwaysRecordingAfterStop = false
				if isStartingCapture {
					cancelPendingCaptureStart()
				}
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
						recordMicrophoneEnabled = false
					}
					restartCaptureSilently()
				}
			} else {
				restartCaptureSilently()
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
	private var captureStartTask: Task<Void, Never>?
	private var captureStopTask: Task<Void, Never>?
	private var replayRestartTask: Task<Void, Never>?
	private var captureGeneration: UInt64 = 0
	private var replayRestartGeneration: UInt64 = 0
	private var resumeAlwaysRecordingAfterStop = false
	/// The mode that owns the active capture pipeline. This is intentionally
	/// separate from the selected preference so an in-flight stop always uses the
	/// matching capture API, even if settings are reset at the same time.
	private var activeRecordingMode: RecordingMode?
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
	private static let maxAutomaticRestartFailuresBeforeFallback = 3
	private var awaitingScreenGrant = false
	private var screenGrantPollTask: Task<Void, Never>?
	private var preferredResolutionID: String?
	private var isRestoringSettings = false
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

		let dotaGSIAuthToken = UUID().uuidString
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
		selectedRecordingMode = settings.recordingMode
		preferredResolutionID = settings.resolutionID
		hotkey = settings.hotkey
		startRecordingHotkey = if settings.startRecordingHotkey == hotkey {
			Hotkey.startRecordingDefault(avoiding: [hotkey])
		} else {
			settings.startRecordingHotkey
		}
		stopRecordingHotkey = if settings.stopRecordingHotkey == hotkey
			|| settings.stopRecordingHotkey == startRecordingHotkey
		{
			Hotkey.stopRecordingDefault(avoiding: [hotkey, startRecordingHotkey])
		} else {
			settings.stopRecordingHotkey
		}
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
			await self?.captureManager.setOnCaptureInterruptedHandler { [weak self] error, recoveredRecordingURL in
				self?.handleCaptureInterrupted(
					error,
					recoveredRecordingURL: recoveredRecordingURL
				)
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
	}

	func resetToDefaults() {
		if isStartingCapture {
			cancelPendingCaptureStart()
		}
		let settings = AppSettings.default
		let wasAlwaysRecording = alwaysRecordEnabled
		let activeModeBeforeReset = activeRecordingMode

		isRestoringSettings = true
		replayDuration = settings.replayDuration
		selectedQuality = settings.qualityPreset
		selectedFrameRate = settings.frameRateOption
		selectedContainer = settings.container
		selectedAudioCodec = settings.audioCodec
		selectedRecordingMode = settings.recordingMode
		preferredResolutionID = settings.resolutionID
		selectedResolution = availableResolutions.first(where: { $0.isNative })
			?? availableResolutions.first
		hotkey = settings.hotkey
		startRecordingHotkey = settings.startRecordingHotkey
		stopRecordingHotkey = settings.stopRecordingHotkey
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
		if activeModeBeforeReset == .recording, isCapturing {
			stopRecording()
		} else if wasAlwaysRecording, !alwaysRecordEnabled, isCapturing {
			beginReplayStop(reason: .manual)
		} else {
			restartCaptureSilently()
		}
	}

	func startCapture(isAutomatic: Bool = false) {
		startCapture(reason: isAutomatic ? .retry : .manual)
	}

	/// Starts the currently selected mode. Repeated start-hotkey presses while a
	/// capture or transition is active are intentionally idempotent.
	func startRecording() {
		guard !isCapturing, !isCaptureTransitioning else { return }
		startCapture(reason: .manual)
	}

	func startAlwaysRecording(isAutomatic: Bool = true) {
		guard alwaysRecordEnabled, selectedRecordingMode == .instantReplay else { return }
		if isDisplayOrSystemAsleep {
			return
		}
		startCapture(reason: isAutomatic ? .alwaysRecord : .manual)
	}

	func stopCapture() {
		if selectedRecordingMode == .instantReplay, alwaysRecordEnabled {
			alwaysRecordEnabled = false
		}
		automaticCaptureRetryTask?.cancel()
		automaticCaptureRetryTask = nil
		if isStartingCapture {
			cancelPendingCaptureStart()
			return
		}
		if isRestartingCapture {
			beginReplayStop(reason: .manual)
			return
		}
		guard activeRecordingMode != .recording else { return }
		guard isCapturing, !isCaptureTransitioning else { return }
		beginReplayStop(reason: .manual)
	}

	/// Stops the active mode. Recording mode finalizes and adds the whole session
	/// to the clip library; Instant Replay simply stops its rolling buffer.
	func stopRecording() {
		if selectedRecordingMode == .instantReplay {
			if alwaysRecordEnabled {
				alwaysRecordEnabled = false
			}
			automaticCaptureRetryTask?.cancel()
			automaticCaptureRetryTask = nil
		}
		if isStartingCapture {
			cancelPendingCaptureStart()
			return
		}
		if isRestartingCapture {
			if alwaysRecordEnabled {
				alwaysRecordEnabled = false
			}
			beginReplayStop(reason: .manual)
			return
		}
		guard isCapturing, !isCaptureTransitioning else { return }
		if activeRecordingMode == .recording {
			beginManualRecordingStop(reason: .manual)
		} else {
			stopCapture()
		}
	}

	func saveReplay() {
		guard activeRecordingMode == .instantReplay,
		      isCapturing,
		      !isCaptureTransitioning,
		      !isSavingReplay
		else { return }
		isSavingReplay = true
		Task {
			await saveReplayAsync()
			isSavingReplay = false
		}
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
			stopRecording()
		} else {
			startRecording()
		}
	}

	var needsCaptureShutdown: Bool {
		isCapturing || isCaptureTransitioning
	}

	/// Finalizes an OBS-style recording before the process exits. Replay capture
	/// has no user-owned pending file, so it is stopped and discarded normally.
	func prepareForTermination() async {
		resumeAlwaysRecordingAfterStop = false
		automaticCaptureRetryTask?.cancel()
		automaticCaptureRetryTask = nil

		if isStartingCapture {
			cancelPendingCaptureStart()
			await captureStartTask?.value
		}
		if isStoppingCapture {
			await captureStopTask?.value
			return
		}
		if isCapturing, activeRecordingMode == .recording {
			beginManualRecordingStop(reason: .manual)
			await captureStopTask?.value
		} else if isCapturing {
			beginReplayStop(reason: .manual)
			await captureStopTask?.value
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
		guard !isCapturing, !isCaptureTransitioning else { return }
		let requestedMode = reason == .manual ? selectedRecordingMode : .instantReplay
		guard reason == .manual || selectedRecordingMode == .instantReplay else { return }
		captureGeneration &+= 1
		let generation = captureGeneration
		isStartingCapture = true
		captureStartTask = Task {
			await startCaptureAsync(
				reason: reason,
				mode: requestedMode,
				generation: generation
			)
		}
	}

	private func startCaptureAsync(
		reason: AnalyticsCaptureStartReason,
		mode: RecordingMode,
		generation: UInt64
	) async {
		defer {
			if captureGeneration == generation {
				captureStartTask = nil
				isStartingCapture = false
				resumeAlwaysRecordingIfNeeded()
			}
		}
		let isAutomatic = reason != .manual
		if !captureStartIsCurrent(generation) {
			return
		}
		if !isAutomatic {
			automaticCaptureRetryTask?.cancel()
		}
		do {
			try await PermissionManager.ensureScreenAccess()
			guard captureStartIsCurrent(generation) else { return }
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
			guard captureStartIsCurrent(generation) else { return }

			if mode == .recording {
				try await captureManager.startManualRecording(
					contentFilter: contentFilter,
					resolution: selectedResolution,
					quality: selectedQuality,
					frameRate: selectedFrameRate.framesPerSecond,
					audioCodec: selectedAudioCodec,
					container: selectedContainer,
					recordMicrophoneEnabled: recordMicrophoneEnabled,
					recordDesktopAudioEnabled: recordDesktopAudioEnabled,
					microphoneDeviceID: selectedMicrophoneDeviceID
				)
			} else {
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
			}

			guard captureStartIsCurrent(generation) else {
				if mode == .recording {
					if let recoveredURL = try? await captureManager.stopManualRecording() {
						try? await addRecordedClip(at: recoveredURL)
					}
				} else {
					_ = await captureManager.stop()
				}
				return
			}
			isCapturing = true
			activeRecordingMode = mode
			let settings = analyticsSettingsSnapshot
			Task { await analytics.captureSessionStarted(reason: reason, settings: settings) }
			automaticRestartFailureCount = 0
			updateDiscordActivity(.recording(game: nil, joinURL: nil, artURL: nil))
			if !isAutomatic {
				playRecordingStartFeedback()
			}
			automaticCaptureRetryTask?.cancel()
		} catch {
			guard captureGeneration == generation, !Task.isCancelled else { return }
			isCapturing = false
			activeRecordingMode = nil
			updateDiscordActivity(.idle)
			let category = analyticsErrorCategory(error)
			Task {
				await analytics.captureStartFailed(
					reason: reason,
					category: category,
					retrying: isAutomatic
				)
			}

			if isAutomatic {
				if isDisplayOrSystemAsleep {
					return
				}
				AppLog.error(.app, "Automatic capture start failed", error)
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

	private func captureStartIsCurrent(_ generation: UInt64) -> Bool {
		captureGeneration == generation && !Task.isCancelled && !isDisplayOrSystemAsleep
	}

	private func cancelPendingCaptureStart() {
		guard isStartingCapture else { return }
		captureStartTask?.cancel()
		if #available(macOS 14.0, *), let picker = contentPicker as? ContentSharingPicker {
			picker.cancel()
		}
	}

	private func resumeAlwaysRecordingIfNeeded() {
		guard resumeAlwaysRecordingAfterStop else { return }
		guard !isCapturing, !isCaptureTransitioning, !isDisplayOrSystemAsleep else { return }
		resumeAlwaysRecordingAfterStop = false
		guard selectedRecordingMode == .instantReplay, alwaysRecordEnabled else { return }
		startCapture(reason: .wake)
	}

	private func beginReplayStop(reason: AnalyticsCaptureEndReason) {
		guard activeRecordingMode == .instantReplay, isCapturing, !isStoppingCapture else { return }
		cancelReplayRestart()
		isStoppingCapture = true
		isCapturing = false
		automaticCaptureRetryTask?.cancel()
		automaticCaptureRetryTask = nil
		updateDiscordActivity(.idle)
		captureStopTask = Task { await finishReplayStop(reason: reason) }
	}

	private func finishReplayStop(reason: AnalyticsCaptureEndReason) async {
		_ = await captureManager.stop()
		activeRecordingMode = nil
		Task { await analytics.captureSessionEnded(reason: reason) }
		if reason == .manual {
			playRecordingEndFeedback()
		}
		captureStopTask = nil
		isStoppingCapture = false
		isRestartingCapture = false
		resumeAlwaysRecordingIfNeeded()
	}

	private func beginManualRecordingStop(reason: AnalyticsCaptureEndReason) {
		guard activeRecordingMode == .recording, isCapturing, !isStoppingCapture else { return }
		isStoppingCapture = true
		isCapturing = false
		automaticCaptureRetryTask?.cancel()
		automaticCaptureRetryTask = nil
		updateDiscordActivity(.idle)
		captureStopTask = Task { await finishManualRecording(reason: reason) }
	}

	private func finishManualRecording(reason: AnalyticsCaptureEndReason) async {
		do {
			let url = try await captureManager.stopManualRecording()
			try await addRecordedClip(at: url)
			if reason == .manual {
				playRecordingEndFeedback()
			}
		} catch {
			AppLog.error(.app, "Failed to finish recording:", error)
			playErrorFeedback()
		}

		Task { await analytics.captureSessionEnded(reason: reason) }
		activeRecordingMode = nil
		captureStopTask = nil
		isStoppingCapture = false
	}

	private func addRecordedClip(at url: URL) async throws {
		let clipDuration = try await resolvedClipDuration(for: url)
		let clip = try await clipLibrary.addClip(url: url, duration: clipDuration)
		lastClip = clip
		refreshStorageWarning()
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
		guard isCapturing,
		      activeRecordingMode == .instantReplay,
		      !isStoppingCapture,
		      !isDisplayOrSystemAsleep
		else { return }

		replayRestartGeneration &+= 1
		let generation = replayRestartGeneration
		replayRestartTask?.cancel()
		isRestartingCapture = true
		replayRestartTask = Task {
			await performReplayRestart(generation: generation)
		}
	}

	private func performReplayRestart(generation: UInt64) async {
		defer {
			if replayRestartGeneration == generation {
				replayRestartTask = nil
				isRestartingCapture = false
			}
		}

		_ = await captureManager.stop()
		guard replayRestartGeneration == generation,
		      !Task.isCancelled,
		      isCapturing,
		      activeRecordingMode == .instantReplay,
		      !isDisplayOrSystemAsleep
		else { return }

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
			guard replayRestartGeneration == generation, !Task.isCancelled else { return }
			isCapturing = false
			activeRecordingMode = nil
			updateDiscordActivity(.idle)
			playErrorFeedback()
			AppLog.error(.app, "Silent restart failed:", error)
		}
	}

	private func cancelReplayRestart() {
		guard replayRestartTask != nil || isRestartingCapture else { return }
		replayRestartGeneration &+= 1
		replayRestartTask?.cancel()
		replayRestartTask = nil
		isRestartingCapture = false
	}

	/// Clears `lastClip` if it points at a clip that was just deleted, so
	/// "Open Last Clip" doesn't stay enabled and try to open a missing file.
	func clipWasDeleted(_ clip: Clip) {
		if lastClip?.id == clip.id {
			lastClip = nil
		}
	}

	private func saveReplayAsync() async {
		guard activeRecordingMode == .instantReplay, isCapturing else { return }
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
				seconds: replayDuration, container: selectedContainer
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
		gamePresenceTask?.cancel()
		gamePresenceTask = Task { @MainActor [weak self] in
			while !Task.isCancelled {
				guard let self, self.isCapturing, self.discordRPCEnabled,
				      self.discordActivityState.isRecording else { return }
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

			while !Task.isCancelled {
				guard self.discordRPCEnabled, self.discordActivityState == state else { return }
				let published = await self.discordRPCClient.publish(state: state)
				if published { return }
				try? await Task.sleep(nanoseconds: 2_000_000_000)
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
		var lastError: Error = CaptureError.invalidDuration
		for attempt in 0 ..< 20 {
			do {
				let duration = try await AVURLAsset(url: url).load(.duration)
				let seconds = CMTimeGetSeconds(duration)
				if seconds.isFinite, seconds > 0 {
					return seconds
				}
				lastError = CaptureError.invalidDuration
			} catch {
				lastError = error
			}

			if attempt < 19 {
				try? await Task.sleep(nanoseconds: 250_000_000)
			}
		}
		AppLog.info(.app, "Couldnt read exported clip duration", lastError)
		throw lastError
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
		if selectedRecordingMode == .instantReplay, alwaysRecordEnabled {
			resumeAlwaysRecordingAfterStop = true
		}
		if isStartingCapture {
			cancelPendingCaptureStart()
			return
		}
		if isCapturing {
			if activeRecordingMode == .recording {
				beginManualRecordingStop(reason: .sleep)
			} else {
				beginReplayStop(reason: .sleep)
			}
		}
	}

	func handleWake() {
		if isAsleep {
			AppLog.info(.app, "System waking up")
		}
		isAsleep = false
		guard selectedRecordingMode == .instantReplay, alwaysRecordEnabled else { return }
		resumeAlwaysRecordingAfterStop = true
		resumeAlwaysRecordingIfNeeded()
	}

	private func handleCaptureInterrupted(
		_ error: Error,
		recoveredRecordingURL: URL?
	) {
		// An intentional stop owns finalization and library insertion. A late
		// framework callback must not clear that state or add the same file twice.
		guard !isStoppingCapture else {
			AppLog.info(.app, "Ignoring capture interruption during intentional stop")
			return
		}
		let interruptedMode = activeRecordingMode
			?? (isStartingCapture ? selectedRecordingMode : nil)
		captureGeneration &+= 1
		captureStartTask?.cancel()
		captureStartTask = nil
		cancelReplayRestart()
		isCapturing = false
		isStartingCapture = false
		activeRecordingMode = nil
		updateDiscordActivity(.idle)
		let wasAsleep = isDisplayOrSystemAsleep
		if !wasAsleep, (interruptedMode == .recording || !alwaysRecordEnabled) {
			playErrorFeedback()
		}
		AppLog.error(.app, "Capture interrupted:", error)
		let category = analyticsErrorCategory(error)
		let shouldRetry = interruptedMode == .instantReplay && !wasAsleep

		if let recoveredRecordingURL {
			isStoppingCapture = true
			captureStopTask = Task {
				await finishRecoveredRecording(
					at: recoveredRecordingURL,
					analyticsCategory: category
				)
			}
		} else {
			Task {
				await analytics.captureInterrupted(category: category, retrying: shouldRetry)
				await analytics.captureSessionEnded(reason: .interrupted)
			}
		}

		if shouldRetry {
			scheduleCaptureRetry()
		}
	}

	private func finishRecoveredRecording(
		at url: URL,
		analyticsCategory: String
	) async {
		do {
			try await addRecordedClip(at: url)
		} catch {
			AppLog.error(.app, "Failed to add recovered recording:", error)
		}
		await analytics.captureInterrupted(category: analyticsCategory, retrying: false)
		await analytics.captureSessionEnded(reason: .interrupted)
		captureStopTask = nil
		isStoppingCapture = false
	}

	private func scheduleCaptureRetry() {
		guard selectedRecordingMode == .instantReplay else { return }
		automaticCaptureRetryTask?.cancel()
		automaticCaptureRetryTask = Task { @MainActor [weak self] in
			guard let self else { return }
			try? await Task.sleep(nanoseconds: 2_000_000_000)
			if Task.isCancelled { return }
			if self.isDisplayOrSystemAsleep {
				return
			}
			if self.selectedRecordingMode == .instantReplay,
			   !self.isCapturing,
			   !self.isCaptureTransitioning
			{
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
			startRecording: startRecordingHotkey,
			stopRecording: stopRecordingHotkey
		)
	}

	private func rejectHotkeyChange(message: String, revert: () -> Void) {
		isRestoringSettings = true
		revert()
		isRestoringSettings = false
		hotkeyConflictMessage = message
	}

	private func persistSettings() {
		AppSettingsStorage.save(
			AppSettings(
				replayDuration: replayDuration,
				resolutionID: preferredResolutionID,
				qualityID: selectedQuality.id,
				frameRate: selectedFrameRate.framesPerSecond,
				containerID: selectedContainer.id,
				audioCodecID: selectedAudioCodec.id,
				recordingModeID: selectedRecordingMode.id,
				hotkey: hotkey,
				startRecordingHotkey: startRecordingHotkey,
				stopRecordingHotkey: stopRecordingHotkey,
				alwaysRecordEnabled: alwaysRecordEnabled,
				saveFeedbackEnabled: saveFeedbackEnabled,
				saveFeedbackVolume: saveFeedbackVolume,
				saveFeedbackSoundID: saveFeedbackSound.id,
				recordingStartFeedbackEnabled: recordingStartFeedbackEnabled,
				recordingStartFeedbackVolume: recordingStartFeedbackVolume,
				recordingStartFeedbackSoundID: recordingStartFeedbackSound.id,
				recordingEndFeedbackEnabled: recordingEndFeedbackEnabled,
				recordingEndFeedbackVolume: recordingEndFeedbackVolume,
				recordingEndFeedbackSoundID: recordingEndFeedbackSound.id,
				errorFeedbackEnabled: errorFeedbackEnabled,
				errorFeedbackVolume: errorFeedbackVolume,
				errorFeedbackSoundID: errorFeedbackSound.id,
				discordRPCEnabled: discordRPCEnabled,
				shareGamePresenceEnabled: shareGamePresenceEnabled,
				shareRobloxExperienceEnabled: shareRobloxExperienceEnabled,
				fileLoggingEnabled: fileLoggingEnabled,
				analyticsEnabled: analyticsEnabled,

				betaUpdatesEnabled: betaUpdatesEnabled,
				enabledUploadProviderIDs: enabledUploadProviderIDs,
				recordMicrophoneEnabled: recordMicrophoneEnabled,
				recordDesktopAudioEnabled: recordDesktopAudioEnabled,
				captureTargetPromptEnabled: captureTargetPromptEnabled,
				microphoneDeviceID: selectedMicrophoneDeviceID,
				outputDirectoryPath: outputDirectoryPath
			)
		)
		let settings = analyticsSettingsSnapshot
		Task { await analytics.settingsUpdated(settings) }
	}

	private func refreshStorageWarning() {
		storageMonitor.refresh()
	}
}
