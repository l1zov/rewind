import Defaults
import Foundation

struct AppSettings: Codable {
	static let replayDurationRange: ClosedRange<TimeInterval> = 10 ... 300
	static let replayDurationStep: TimeInterval = 5
	static let replayDurationQuickOptions = [15, 30, 45, 60, 90, 120, 180, 240, 300]
	static let saveFeedbackVolumeRange: ClosedRange<Double> = 1 ... 100
	static let saveFeedbackVolumeStep: Double = 1

	var replayDuration: TimeInterval
	var resolutionID: String?
	var qualityID: String
	var frameRate: Int
	var containerID: String
	var audioCodecID: String
	var hotkey: Hotkey
	var startRecordingHotkey: Hotkey
	var alwaysRecordEnabled: Bool
	var saveFeedbackEnabled: Bool
	var saveFeedbackVolume: Double
	var saveFeedbackSoundID: String
	var recordingStartFeedbackEnabled: Bool
	var recordingStartFeedbackVolume: Double
	var recordingStartFeedbackSoundID: String
	var recordingEndFeedbackEnabled: Bool
	var recordingEndFeedbackVolume: Double
	var recordingEndFeedbackSoundID: String
	var errorFeedbackEnabled: Bool
	var errorFeedbackVolume: Double
	var errorFeedbackSoundID: String
	var discordRPCEnabled: Bool
	var shareGamePresenceEnabled: Bool
	var shareRobloxExperienceEnabled: Bool
	var fileLoggingEnabled: Bool
	var analyticsEnabled: Bool

	var betaUpdatesEnabled: Bool
	/// IDs from `ClipUploadProvider.providers`, in the order the user enabled them.
	var enabledUploadProviderIDs: [String]
	var recordMicrophoneEnabled: Bool
	var recordDesktopAudioEnabled: Bool
	var captureTargetPromptEnabled: Bool
	var microphoneDeviceID: String?
	var outputDirectoryPath: String?
	/// 0...1 mix level of desktop audio in saved clips.
	var desktopAudioVolume: Double
	/// 0...1 mix level of the microphone in saved clips.
	var microphoneVolume: Double

	static let audioVolumeRange: ClosedRange<Double> = 0 ... 1

	static let `default` = AppSettings(
		replayDuration: 30,
		resolutionID: nil,
		qualityID: QualityPreset.default.id,
		frameRate: CaptureFrameRate.default.framesPerSecond,
		containerID: CaptureContainer.default.id,
		audioCodecID: CaptureAudioCodec.default.id,
		hotkey: .default,
		startRecordingHotkey: .startRecordingDefault,
		alwaysRecordEnabled: false,
		saveFeedbackEnabled: true,
		saveFeedbackVolume: 20,
		saveFeedbackSoundID: FeedbackSound.default.id,
		recordingStartFeedbackEnabled: true,
		recordingStartFeedbackVolume: 20,
		recordingStartFeedbackSoundID: FeedbackSound.defaultStart.id,
		recordingEndFeedbackEnabled: true,
		recordingEndFeedbackVolume: 20,
		recordingEndFeedbackSoundID: FeedbackSound.defaultEnd.id,
		errorFeedbackEnabled: true,
		errorFeedbackVolume: 20,
		errorFeedbackSoundID: FeedbackSound.defaultError.id,
		discordRPCEnabled: true,
		shareGamePresenceEnabled: true,
		shareRobloxExperienceEnabled: true,
		fileLoggingEnabled: false,
		analyticsEnabled: true,

		betaUpdatesEnabled: false,
		enabledUploadProviderIDs: [],
		recordMicrophoneEnabled: false,
		recordDesktopAudioEnabled: true,
		captureTargetPromptEnabled: true,
		microphoneDeviceID: nil,
		outputDirectoryPath: nil,
		desktopAudioVolume: 1,
		microphoneVolume: 1
	)

	private enum CodingKeys: String, CodingKey {
		case replayDuration
		case resolutionID
		case qualityID
		case frameRate
		case containerID
		case audioCodecID
		case hotkey
		case startRecordingHotkey
		case alwaysRecordEnabled = "autoRecordEnabled"
		case saveFeedbackEnabled
		case saveFeedbackVolume
		case saveFeedbackSoundID
		case recordingStartFeedbackEnabled
		case recordingStartFeedbackVolume
		case recordingStartFeedbackSoundID
		case recordingEndFeedbackEnabled
		case recordingEndFeedbackVolume
		case recordingEndFeedbackSoundID
		case errorFeedbackEnabled
		case errorFeedbackVolume
		case errorFeedbackSoundID
		case discordRPCEnabled
		case shareGamePresenceEnabled
		case shareRobloxExperienceEnabled
		case fileLoggingEnabled
		case analyticsEnabled

		case betaUpdatesEnabled
		case enabledUploadProviderIDs
		/// Superseded by `enabledUploadProviderIDs`; still read so existing
		/// installs keep the hosts they had switched on.
		case catboxEnabled
		case litterboxEnabled
		case recordMicrophoneEnabled
		case recordDesktopAudioEnabled
		case captureTargetPromptEnabled
		case microphoneDeviceID
		case outputDirectoryPath
		case desktopAudioVolume
		case microphoneVolume
	}

	init(
		replayDuration: TimeInterval = AppSettings.default.replayDuration,
		resolutionID: String? = AppSettings.default.resolutionID,
		qualityID: String = AppSettings.default.qualityID,
		frameRate: Int = AppSettings.default.frameRate,
		containerID: String = AppSettings.default.containerID,
		audioCodecID: String = AppSettings.default.audioCodecID,
		hotkey: Hotkey = AppSettings.default.hotkey,
		startRecordingHotkey: Hotkey = AppSettings.default.startRecordingHotkey,
		alwaysRecordEnabled: Bool = AppSettings.default.alwaysRecordEnabled,
		saveFeedbackEnabled: Bool = AppSettings.default.saveFeedbackEnabled,
		saveFeedbackVolume: Double = AppSettings.default.saveFeedbackVolume,
		saveFeedbackSoundID: String = AppSettings.default.saveFeedbackSoundID,
		recordingStartFeedbackEnabled: Bool = AppSettings.default.recordingStartFeedbackEnabled,
		recordingStartFeedbackVolume: Double = AppSettings.default.recordingStartFeedbackVolume,
		recordingStartFeedbackSoundID: String = AppSettings.default.recordingStartFeedbackSoundID,
		recordingEndFeedbackEnabled: Bool = AppSettings.default.recordingEndFeedbackEnabled,
		recordingEndFeedbackVolume: Double = AppSettings.default.recordingEndFeedbackVolume,
		recordingEndFeedbackSoundID: String = AppSettings.default.recordingEndFeedbackSoundID,
		errorFeedbackEnabled: Bool = AppSettings.default.errorFeedbackEnabled,
		errorFeedbackVolume: Double = AppSettings.default.errorFeedbackVolume,
		errorFeedbackSoundID: String = AppSettings.default.errorFeedbackSoundID,
		discordRPCEnabled: Bool = AppSettings.default.discordRPCEnabled,
		shareGamePresenceEnabled: Bool = AppSettings.default.shareGamePresenceEnabled,
		shareRobloxExperienceEnabled: Bool = AppSettings.default.shareRobloxExperienceEnabled,
		fileLoggingEnabled: Bool = AppSettings.default.fileLoggingEnabled,
		analyticsEnabled: Bool = AppSettings.default.analyticsEnabled,
		betaUpdatesEnabled: Bool = AppSettings.default.betaUpdatesEnabled,
		enabledUploadProviderIDs: [String] = AppSettings.default.enabledUploadProviderIDs,
		recordMicrophoneEnabled: Bool = AppSettings.default.recordMicrophoneEnabled,
		recordDesktopAudioEnabled: Bool = AppSettings.default.recordDesktopAudioEnabled,
		captureTargetPromptEnabled: Bool = AppSettings.default.captureTargetPromptEnabled,
		microphoneDeviceID: String? = AppSettings.default.microphoneDeviceID,
		outputDirectoryPath: String? = AppSettings.default.outputDirectoryPath,
		desktopAudioVolume: Double = AppSettings.default.desktopAudioVolume,
		microphoneVolume: Double = AppSettings.default.microphoneVolume
	) {
		self.replayDuration = replayDuration
		self.resolutionID = resolutionID
		self.qualityID = qualityID
		self.frameRate = frameRate
		self.containerID = containerID
		self.audioCodecID = audioCodecID
		self.hotkey = hotkey
		self.startRecordingHotkey = startRecordingHotkey
		self.alwaysRecordEnabled = alwaysRecordEnabled
		self.saveFeedbackEnabled = saveFeedbackEnabled
		self.saveFeedbackVolume = saveFeedbackVolume
		self.saveFeedbackSoundID = saveFeedbackSoundID
		self.recordingStartFeedbackEnabled = recordingStartFeedbackEnabled
		self.recordingStartFeedbackVolume = recordingStartFeedbackVolume
		self.recordingStartFeedbackSoundID = recordingStartFeedbackSoundID
		self.recordingEndFeedbackEnabled = recordingEndFeedbackEnabled
		self.recordingEndFeedbackVolume = recordingEndFeedbackVolume
		self.recordingEndFeedbackSoundID = recordingEndFeedbackSoundID
		self.errorFeedbackEnabled = errorFeedbackEnabled
		self.errorFeedbackVolume = errorFeedbackVolume
		self.errorFeedbackSoundID = errorFeedbackSoundID
		self.discordRPCEnabled = discordRPCEnabled
		self.shareGamePresenceEnabled = shareGamePresenceEnabled
		self.shareRobloxExperienceEnabled = shareRobloxExperienceEnabled
		self.fileLoggingEnabled = fileLoggingEnabled
		self.analyticsEnabled = analyticsEnabled

		self.betaUpdatesEnabled = betaUpdatesEnabled
		self.enabledUploadProviderIDs = enabledUploadProviderIDs
		self.recordMicrophoneEnabled = recordMicrophoneEnabled
		self.recordDesktopAudioEnabled = recordDesktopAudioEnabled
		self.captureTargetPromptEnabled = captureTargetPromptEnabled
		self.microphoneDeviceID = microphoneDeviceID
		self.outputDirectoryPath = outputDirectoryPath
		self.desktopAudioVolume = desktopAudioVolume
		self.microphoneVolume = microphoneVolume
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		replayDuration = try container.decode(TimeInterval.self, forKey: .replayDuration)
		resolutionID = try container.decodeIfPresent(String.self, forKey: .resolutionID)
		qualityID = try container.decodeIfPresent(String.self, forKey: .qualityID) ?? QualityPreset.default.id
		frameRate = try container.decodeIfPresent(Int.self, forKey: .frameRate) ?? CaptureFrameRate.default.framesPerSecond
		containerID = try container.decodeIfPresent(String.self, forKey: .containerID) ?? CaptureContainer.default.id
		audioCodecID = try container.decodeIfPresent(String.self, forKey: .audioCodecID) ?? CaptureAudioCodec.default.id
		hotkey = try container.decode(Hotkey.self, forKey: .hotkey)
		startRecordingHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .startRecordingHotkey)
			?? .startRecordingDefault
		alwaysRecordEnabled = try container.decodeIfPresent(Bool.self, forKey: .alwaysRecordEnabled) ?? false
		saveFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .saveFeedbackEnabled) ?? true
		saveFeedbackVolume = try container.decodeIfPresent(Double.self, forKey: .saveFeedbackVolume)
			?? AppSettings.default.saveFeedbackVolume
		saveFeedbackSoundID = try container.decodeIfPresent(String.self, forKey: .saveFeedbackSoundID)
			?? FeedbackSound.default.id
		recordingStartFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordingStartFeedbackEnabled) ?? true
		recordingStartFeedbackVolume = try container.decodeIfPresent(Double.self, forKey: .recordingStartFeedbackVolume)
			?? AppSettings.default.recordingStartFeedbackVolume
		recordingStartFeedbackSoundID = try container.decodeIfPresent(String.self, forKey: .recordingStartFeedbackSoundID)
			?? FeedbackSound.defaultStart.id
		recordingEndFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordingEndFeedbackEnabled) ?? true
		recordingEndFeedbackVolume = try container.decodeIfPresent(Double.self, forKey: .recordingEndFeedbackVolume)
			?? AppSettings.default.recordingEndFeedbackVolume
		recordingEndFeedbackSoundID = try container.decodeIfPresent(String.self, forKey: .recordingEndFeedbackSoundID)
			?? FeedbackSound.defaultEnd.id
		errorFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .errorFeedbackEnabled) ?? true
		errorFeedbackVolume = try container.decodeIfPresent(Double.self, forKey: .errorFeedbackVolume)
			?? AppSettings.default.errorFeedbackVolume
		errorFeedbackSoundID = try container.decodeIfPresent(String.self, forKey: .errorFeedbackSoundID)
			?? FeedbackSound.defaultError.id
		discordRPCEnabled = try container.decodeIfPresent(Bool.self, forKey: .discordRPCEnabled) ?? true
		shareGamePresenceEnabled = try container.decodeIfPresent(Bool.self, forKey: .shareGamePresenceEnabled) ?? true
		shareRobloxExperienceEnabled = try container.decodeIfPresent(Bool.self, forKey: .shareRobloxExperienceEnabled) ?? true
		fileLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .fileLoggingEnabled) ?? false
		analyticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .analyticsEnabled) ?? true

		betaUpdatesEnabled = try container.decodeIfPresent(Bool.self, forKey: .betaUpdatesEnabled) ?? false
		if let storedProviderIDs = try container.decodeIfPresent(
			[String].self, forKey: .enabledUploadProviderIDs
		) {
			// Unknown IDs are kept rather than dropped so downgrading and then
			// upgrading again doesn't silently switch a host back off.
			enabledUploadProviderIDs = storedProviderIDs.reduce(into: [String]()) { unique, id in
				if !unique.contains(id) { unique.append(id) }
			}
		} else {
			var migrated: [String] = []
			if try container.decodeIfPresent(Bool.self, forKey: .catboxEnabled) ?? false {
				migrated.append(ClipUploadProvider.catboxID)
			}
			if try container.decodeIfPresent(Bool.self, forKey: .litterboxEnabled) ?? false {
				migrated.append(ClipUploadProvider.litterboxID)
			}
			enabledUploadProviderIDs = migrated
		}
		recordMicrophoneEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordMicrophoneEnabled) ?? false
		recordDesktopAudioEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordDesktopAudioEnabled) ?? true
		captureTargetPromptEnabled = try container.decodeIfPresent(Bool.self, forKey: .captureTargetPromptEnabled) ?? true
		microphoneDeviceID = try container.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
		outputDirectoryPath = try container.decodeIfPresent(String.self, forKey: .outputDirectoryPath)
		desktopAudioVolume = try container.decodeIfPresent(Double.self, forKey: .desktopAudioVolume) ?? 1
		microphoneVolume = try container.decodeIfPresent(Double.self, forKey: .microphoneVolume) ?? 1
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(replayDuration, forKey: .replayDuration)
		try container.encodeIfPresent(resolutionID, forKey: .resolutionID)

		let qualityToStore: String? = qualityID == QualityPreset.default.id ? nil : qualityID
		try container.encodeIfPresent(qualityToStore, forKey: .qualityID)
		let frameRateToStore: Int? = frameRate == CaptureFrameRate.default.framesPerSecond ? nil : frameRate
		try container.encodeIfPresent(frameRateToStore, forKey: .frameRate)
		let containerToStore: String? = containerID == CaptureContainer.default.id ? nil : containerID
		try container.encodeIfPresent(containerToStore, forKey: .containerID)
		let audioCodecToStore: String? = audioCodecID == CaptureAudioCodec.default.id ? nil : audioCodecID
		try container.encodeIfPresent(audioCodecToStore, forKey: .audioCodecID)

		try container.encode(hotkey, forKey: .hotkey)
		try container.encode(startRecordingHotkey, forKey: .startRecordingHotkey)
		try container.encode(alwaysRecordEnabled, forKey: .alwaysRecordEnabled)
		try container.encode(saveFeedbackEnabled, forKey: .saveFeedbackEnabled)
		try container.encode(saveFeedbackVolume, forKey: .saveFeedbackVolume)
		try container.encode(saveFeedbackSoundID, forKey: .saveFeedbackSoundID)
		try container.encode(recordingStartFeedbackEnabled, forKey: .recordingStartFeedbackEnabled)
		try container.encode(recordingStartFeedbackVolume, forKey: .recordingStartFeedbackVolume)
		try container.encode(recordingStartFeedbackSoundID, forKey: .recordingStartFeedbackSoundID)
		try container.encode(recordingEndFeedbackEnabled, forKey: .recordingEndFeedbackEnabled)
		try container.encode(recordingEndFeedbackVolume, forKey: .recordingEndFeedbackVolume)
		try container.encode(recordingEndFeedbackSoundID, forKey: .recordingEndFeedbackSoundID)
		try container.encode(errorFeedbackEnabled, forKey: .errorFeedbackEnabled)
		try container.encode(errorFeedbackVolume, forKey: .errorFeedbackVolume)
		try container.encode(errorFeedbackSoundID, forKey: .errorFeedbackSoundID)
		try container.encode(discordRPCEnabled, forKey: .discordRPCEnabled)
		try container.encode(shareGamePresenceEnabled, forKey: .shareGamePresenceEnabled)
		try container.encode(shareRobloxExperienceEnabled, forKey: .shareRobloxExperienceEnabled)
		try container.encode(fileLoggingEnabled, forKey: .fileLoggingEnabled)
		try container.encode(analyticsEnabled, forKey: .analyticsEnabled)

		try container.encode(betaUpdatesEnabled, forKey: .betaUpdatesEnabled)
		try container.encode(enabledUploadProviderIDs, forKey: .enabledUploadProviderIDs)
		try container.encode(recordMicrophoneEnabled, forKey: .recordMicrophoneEnabled)
		try container.encode(recordDesktopAudioEnabled, forKey: .recordDesktopAudioEnabled)
		try container.encode(captureTargetPromptEnabled, forKey: .captureTargetPromptEnabled)
		try container.encodeIfPresent(microphoneDeviceID, forKey: .microphoneDeviceID)
		try container.encodeIfPresent(outputDirectoryPath, forKey: .outputDirectoryPath)
		try container.encode(desktopAudioVolume, forKey: .desktopAudioVolume)
		try container.encode(microphoneVolume, forKey: .microphoneVolume)
	}

	var qualityPreset: QualityPreset {
		QualityPreset.presets.first(where: { $0.id == qualityID }) ?? .default
	}

	var frameRateOption: CaptureFrameRate {
		CaptureFrameRate.options.first(where: { $0.framesPerSecond == frameRate }) ?? .default
	}

	var container: CaptureContainer {
		CaptureContainer.options.first(where: { $0.id == containerID }) ?? .default
	}

	var audioCodec: CaptureAudioCodec {
		CaptureAudioCodec.options.first(where: { $0.id == audioCodecID }) ?? .default
	}

	var saveFeedbackSound: FeedbackSound {
		FeedbackSound.options.first(where: { $0.id == saveFeedbackSoundID }) ?? .default
	}

	var recordingStartFeedbackSound: FeedbackSound {
		FeedbackSound.options.first(where: { $0.id == recordingStartFeedbackSoundID }) ?? .defaultStart
	}

	var recordingEndFeedbackSound: FeedbackSound {
		FeedbackSound.options.first(where: { $0.id == recordingEndFeedbackSoundID }) ?? .defaultEnd
	}

	var errorFeedbackSound: FeedbackSound {
		FeedbackSound.options.first(where: { $0.id == errorFeedbackSoundID }) ?? .defaultError
	}
}

enum AppSettingsStorage {
	private static let key = "settings.app.v1"

	static func load() -> AppSettings {
		if let data = UserDefaults.standard.data(forKey: key),
		   let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
		{
			// A value that no longer exists (e.g. a sound or preset removed in an
			// update) resets just that field, not the user's whole configuration.
			let repaired = sanitized(decoded)
			if let normalized = try? JSONEncoder().encode(repaired), normalized != data {
				UserDefaults.standard.set(normalized, forKey: key)
			}
			return repaired
		}

		if UserDefaults.standard.object(forKey: key) != nil {
			UserDefaults.standard.removeObject(forKey: key)
		}

		return .default
	}

	static func save(_ settings: AppSettings) {
		let s = sanitized(settings)
		Defaults[.replayDuration] = s.replayDuration
		Defaults[.resolutionID] = s.resolutionID
		Defaults[.qualityID] = s.qualityID
		Defaults[.frameRate] = s.frameRate
		Defaults[.containerID] = s.containerID
		Defaults[.audioCodecID] = s.audioCodecID
		Defaults[.hotkey] = s.hotkey
		Defaults[.startRecordingHotkey] = s.startRecordingHotkey
		Defaults[.alwaysRecordEnabled] = s.alwaysRecordEnabled
		Defaults[.saveFeedbackEnabled] = s.saveFeedbackEnabled
		Defaults[.saveFeedbackVolume] = s.saveFeedbackVolume
		Defaults[.saveFeedbackSoundID] = s.saveFeedbackSoundID
		Defaults[.recordingStartFeedbackEnabled] = s.recordingStartFeedbackEnabled
		Defaults[.recordingStartFeedbackVolume] = s.recordingStartFeedbackVolume
		Defaults[.recordingStartFeedbackSoundID] = s.recordingStartFeedbackSoundID
		Defaults[.recordingEndFeedbackEnabled] = s.recordingEndFeedbackEnabled
		Defaults[.recordingEndFeedbackVolume] = s.recordingEndFeedbackVolume
		Defaults[.recordingEndFeedbackSoundID] = s.recordingEndFeedbackSoundID
		Defaults[.errorFeedbackEnabled] = s.errorFeedbackEnabled
		Defaults[.errorFeedbackVolume] = s.errorFeedbackVolume
		Defaults[.errorFeedbackSoundID] = s.errorFeedbackSoundID
		Defaults[.discordRPCEnabled] = s.discordRPCEnabled
		Defaults[.shareGamePresenceEnabled] = s.shareGamePresenceEnabled
		Defaults[.shareRobloxExperienceEnabled] = s.shareRobloxExperienceEnabled
		Defaults[.fileLoggingEnabled] = s.fileLoggingEnabled
		Defaults[.analyticsEnabled] = s.analyticsEnabled
		Defaults[.betaUpdatesEnabled] = s.betaUpdatesEnabled
		Defaults[.enabledUploadProviderIDs] = s.enabledUploadProviderIDs
		Defaults[.recordMicrophoneEnabled] = s.recordMicrophoneEnabled
		Defaults[.recordDesktopAudioEnabled] = s.recordDesktopAudioEnabled
		Defaults[.captureTargetPromptEnabled] = s.captureTargetPromptEnabled
		Defaults[.microphoneDeviceID] = s.microphoneDeviceID
		Defaults[.outputDirectoryPath] = s.outputDirectoryPath
		Defaults[.desktopAudioVolume] = s.desktopAudioVolume
		Defaults[.microphoneVolume] = s.microphoneVolume

		guard let data = try? JSONEncoder().encode(s) else {
			UserDefaults.standard.removeObject(forKey: key)
			return
		}
		UserDefaults.standard.set(data, forKey: key)
	}

	/// Replaces each out-of-range or unknown field with its default and leaves
	/// every other field untouched.
	static func sanitized(_ settings: AppSettings) -> AppSettings {
		let defaults = AppSettings.default
		var s = settings
		if !AppSettings.replayDurationRange.contains(s.replayDuration) { s.replayDuration = defaults.replayDuration }
		if !QualityPreset.presets.contains(where: { $0.id == s.qualityID }) { s.qualityID = defaults.qualityID }
		if !CaptureFrameRate.options.contains(where: { $0.framesPerSecond == s.frameRate }) { s.frameRate = defaults.frameRate }
		if !CaptureContainer.options.contains(where: { $0.id == s.containerID }) { s.containerID = defaults.containerID }
		if !CaptureAudioCodec.options.contains(where: { $0.id == s.audioCodecID }) { s.audioCodecID = defaults.audioCodecID }
		if !AppSettings.saveFeedbackVolumeRange.contains(s.saveFeedbackVolume) { s.saveFeedbackVolume = defaults.saveFeedbackVolume }
		if !FeedbackSound.options.contains(where: { $0.id == s.saveFeedbackSoundID }) { s.saveFeedbackSoundID = defaults.saveFeedbackSoundID }
		if !AppSettings.saveFeedbackVolumeRange.contains(s.recordingStartFeedbackVolume) {
			s.recordingStartFeedbackVolume = defaults.recordingStartFeedbackVolume
		}
		if !FeedbackSound.options.contains(where: { $0.id == s.recordingStartFeedbackSoundID }) {
			s.recordingStartFeedbackSoundID = defaults.recordingStartFeedbackSoundID
		}
		if !AppSettings.saveFeedbackVolumeRange.contains(s.recordingEndFeedbackVolume) {
			s.recordingEndFeedbackVolume = defaults.recordingEndFeedbackVolume
		}
		if !FeedbackSound.options.contains(where: { $0.id == s.recordingEndFeedbackSoundID }) {
			s.recordingEndFeedbackSoundID = defaults.recordingEndFeedbackSoundID
		}
		if !AppSettings.saveFeedbackVolumeRange.contains(s.errorFeedbackVolume) { s.errorFeedbackVolume = defaults.errorFeedbackVolume }
		if !FeedbackSound.options.contains(where: { $0.id == s.errorFeedbackSoundID }) {
			s.errorFeedbackSoundID = defaults.errorFeedbackSoundID
		}
		if !AppSettings.audioVolumeRange.contains(s.desktopAudioVolume) { s.desktopAudioVolume = defaults.desktopAudioVolume }
		if !AppSettings.audioVolumeRange.contains(s.microphoneVolume) { s.microphoneVolume = defaults.microphoneVolume }
		return s
	}
}
