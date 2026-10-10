import Defaults
import Foundation

extension Hotkey: Defaults.Serializable {}

extension Defaults.Keys {
	// - Constants ---
	static let replayDurationRange: ClosedRange<TimeInterval> = 10 ... 300
	static let replayDurationStep: TimeInterval = 5
	static let replayDurationQuickOptions = [15, 30, 45, 60, 90, 120, 180, 240, 300]
	static let saveFeedbackVolumeRange: ClosedRange<Double> = 1 ... 100
	static let saveFeedbackVolumeStep: Double = 1
	static let audioVolumeRange: ClosedRange<Double> = 0 ... 1

	// - General ---
	static let betaUpdatesEnabled = Key<Bool>("betaUpdatesEnabled", default: false)
	static let analyticsEnabled = Key<Bool>("analyticsEnabled", default: true)
	static let outputDirectoryPath = Key<String?>("outputDirectoryPath", default: nil)

	// - Capture ---
	static let replayDuration = Key<TimeInterval>("replayDuration", default: 30)
	static let resolutionID = Key<String?>("resolutionID", default: nil)
	static let qualityID = Key<String>("qualityID", default: QualityPreset.default.id)
	static let frameRate = Key<Int>("frameRate", default: CaptureFrameRate.default.framesPerSecond)
	static let containerID = Key<String>("containerID", default: CaptureContainer.default.id)
	static let audioCodecID = Key<String>("audioCodecID", default: CaptureAudioCodec.default.id)
	static let alwaysRecordEnabled = Key<Bool>("alwaysRecordEnabled", default: false)
	static let captureTargetPromptEnabled = Key<Bool>("captureTargetPromptEnabled", default: true)

	// - Audio ---
	static let recordMicrophoneEnabled = Key<Bool>("recordMicrophoneEnabled", default: false)
	static let recordDesktopAudioEnabled = Key<Bool>("recordDesktopAudioEnabled", default: true)
	static let microphoneDeviceID = Key<String?>("microphoneDeviceID", default: nil)
	static let desktopAudioVolume = Key<Double>("desktopAudioVolume", default: 1)
	static let microphoneVolume = Key<Double>("microphoneVolume", default: 1)

	// - Hotkeys ---
	static let hotkey = Key<Hotkey>("hotkey", default: .default)
	static let startRecordingHotkey = Key<Hotkey>("startRecordingHotkey", default: .startRecordingDefault)

	// - Feedback ---
	static let saveFeedbackEnabled = Key<Bool>("saveFeedbackEnabled", default: true)
	static let saveFeedbackVolume = Key<Double>("saveFeedbackVolume", default: 20)
	static let saveFeedbackSoundID = Key<String>("saveFeedbackSoundID", default: FeedbackSound.default.id)
	static let recordingStartFeedbackEnabled = Key<Bool>("recordingStartFeedbackEnabled", default: true)
	static let recordingStartFeedbackVolume = Key<Double>("recordingStartFeedbackVolume", default: 20)
	static let recordingStartFeedbackSoundID = Key<String>("recordingStartFeedbackSoundID", default: FeedbackSound.defaultStart.id)
	static let recordingEndFeedbackEnabled = Key<Bool>("recordingEndFeedbackEnabled", default: true)
	static let recordingEndFeedbackVolume = Key<Double>("recordingEndFeedbackVolume", default: 20)
	static let recordingEndFeedbackSoundID = Key<String>("recordingEndFeedbackSoundID", default: FeedbackSound.defaultEnd.id)
	static let errorFeedbackEnabled = Key<Bool>("errorFeedbackEnabled", default: true)
	static let errorFeedbackVolume = Key<Double>("errorFeedbackVolume", default: 20)
	static let errorFeedbackSoundID = Key<String>("errorFeedbackSoundID", default: FeedbackSound.defaultError.id)

	// - Integrations ---
	static let discordRPCEnabled = Key<Bool>("discordRPCEnabled", default: true)
	static let shareGamePresenceEnabled = Key<Bool>("shareGamePresenceEnabled", default: true)
	static let shareRobloxExperienceEnabled = Key<Bool>("shareRobloxExperienceEnabled", default: true)
	static let fileLoggingEnabled = Key<Bool>("fileLoggingEnabled", default: false)
	static let enabledUploadProviderIDs = Key<[String]>("enabledUploadProviderIDs", default: [])
}

enum DefaultsMigration {
	private static let legacySettingsKey = "settings.app.v1"

	static func migrateLegacySettingsIfNeeded(userDefaults: UserDefaults = .standard) {
		guard let data = userDefaults.data(forKey: legacySettingsKey),
		      let legacy = try? JSONDecoder().decode(AppSettings.self, from: data)
		else {
			return
		}

		let s = AppSettingsStorage.sanitized(legacy)

		userDefaults[.replayDuration] = s.replayDuration
		userDefaults[.resolutionID] = s.resolutionID
		userDefaults[.qualityID] = s.qualityID
		userDefaults[.frameRate] = s.frameRate
		userDefaults[.containerID] = s.containerID
		userDefaults[.audioCodecID] = s.audioCodecID
		userDefaults[.hotkey] = s.hotkey
		userDefaults[.startRecordingHotkey] = s.startRecordingHotkey
		userDefaults[.alwaysRecordEnabled] = s.alwaysRecordEnabled
		userDefaults[.saveFeedbackEnabled] = s.saveFeedbackEnabled
		userDefaults[.saveFeedbackVolume] = s.saveFeedbackVolume
		userDefaults[.saveFeedbackSoundID] = s.saveFeedbackSoundID
		userDefaults[.recordingStartFeedbackEnabled] = s.recordingStartFeedbackEnabled
		userDefaults[.recordingStartFeedbackVolume] = s.recordingStartFeedbackVolume
		userDefaults[.recordingStartFeedbackSoundID] = s.recordingStartFeedbackSoundID
		userDefaults[.recordingEndFeedbackEnabled] = s.recordingEndFeedbackEnabled
		userDefaults[.recordingEndFeedbackVolume] = s.recordingEndFeedbackVolume
		userDefaults[.recordingEndFeedbackSoundID] = s.recordingEndFeedbackSoundID
		userDefaults[.errorFeedbackEnabled] = s.errorFeedbackEnabled
		userDefaults[.errorFeedbackVolume] = s.errorFeedbackVolume
		userDefaults[.errorFeedbackSoundID] = s.errorFeedbackSoundID
		userDefaults[.discordRPCEnabled] = s.discordRPCEnabled
		userDefaults[.shareGamePresenceEnabled] = s.shareGamePresenceEnabled
		userDefaults[.shareRobloxExperienceEnabled] = s.shareRobloxExperienceEnabled
		userDefaults[.fileLoggingEnabled] = s.fileLoggingEnabled
		userDefaults[.analyticsEnabled] = s.analyticsEnabled
		userDefaults[.betaUpdatesEnabled] = s.betaUpdatesEnabled
		userDefaults[.enabledUploadProviderIDs] = s.enabledUploadProviderIDs
		userDefaults[.recordMicrophoneEnabled] = s.recordMicrophoneEnabled
		userDefaults[.recordDesktopAudioEnabled] = s.recordDesktopAudioEnabled
		userDefaults[.captureTargetPromptEnabled] = s.captureTargetPromptEnabled
		userDefaults[.microphoneDeviceID] = s.microphoneDeviceID
		userDefaults[.outputDirectoryPath] = s.outputDirectoryPath
		userDefaults[.desktopAudioVolume] = s.desktopAudioVolume
		userDefaults[.microphoneVolume] = s.microphoneVolume

		userDefaults.removeObject(forKey: legacySettingsKey)
	}
}
