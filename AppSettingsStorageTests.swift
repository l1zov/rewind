@testable import Rewind
import XCTest

final class AppSettingsStorageTests: XCTestCase {
	private let storageKey = "settings.app.v1"

	override func setUp() {
		super.setUp()
		UserDefaults.standard.removeObject(forKey: storageKey)
	}

	override func tearDown() {
		UserDefaults.standard.removeObject(forKey: storageKey)
		super.tearDown()
	}

	func testLoadReturnsDefaultWhenNoSettingsExist() {
		let settings = AppSettingsStorage.load()

		XCTAssertEqual(settings.replayDuration, AppSettings.default.replayDuration)
		XCTAssertEqual(settings.resolutionID, AppSettings.default.resolutionID)
		XCTAssertEqual(settings.qualityID, AppSettings.default.qualityID)
		XCTAssertEqual(settings.frameRate, AppSettings.default.frameRate)
		XCTAssertEqual(settings.containerID, AppSettings.default.containerID)
		XCTAssertEqual(settings.audioCodecID, AppSettings.default.audioCodecID)
		XCTAssertEqual(settings.recordingModeID, RecordingMode.instantReplay.id)
		XCTAssertEqual(settings.recordingMode, .instantReplay)
		XCTAssertEqual(settings.hotkey, AppSettings.default.hotkey)
		XCTAssertEqual(settings.startRecordingHotkey, AppSettings.default.startRecordingHotkey)
		XCTAssertEqual(settings.stopRecordingHotkey, AppSettings.default.stopRecordingHotkey)
		XCTAssertEqual(settings.alwaysRecordEnabled, AppSettings.default.alwaysRecordEnabled)
		XCTAssertEqual(settings.saveFeedbackEnabled, AppSettings.default.saveFeedbackEnabled)
		XCTAssertEqual(settings.saveFeedbackVolume, AppSettings.default.saveFeedbackVolume)
		XCTAssertEqual(settings.saveFeedbackSoundID, AppSettings.default.saveFeedbackSoundID)
		XCTAssertEqual(settings.recordingStartFeedbackEnabled, AppSettings.default.recordingStartFeedbackEnabled)
		XCTAssertEqual(settings.recordingStartFeedbackVolume, AppSettings.default.recordingStartFeedbackVolume)
		XCTAssertEqual(settings.recordingStartFeedbackSoundID, AppSettings.default.recordingStartFeedbackSoundID)
		XCTAssertEqual(settings.recordingEndFeedbackEnabled, AppSettings.default.recordingEndFeedbackEnabled)
		XCTAssertEqual(settings.recordingEndFeedbackVolume, AppSettings.default.recordingEndFeedbackVolume)
		XCTAssertEqual(settings.recordingEndFeedbackSoundID, AppSettings.default.recordingEndFeedbackSoundID)
		XCTAssertEqual(settings.errorFeedbackEnabled, AppSettings.default.errorFeedbackEnabled)
		XCTAssertEqual(settings.errorFeedbackVolume, AppSettings.default.errorFeedbackVolume)
		XCTAssertEqual(settings.errorFeedbackSoundID, AppSettings.default.errorFeedbackSoundID)
		XCTAssertEqual(settings.discordRPCEnabled, AppSettings.default.discordRPCEnabled)
		XCTAssertEqual(settings.fileLoggingEnabled, AppSettings.default.fileLoggingEnabled)
		XCTAssertEqual(settings.analyticsEnabled, AppSettings.default.analyticsEnabled)
		XCTAssertEqual(settings.enabledUploadProviderIDs, AppSettings.default.enabledUploadProviderIDs)
		XCTAssertEqual(settings.recordMicrophoneEnabled, AppSettings.default.recordMicrophoneEnabled)
	}

	func testSaveThenLoadPersistsValues() {
		let expected = AppSettings(
			replayDuration: 45,
			resolutionID: "1920x1080",
			qualityID: "very-high",
			frameRate: 30,
			containerID: "mp4",
			audioCodecID: CaptureAudioCodec.aac.id,
			recordingModeID: RecordingMode.recording.id,
			hotkey: Hotkey(keyCode: 0, modifiers: Hotkey.default.modifiers),
			startRecordingHotkey: Hotkey.startRecordingDefault,
			stopRecordingHotkey: Hotkey.stopRecordingDefault,
			alwaysRecordEnabled: true,
			saveFeedbackEnabled: false,
			saveFeedbackVolume: 15,
			saveFeedbackSoundID: FeedbackSound.pop.id,
			recordingStartFeedbackEnabled: false,
			recordingStartFeedbackVolume: 25,
			recordingStartFeedbackSoundID: FeedbackSound.ping.id,
			recordingEndFeedbackEnabled: true,
			recordingEndFeedbackVolume: 35,
			recordingEndFeedbackSoundID: FeedbackSound.cling.id,
			errorFeedbackEnabled: true,
			errorFeedbackVolume: 45,
			errorFeedbackSoundID: FeedbackSound.pop.id,
			discordRPCEnabled: false,
			shareGamePresenceEnabled: AppSettings.default.shareGamePresenceEnabled,
			shareRobloxExperienceEnabled: AppSettings.default.shareRobloxExperienceEnabled,
			fileLoggingEnabled: false,
			analyticsEnabled: false,

			betaUpdatesEnabled: false,
			enabledUploadProviderIDs: [ClipUploadProvider.catboxID],
			recordMicrophoneEnabled: true,
			recordDesktopAudioEnabled: false,
			captureTargetPromptEnabled: false,
			microphoneDeviceID: "com.example.mic.usb",
			outputDirectoryPath: "/Users/example/Desktop/Clips"
		)

		AppSettingsStorage.save(expected)
		let loaded = AppSettingsStorage.load()

		XCTAssertEqual(loaded.replayDuration, expected.replayDuration)
		XCTAssertEqual(loaded.resolutionID, expected.resolutionID)
		XCTAssertEqual(loaded.qualityID, expected.qualityID)
		XCTAssertEqual(loaded.frameRate, expected.frameRate)
		XCTAssertEqual(loaded.containerID, expected.containerID)
		XCTAssertEqual(loaded.audioCodecID, expected.audioCodecID)
		XCTAssertEqual(loaded.recordingModeID, expected.recordingModeID)
		XCTAssertEqual(loaded.recordingMode, RecordingMode.recording)
		XCTAssertEqual(loaded.hotkey, expected.hotkey)
		XCTAssertEqual(loaded.startRecordingHotkey, expected.startRecordingHotkey)
		XCTAssertEqual(loaded.stopRecordingHotkey, expected.stopRecordingHotkey)
		XCTAssertEqual(loaded.alwaysRecordEnabled, expected.alwaysRecordEnabled)
		XCTAssertEqual(loaded.saveFeedbackEnabled, expected.saveFeedbackEnabled)
		XCTAssertEqual(loaded.saveFeedbackVolume, expected.saveFeedbackVolume)
		XCTAssertEqual(loaded.saveFeedbackSoundID, expected.saveFeedbackSoundID)
		XCTAssertEqual(loaded.recordingStartFeedbackEnabled, expected.recordingStartFeedbackEnabled)
		XCTAssertEqual(loaded.recordingStartFeedbackVolume, expected.recordingStartFeedbackVolume)
		XCTAssertEqual(loaded.recordingStartFeedbackSoundID, expected.recordingStartFeedbackSoundID)
		XCTAssertEqual(loaded.recordingEndFeedbackEnabled, expected.recordingEndFeedbackEnabled)
		XCTAssertEqual(loaded.recordingEndFeedbackVolume, expected.recordingEndFeedbackVolume)
		XCTAssertEqual(loaded.recordingEndFeedbackSoundID, expected.recordingEndFeedbackSoundID)
		XCTAssertEqual(loaded.errorFeedbackEnabled, expected.errorFeedbackEnabled)
		XCTAssertEqual(loaded.errorFeedbackVolume, expected.errorFeedbackVolume)
		XCTAssertEqual(loaded.errorFeedbackSoundID, expected.errorFeedbackSoundID)
		XCTAssertEqual(loaded.discordRPCEnabled, expected.discordRPCEnabled)
		XCTAssertEqual(loaded.fileLoggingEnabled, expected.fileLoggingEnabled)
		XCTAssertEqual(loaded.analyticsEnabled, expected.analyticsEnabled)
		XCTAssertEqual(loaded.enabledUploadProviderIDs, expected.enabledUploadProviderIDs)
		XCTAssertEqual(loaded.recordMicrophoneEnabled, expected.recordMicrophoneEnabled)
		XCTAssertEqual(loaded.recordDesktopAudioEnabled, expected.recordDesktopAudioEnabled)
		XCTAssertEqual(loaded.captureTargetPromptEnabled, expected.captureTargetPromptEnabled)
		XCTAssertEqual(loaded.microphoneDeviceID, expected.microphoneDeviceID)
		XCTAssertEqual(loaded.outputDirectoryPath, expected.outputDirectoryPath)
	}

	func testLoadClearsStoredValuesAndReturnsDefaultWhenStoredSettingsAreInvalid() throws {
		let invalid = AppSettings(
			replayDuration: 500,
			resolutionID: "jldsjkjdhsk",
			qualityID: "dsjdjhhdha",
			frameRate: 999,
			containerID: "hhkkhhklllllll",
			audioCodecID: "nope",
			recordingModeID: "nope",
			hotkey: Hotkey(keyCode: 999, modifiers: 0),
			startRecordingHotkey: Hotkey(keyCode: 998, modifiers: 0),
			stopRecordingHotkey: Hotkey(keyCode: 997, modifiers: 0),
			alwaysRecordEnabled: true,
			saveFeedbackEnabled: true,
			saveFeedbackVolume: 300,
			saveFeedbackSoundID: "1234556789blahhhh",
			recordingStartFeedbackEnabled: true,
			recordingStartFeedbackVolume: 300,
			recordingStartFeedbackSoundID: "1234556789blahhhh",
			recordingEndFeedbackEnabled: true,
			recordingEndFeedbackVolume: 300,
			recordingEndFeedbackSoundID: "1234556789blahhhh",
			errorFeedbackEnabled: true,
			errorFeedbackVolume: 300,
			errorFeedbackSoundID: "1234556789blahhhh",
			discordRPCEnabled: false,
			shareGamePresenceEnabled: AppSettings.default.shareGamePresenceEnabled,
			shareRobloxExperienceEnabled: AppSettings.default.shareRobloxExperienceEnabled,
			fileLoggingEnabled: false,
			analyticsEnabled: false,

			betaUpdatesEnabled: false,
			enabledUploadProviderIDs: [],
			recordMicrophoneEnabled: true,
			recordDesktopAudioEnabled: true,
			captureTargetPromptEnabled: true,
			microphoneDeviceID: nil,
			outputDirectoryPath: nil
		)
		let data = try JSONEncoder().encode(invalid)
		UserDefaults.standard.set(data, forKey: storageKey)

		let loaded = AppSettingsStorage.load()

		XCTAssertNil(UserDefaults.standard.object(forKey: storageKey))
		XCTAssertEqual(loaded.replayDuration, AppSettings.default.replayDuration)
		XCTAssertEqual(loaded.resolutionID, AppSettings.default.resolutionID)
		XCTAssertEqual(loaded.qualityID, AppSettings.default.qualityID)
		XCTAssertEqual(loaded.frameRate, AppSettings.default.frameRate)
		XCTAssertEqual(loaded.containerID, AppSettings.default.containerID)
		XCTAssertEqual(loaded.audioCodecID, AppSettings.default.audioCodecID)
		XCTAssertEqual(loaded.recordingModeID, AppSettings.default.recordingModeID)
		XCTAssertEqual(loaded.hotkey, AppSettings.default.hotkey)
		XCTAssertEqual(loaded.startRecordingHotkey, AppSettings.default.startRecordingHotkey)
		XCTAssertEqual(loaded.stopRecordingHotkey, AppSettings.default.stopRecordingHotkey)
		XCTAssertEqual(loaded.alwaysRecordEnabled, AppSettings.default.alwaysRecordEnabled)
		XCTAssertEqual(loaded.saveFeedbackEnabled, AppSettings.default.saveFeedbackEnabled)
		XCTAssertEqual(loaded.saveFeedbackVolume, AppSettings.default.saveFeedbackVolume)
		XCTAssertEqual(loaded.saveFeedbackSoundID, AppSettings.default.saveFeedbackSoundID)
		XCTAssertEqual(loaded.recordingStartFeedbackEnabled, AppSettings.default.recordingStartFeedbackEnabled)
		XCTAssertEqual(loaded.recordingStartFeedbackVolume, AppSettings.default.recordingStartFeedbackVolume)
		XCTAssertEqual(loaded.recordingStartFeedbackSoundID, AppSettings.default.recordingStartFeedbackSoundID)
		XCTAssertEqual(loaded.recordingEndFeedbackEnabled, AppSettings.default.recordingEndFeedbackEnabled)
		XCTAssertEqual(loaded.recordingEndFeedbackVolume, AppSettings.default.recordingEndFeedbackVolume)
		XCTAssertEqual(loaded.recordingEndFeedbackSoundID, AppSettings.default.recordingEndFeedbackSoundID)
		XCTAssertEqual(loaded.errorFeedbackEnabled, AppSettings.default.errorFeedbackEnabled)
		XCTAssertEqual(loaded.errorFeedbackVolume, AppSettings.default.errorFeedbackVolume)
		XCTAssertEqual(loaded.errorFeedbackSoundID, AppSettings.default.errorFeedbackSoundID)
		XCTAssertEqual(loaded.discordRPCEnabled, AppSettings.default.discordRPCEnabled)
		XCTAssertEqual(loaded.fileLoggingEnabled, AppSettings.default.fileLoggingEnabled)
		XCTAssertEqual(loaded.analyticsEnabled, AppSettings.default.analyticsEnabled)
		XCTAssertEqual(loaded.recordMicrophoneEnabled, AppSettings.default.recordMicrophoneEnabled)
	}

	func testLoadFallsBackToDefaultWhenStoredBlobIsInvalid() {
		UserDefaults.standard.set(Data([0x00, 0x01, 0x02]), forKey: storageKey)

		let loaded = AppSettingsStorage.load()

		XCTAssertNil(UserDefaults.standard.object(forKey: storageKey))
		XCTAssertEqual(loaded.replayDuration, AppSettings.default.replayDuration)
		XCTAssertEqual(loaded.qualityID, AppSettings.default.qualityID)
		XCTAssertEqual(loaded.frameRate, AppSettings.default.frameRate)
		XCTAssertEqual(loaded.containerID, AppSettings.default.containerID)
		XCTAssertEqual(loaded.audioCodecID, AppSettings.default.audioCodecID)
		XCTAssertEqual(loaded.recordingModeID, AppSettings.default.recordingModeID)
		XCTAssertEqual(loaded.hotkey, AppSettings.default.hotkey)
		XCTAssertEqual(loaded.startRecordingHotkey, AppSettings.default.startRecordingHotkey)
		XCTAssertEqual(loaded.stopRecordingHotkey, AppSettings.default.stopRecordingHotkey)
		XCTAssertEqual(loaded.alwaysRecordEnabled, AppSettings.default.alwaysRecordEnabled)
		XCTAssertEqual(loaded.saveFeedbackEnabled, AppSettings.default.saveFeedbackEnabled)
		XCTAssertEqual(loaded.saveFeedbackVolume, AppSettings.default.saveFeedbackVolume)
		XCTAssertEqual(loaded.saveFeedbackSoundID, AppSettings.default.saveFeedbackSoundID)
		XCTAssertEqual(loaded.recordingStartFeedbackEnabled, AppSettings.default.recordingStartFeedbackEnabled)
		XCTAssertEqual(loaded.recordingStartFeedbackVolume, AppSettings.default.recordingStartFeedbackVolume)
		XCTAssertEqual(loaded.recordingStartFeedbackSoundID, AppSettings.default.recordingStartFeedbackSoundID)
		XCTAssertEqual(loaded.recordingEndFeedbackEnabled, AppSettings.default.recordingEndFeedbackEnabled)
		XCTAssertEqual(loaded.recordingEndFeedbackVolume, AppSettings.default.recordingEndFeedbackVolume)
		XCTAssertEqual(loaded.recordingEndFeedbackSoundID, AppSettings.default.recordingEndFeedbackSoundID)
		XCTAssertEqual(loaded.errorFeedbackEnabled, AppSettings.default.errorFeedbackEnabled)
		XCTAssertEqual(loaded.errorFeedbackVolume, AppSettings.default.errorFeedbackVolume)
		XCTAssertEqual(loaded.errorFeedbackSoundID, AppSettings.default.errorFeedbackSoundID)
		XCTAssertEqual(loaded.discordRPCEnabled, AppSettings.default.discordRPCEnabled)
		XCTAssertEqual(loaded.fileLoggingEnabled, AppSettings.default.fileLoggingEnabled)
		XCTAssertEqual(loaded.analyticsEnabled, AppSettings.default.analyticsEnabled)
		XCTAssertEqual(loaded.recordMicrophoneEnabled, AppSettings.default.recordMicrophoneEnabled)
	}

	func testSaveClearsStorageWhenSettingsAreInvalid() {
		let invalid = AppSettings(
			replayDuration: AppSettings.default.replayDuration,
			resolutionID: AppSettings.default.resolutionID,
			qualityID: "old-balanced-id",
			frameRate: AppSettings.default.frameRate,
			containerID: AppSettings.default.containerID,
			audioCodecID: AppSettings.default.audioCodecID,
			recordingModeID: AppSettings.default.recordingModeID,
			hotkey: AppSettings.default.hotkey,
			startRecordingHotkey: AppSettings.default.startRecordingHotkey,
			stopRecordingHotkey: AppSettings.default.stopRecordingHotkey,
			alwaysRecordEnabled: AppSettings.default.alwaysRecordEnabled,
			saveFeedbackEnabled: AppSettings.default.saveFeedbackEnabled,
			saveFeedbackVolume: AppSettings.default.saveFeedbackVolume,
			saveFeedbackSoundID: AppSettings.default.saveFeedbackSoundID,
			recordingStartFeedbackEnabled: AppSettings.default.recordingStartFeedbackEnabled,
			recordingStartFeedbackVolume: AppSettings.default.recordingStartFeedbackVolume,
			recordingStartFeedbackSoundID: AppSettings.default.recordingStartFeedbackSoundID,
			recordingEndFeedbackEnabled: AppSettings.default.recordingEndFeedbackEnabled,
			recordingEndFeedbackVolume: AppSettings.default.recordingEndFeedbackVolume,
			recordingEndFeedbackSoundID: AppSettings.default.recordingEndFeedbackSoundID,
			errorFeedbackEnabled: AppSettings.default.errorFeedbackEnabled,
			errorFeedbackVolume: AppSettings.default.errorFeedbackVolume,
			errorFeedbackSoundID: AppSettings.default.errorFeedbackSoundID,
			discordRPCEnabled: AppSettings.default.discordRPCEnabled,
			shareGamePresenceEnabled: AppSettings.default.shareGamePresenceEnabled,
			shareRobloxExperienceEnabled: AppSettings.default.shareRobloxExperienceEnabled,
			fileLoggingEnabled: AppSettings.default.fileLoggingEnabled,
			analyticsEnabled: AppSettings.default.analyticsEnabled,

			betaUpdatesEnabled: AppSettings.default.betaUpdatesEnabled,
			enabledUploadProviderIDs: AppSettings.default.enabledUploadProviderIDs,
			recordMicrophoneEnabled: AppSettings.default.recordMicrophoneEnabled,
			recordDesktopAudioEnabled: AppSettings.default.recordDesktopAudioEnabled,
			captureTargetPromptEnabled: AppSettings.default.captureTargetPromptEnabled,
			microphoneDeviceID: AppSettings.default.microphoneDeviceID,
			outputDirectoryPath: AppSettings.default.outputDirectoryPath
		)

		AppSettingsStorage.save(invalid)

		XCTAssertNil(UserDefaults.standard.object(forKey: storageKey))
	}

	// - Default tracking ---

	private func storedDictionary() throws -> [String: Any] {
		let data = try XCTUnwrap(UserDefaults.standard.data(forKey: storageKey))
		return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
	}

	private func settings(
		qualityID: String,
		frameRate: Int,
		containerID: String,
		audioCodecID: String
	) -> AppSettings {
		AppSettings(
			replayDuration: AppSettings.default.replayDuration,
			resolutionID: AppSettings.default.resolutionID,
			qualityID: qualityID,
			frameRate: frameRate,
			containerID: containerID,
			audioCodecID: audioCodecID,
			recordingModeID: AppSettings.default.recordingModeID,
			hotkey: AppSettings.default.hotkey,
			startRecordingHotkey: AppSettings.default.startRecordingHotkey,
			stopRecordingHotkey: AppSettings.default.stopRecordingHotkey,
			alwaysRecordEnabled: AppSettings.default.alwaysRecordEnabled,
			saveFeedbackEnabled: AppSettings.default.saveFeedbackEnabled,
			saveFeedbackVolume: AppSettings.default.saveFeedbackVolume,
			saveFeedbackSoundID: AppSettings.default.saveFeedbackSoundID,
			recordingStartFeedbackEnabled: AppSettings.default.recordingStartFeedbackEnabled,
			recordingStartFeedbackVolume: AppSettings.default.recordingStartFeedbackVolume,
			recordingStartFeedbackSoundID: AppSettings.default.recordingStartFeedbackSoundID,
			recordingEndFeedbackEnabled: AppSettings.default.recordingEndFeedbackEnabled,
			recordingEndFeedbackVolume: AppSettings.default.recordingEndFeedbackVolume,
			recordingEndFeedbackSoundID: AppSettings.default.recordingEndFeedbackSoundID,
			errorFeedbackEnabled: AppSettings.default.errorFeedbackEnabled,
			errorFeedbackVolume: AppSettings.default.errorFeedbackVolume,
			errorFeedbackSoundID: AppSettings.default.errorFeedbackSoundID,
			discordRPCEnabled: AppSettings.default.discordRPCEnabled,
			shareGamePresenceEnabled: AppSettings.default.shareGamePresenceEnabled,
			shareRobloxExperienceEnabled: AppSettings.default.shareRobloxExperienceEnabled,
			fileLoggingEnabled: AppSettings.default.fileLoggingEnabled,
			analyticsEnabled: AppSettings.default.analyticsEnabled,

			betaUpdatesEnabled: AppSettings.default.betaUpdatesEnabled,
			enabledUploadProviderIDs: AppSettings.default.enabledUploadProviderIDs,
			recordMicrophoneEnabled: AppSettings.default.recordMicrophoneEnabled,
			recordDesktopAudioEnabled: AppSettings.default.recordDesktopAudioEnabled,
			captureTargetPromptEnabled: AppSettings.default.captureTargetPromptEnabled,
			microphoneDeviceID: AppSettings.default.microphoneDeviceID,
			outputDirectoryPath: AppSettings.default.outputDirectoryPath
		)
	}

	func testDefaultValuedOptionsAreOmittedFromStorage() throws {
		AppSettingsStorage.save(
			settings(
				qualityID: QualityPreset.default.id,
				frameRate: CaptureFrameRate.default.framesPerSecond,
				containerID: CaptureContainer.default.id,
				audioCodecID: CaptureAudioCodec.default.id
			)
		)

		let dict = try storedDictionary()
		XCTAssertNil(dict["qualityID"])
		XCTAssertNil(dict["frameRate"])
		XCTAssertNil(dict["containerID"])
		XCTAssertNil(dict["audioCodecID"])
	}

	func testNonDefaultOptionsArePersisted() throws {
		let nonDefaultContainer = CaptureContainer.options.first { !$0.isDefault }!
		let nonDefaultQuality = QualityPreset.presets.first { !$0.isDefault }!
		let nonDefaultFrameRate = CaptureFrameRate.options.first { !$0.isDefault }!

		AppSettingsStorage.save(
			settings(
				qualityID: nonDefaultQuality.id,
				frameRate: nonDefaultFrameRate.framesPerSecond,
				containerID: nonDefaultContainer.id,
				audioCodecID: CaptureAudioCodec.default.id
			)
		)

		let dict = try storedDictionary()
		XCTAssertEqual(dict["containerID"] as? String, nonDefaultContainer.id)
		XCTAssertNil(dict["audioCodecID"])

		let loaded = AppSettingsStorage.load()
		XCTAssertEqual(loaded.containerID, nonDefaultContainer.id)
		XCTAssertEqual(loaded.audioCodecID, CaptureAudioCodec.default.id)
		XCTAssertEqual(loaded.qualityID, nonDefaultQuality.id)
		XCTAssertEqual(loaded.frameRate, nonDefaultFrameRate.framesPerSecond)
	}

	func testAbsentOptionsAndRecordingSettingsResolveToCurrentDefaults() throws {
		var dict = try XCTUnwrap(
			JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.default)) as? [String: Any]
		)
		dict.removeValue(forKey: "qualityID")
		dict.removeValue(forKey: "frameRate")
		dict.removeValue(forKey: "containerID")
		dict.removeValue(forKey: "audioCodecID")
		dict.removeValue(forKey: "recordingModeID")
		dict.removeValue(forKey: "stopRecordingHotkey")
		UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: dict), forKey: storageKey)

		let loaded = AppSettingsStorage.load()
		XCTAssertEqual(loaded.qualityID, QualityPreset.default.id)
		XCTAssertEqual(loaded.frameRate, CaptureFrameRate.default.framesPerSecond)
		XCTAssertEqual(loaded.containerID, CaptureContainer.default.id)
		XCTAssertEqual(loaded.audioCodecID, CaptureAudioCodec.default.id)
		XCTAssertEqual(loaded.recordingMode, RecordingMode.instantReplay)
		XCTAssertEqual(loaded.stopRecordingHotkey, Hotkey.stopRecordingDefault)
	}

	func testUnknownRecordingModeClearsStoredSettings() throws {
		var dict = try XCTUnwrap(
			JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.default)) as? [String: Any]
		)
		dict["recordingModeID"] = "future-mode"
		UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: dict), forKey: storageKey)

		let loaded = AppSettingsStorage.load()

		XCTAssertNil(UserDefaults.standard.object(forKey: storageKey))
		XCTAssertEqual(loaded.recordingMode, RecordingMode.instantReplay)
	}

	func testLegacyDefaultValuedBlobIsNormalizedOnLoad() throws {
		var dict = try XCTUnwrap(
			JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.default)) as? [String: Any]
		)
		dict["qualityID"] = QualityPreset.default.id
		dict["frameRate"] = CaptureFrameRate.default.framesPerSecond
		dict["containerID"] = CaptureContainer.default.id
		dict["audioCodecID"] = CaptureAudioCodec.default.id
		UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: dict), forKey: storageKey)

		_ = AppSettingsStorage.load()

		let normalized = try storedDictionary()
		XCTAssertNil(normalized["qualityID"])
		XCTAssertNil(normalized["frameRate"])
		XCTAssertNil(normalized["containerID"])
		XCTAssertNil(normalized["audioCodecID"])
	}

	func testLegacyNonDefaultBlobIsPreservedOnLoad() throws {
		let nonDefaultContainer = CaptureContainer.options.first { !$0.isDefault }!
		var dict = try XCTUnwrap(
			JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.default)) as? [String: Any]
		)
		dict["containerID"] = nonDefaultContainer.id
		UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: dict), forKey: storageKey)

		let loaded = AppSettingsStorage.load()
		XCTAssertEqual(loaded.containerID, nonDefaultContainer.id)

		let stored = try storedDictionary()
		XCTAssertEqual(stored["containerID"] as? String, nonDefaultContainer.id)
	}
}
