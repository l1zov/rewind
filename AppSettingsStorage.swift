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
	var recordingModeID: String
	var hotkey: Hotkey
	var startRecordingHotkey: Hotkey
	var stopRecordingHotkey: Hotkey
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

	static let `default` = AppSettings(
		replayDuration: 30,
		resolutionID: nil,
		qualityID: QualityPreset.default.id,
		frameRate: CaptureFrameRate.default.framesPerSecond,
		containerID: CaptureContainer.default.id,
		audioCodecID: CaptureAudioCodec.default.id,
		recordingModeID: RecordingMode.default.id,
		hotkey: .default,
		startRecordingHotkey: .startRecordingDefault,
		stopRecordingHotkey: .stopRecordingDefault,
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
		outputDirectoryPath: nil
	)

	private enum CodingKeys: String, CodingKey {
		case replayDuration
		case resolutionID
		case qualityID
		case frameRate
		case containerID
		case audioCodecID
		case recordingModeID
		case hotkey
		case startRecordingHotkey
		case stopRecordingHotkey
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
	}

	init(
		replayDuration: TimeInterval,
		resolutionID: String?,
		qualityID: String,
		frameRate: Int,
		containerID: String,
		audioCodecID: String,
		recordingModeID: String,
		hotkey: Hotkey,
		startRecordingHotkey: Hotkey,
		stopRecordingHotkey: Hotkey,
		alwaysRecordEnabled: Bool,
		saveFeedbackEnabled: Bool,
		saveFeedbackVolume: Double,
		saveFeedbackSoundID: String,
		recordingStartFeedbackEnabled: Bool,
		recordingStartFeedbackVolume: Double,
		recordingStartFeedbackSoundID: String,
		recordingEndFeedbackEnabled: Bool,
		recordingEndFeedbackVolume: Double,
		recordingEndFeedbackSoundID: String,
		errorFeedbackEnabled: Bool,
		errorFeedbackVolume: Double,
		errorFeedbackSoundID: String,
		discordRPCEnabled: Bool,
		shareGamePresenceEnabled: Bool,
		shareRobloxExperienceEnabled: Bool,
		fileLoggingEnabled: Bool,
		analyticsEnabled: Bool,

		betaUpdatesEnabled: Bool,
		enabledUploadProviderIDs: [String],
		recordMicrophoneEnabled: Bool,
		recordDesktopAudioEnabled: Bool,
		captureTargetPromptEnabled: Bool,
		microphoneDeviceID: String?,
		outputDirectoryPath: String?
	) {
		self.replayDuration = replayDuration
		self.resolutionID = resolutionID
		self.qualityID = qualityID
		self.frameRate = frameRate
		self.containerID = containerID
		self.audioCodecID = audioCodecID
		self.recordingModeID = recordingModeID
		self.hotkey = hotkey
		self.startRecordingHotkey = startRecordingHotkey
		self.stopRecordingHotkey = stopRecordingHotkey
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
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		replayDuration = try container.decode(TimeInterval.self, forKey: .replayDuration)
		resolutionID = try container.decodeIfPresent(String.self, forKey: .resolutionID)
		qualityID = try container.decodeIfPresent(String.self, forKey: .qualityID) ?? QualityPreset.default.id
		frameRate = try container.decodeIfPresent(Int.self, forKey: .frameRate) ?? CaptureFrameRate.default.framesPerSecond
		containerID = try container.decodeIfPresent(String.self, forKey: .containerID) ?? CaptureContainer.default.id
		audioCodecID = try container.decodeIfPresent(String.self, forKey: .audioCodecID) ?? CaptureAudioCodec.default.id
		recordingModeID = try container.decodeIfPresent(String.self, forKey: .recordingModeID) ?? RecordingMode.default.id
		hotkey = try container.decode(Hotkey.self, forKey: .hotkey)
		startRecordingHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .startRecordingHotkey)
			?? .startRecordingDefault
		stopRecordingHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .stopRecordingHotkey)
			?? .stopRecordingDefault
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

		try container.encode(recordingModeID, forKey: .recordingModeID)
		try container.encode(hotkey, forKey: .hotkey)
		try container.encode(startRecordingHotkey, forKey: .startRecordingHotkey)
		try container.encode(stopRecordingHotkey, forKey: .stopRecordingHotkey)
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

	var recordingMode: RecordingMode {
		RecordingMode.options.first(where: { $0.id == recordingModeID }) ?? .default
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
			guard isValid(decoded) else {
				UserDefaults.standard.removeObject(forKey: key)
				return .default
			}
			if let normalized = try? JSONEncoder().encode(decoded), normalized != data {
				UserDefaults.standard.set(normalized, forKey: key)
			}
			return decoded
		}

		if UserDefaults.standard.object(forKey: key) != nil {
			UserDefaults.standard.removeObject(forKey: key)
		}

		return .default
	}

	static func save(_ settings: AppSettings) {
		guard isValid(settings),
		      let data = try? JSONEncoder().encode(settings)
		else {
			UserDefaults.standard.removeObject(forKey: key)
			return
		}
		UserDefaults.standard.set(data, forKey: key)
	}

	private static func isValid(_ settings: AppSettings) -> Bool {
		guard AppSettings.replayDurationRange.contains(settings.replayDuration) else {
			return false
		}
		guard QualityPreset.presets.contains(where: { $0.id == settings.qualityID }) else {
			return false
		}
		guard CaptureFrameRate.options.contains(where: { $0.framesPerSecond == settings.frameRate }) else {
			return false
		}
		guard CaptureContainer.options.contains(where: { $0.id == settings.containerID }) else {
			return false
		}
		guard CaptureAudioCodec.options.contains(where: { $0.id == settings.audioCodecID }) else {
			return false
		}
		guard RecordingMode.options.contains(where: { $0.id == settings.recordingModeID }) else {
			return false
		}
		guard AppSettings.saveFeedbackVolumeRange.contains(settings.saveFeedbackVolume) else {
			return false
		}
		guard FeedbackSound.options.contains(where: { $0.id == settings.saveFeedbackSoundID }) else {
			return false
		}
		guard AppSettings.saveFeedbackVolumeRange.contains(settings.recordingStartFeedbackVolume) else {
			return false
		}
		guard FeedbackSound.options.contains(where: { $0.id == settings.recordingStartFeedbackSoundID }) else {
			return false
		}
		guard AppSettings.saveFeedbackVolumeRange.contains(settings.recordingEndFeedbackVolume) else {
			return false
		}
		guard FeedbackSound.options.contains(where: { $0.id == settings.recordingEndFeedbackSoundID }) else {
			return false
		}
		guard AppSettings.saveFeedbackVolumeRange.contains(settings.errorFeedbackVolume) else {
			return false
		}
		guard FeedbackSound.options.contains(where: { $0.id == settings.errorFeedbackSoundID }) else {
			return false
		}
		return true
	}
}
