import Defaults
@testable import Rewind
import XCTest

final class DefaultsMigrationTests: XCTestCase {
	private let suiteName = "test.rewind.defaults.migration"
	private var testDefaults: UserDefaults!

	override func setUp() {
		super.setUp()
		testDefaults = UserDefaults(suiteName: suiteName)!
		testDefaults.removePersistentDomain(forName: suiteName)
	}

	override func tearDown() {
		testDefaults.removePersistentDomain(forName: suiteName)
		super.tearDown()
	}

	func testMigratesLegacyJSONBlob() throws {
		let legacySettings = AppSettings(
			replayDuration: 60,
			resolutionID: "1920x1080",
			qualityID: "high",
			frameRate: 60,
			containerID: "mp4",
			audioCodecID: "aac",
			hotkey: Hotkey(keyCode: 1, modifiers: 2),
			startRecordingHotkey: Hotkey(keyCode: 3, modifiers: 4),
			alwaysRecordEnabled: true,
			saveFeedbackEnabled: false,
			saveFeedbackVolume: 35,
			saveFeedbackSoundID: "pop",
			recordingStartFeedbackEnabled: false,
			recordingStartFeedbackVolume: 40,
			recordingStartFeedbackSoundID: "ping",
			recordingEndFeedbackEnabled: false,
			recordingEndFeedbackVolume: 45,
			recordingEndFeedbackSoundID: "cling",
			errorFeedbackEnabled: false,
			errorFeedbackVolume: 50,
			errorFeedbackSoundID: "pop",
			discordRPCEnabled: false,
			shareGamePresenceEnabled: false,
			shareRobloxExperienceEnabled: false,
			fileLoggingEnabled: true,
			analyticsEnabled: false,
			betaUpdatesEnabled: true,
			enabledUploadProviderIDs: ["catbox"],
			recordMicrophoneEnabled: true,
			recordDesktopAudioEnabled: false,
			captureTargetPromptEnabled: false,
			microphoneDeviceID: "mic-123",
			outputDirectoryPath: "/tmp/clips",
			desktopAudioVolume: 0.5,
			microphoneVolume: 0.8
		)

		let encoded = try JSONEncoder().encode(legacySettings)
		testDefaults.set(encoded, forKey: "settings.app.v1")

		DefaultsMigration.migrateLegacySettingsIfNeeded(userDefaults: testDefaults)

		XCTAssertNil(testDefaults.object(forKey: "settings.app.v1"))

		XCTAssertEqual(testDefaults.double(forKey: "replayDuration"), 60)
		XCTAssertEqual(testDefaults.string(forKey: "resolutionID"), "1920x1080")
		XCTAssertEqual(testDefaults.string(forKey: "qualityID"), "high")
		XCTAssertEqual(testDefaults.integer(forKey: "frameRate"), 60)
		XCTAssertEqual(testDefaults.string(forKey: "containerID"), "mp4")
		XCTAssertEqual(testDefaults.string(forKey: "audioCodecID"), "aac")
		XCTAssertEqual(testDefaults.bool(forKey: "alwaysRecordEnabled"), true)
		XCTAssertEqual(testDefaults.bool(forKey: "saveFeedbackEnabled"), false)
		XCTAssertEqual(testDefaults.double(forKey: "saveFeedbackVolume"), 35)
		XCTAssertEqual(testDefaults.bool(forKey: "fileLoggingEnabled"), true)
		XCTAssertEqual(testDefaults.bool(forKey: "analyticsEnabled"), false)
		XCTAssertEqual(testDefaults.bool(forKey: "betaUpdatesEnabled"), true)
		XCTAssertEqual(testDefaults.string(forKey: "outputDirectoryPath"), "/tmp/clips")
		XCTAssertEqual(testDefaults.double(forKey: "desktopAudioVolume"), 0.5)
		XCTAssertEqual(testDefaults.double(forKey: "microphoneVolume"), 0.8)
	}
}
