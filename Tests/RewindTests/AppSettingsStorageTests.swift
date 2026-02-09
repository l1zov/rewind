import XCTest
@testable import Rewind

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
    XCTAssertEqual(settings.hotkey, AppSettings.default.hotkey)
    XCTAssertEqual(settings.startRecordingHotkey, AppSettings.default.startRecordingHotkey)
    XCTAssertEqual(settings.saveFeedbackEnabled, AppSettings.default.saveFeedbackEnabled)
    XCTAssertEqual(settings.saveFeedbackVolume, AppSettings.default.saveFeedbackVolume)
    XCTAssertEqual(settings.saveFeedbackSoundID, AppSettings.default.saveFeedbackSoundID)
    XCTAssertEqual(settings.discordRPCEnabled, AppSettings.default.discordRPCEnabled)
  }

  func testSaveThenLoadPersistsValues() {
    let expected = AppSettings(
      replayDuration: 45,
      resolutionID: "1920x1080",
      qualityID: "ultra",
      frameRate: 30,
      containerID: "mp4",
      hotkey: Hotkey(keyCode: 0, modifiers: Hotkey.default.modifiers),
      startRecordingHotkey: Hotkey.startRecordingDefault,
      saveFeedbackEnabled: false,
      saveFeedbackVolume: 15,
      saveFeedbackSoundID: SaveFeedbackSound.pop.id,
      discordRPCEnabled: false
    )

    AppSettingsStorage.save(expected)
    let loaded = AppSettingsStorage.load()

    XCTAssertEqual(loaded.replayDuration, expected.replayDuration)
    XCTAssertEqual(loaded.resolutionID, expected.resolutionID)
    XCTAssertEqual(loaded.qualityID, expected.qualityID)
    XCTAssertEqual(loaded.frameRate, expected.frameRate)
    XCTAssertEqual(loaded.containerID, expected.containerID)
    XCTAssertEqual(loaded.hotkey, expected.hotkey)
    XCTAssertEqual(loaded.startRecordingHotkey, expected.startRecordingHotkey)
    XCTAssertEqual(loaded.saveFeedbackEnabled, expected.saveFeedbackEnabled)
    XCTAssertEqual(loaded.saveFeedbackVolume, expected.saveFeedbackVolume)
    XCTAssertEqual(loaded.saveFeedbackSoundID, expected.saveFeedbackSoundID)
    XCTAssertEqual(loaded.discordRPCEnabled, expected.discordRPCEnabled)
  }

  func testLoadNormalizesInvalidStoredValues() throws {
    let invalid = AppSettings(
      replayDuration: 500,
      resolutionID: "jldsjkjdhsk",
      qualityID: "dsjdjhhdha",
      frameRate: 999,
      containerID: "hhkkhhklllllll",
      hotkey: Hotkey(keyCode: 999, modifiers: 0),
      startRecordingHotkey: Hotkey(keyCode: 998, modifiers: 0),
      saveFeedbackEnabled: true,
      saveFeedbackVolume: 300,
      saveFeedbackSoundID: "1234556789blahhhh",
      discordRPCEnabled: false
    )
    let data = try JSONEncoder().encode(invalid)
    UserDefaults.standard.set(data, forKey: storageKey)

    let loaded = AppSettingsStorage.load()

    XCTAssertEqual(loaded.replayDuration, AppSettings.replayDurationRange.upperBound)
    XCTAssertEqual(loaded.resolutionID, invalid.resolutionID)
    XCTAssertEqual(loaded.qualityID, QualityPreset.default.id)
    XCTAssertEqual(loaded.frameRate, CaptureFrameRate.default.framesPerSecond)
    XCTAssertEqual(loaded.containerID, CaptureContainer.default.id)
    XCTAssertEqual(loaded.hotkey, invalid.hotkey)
    XCTAssertEqual(loaded.startRecordingHotkey, invalid.startRecordingHotkey)
    XCTAssertEqual(loaded.saveFeedbackEnabled, invalid.saveFeedbackEnabled)
    XCTAssertEqual(loaded.saveFeedbackVolume, AppSettings.saveFeedbackVolumeRange.upperBound)
    XCTAssertEqual(loaded.saveFeedbackSoundID, SaveFeedbackSound.default.id)
    XCTAssertEqual(loaded.discordRPCEnabled, invalid.discordRPCEnabled)
  }

  func testLoadFallsBackToDefaultWhenStoredBlobIsInvalid() {
    UserDefaults.standard.set(Data([0x00, 0x01, 0x02]), forKey: storageKey)

    let loaded = AppSettingsStorage.load()

    XCTAssertEqual(loaded.replayDuration, AppSettings.default.replayDuration)
    XCTAssertEqual(loaded.qualityID, AppSettings.default.qualityID)
    XCTAssertEqual(loaded.frameRate, AppSettings.default.frameRate)
    XCTAssertEqual(loaded.containerID, AppSettings.default.containerID)
    XCTAssertEqual(loaded.hotkey, AppSettings.default.hotkey)
    XCTAssertEqual(loaded.startRecordingHotkey, AppSettings.default.startRecordingHotkey)
    XCTAssertEqual(loaded.saveFeedbackEnabled, AppSettings.default.saveFeedbackEnabled)
    XCTAssertEqual(loaded.saveFeedbackVolume, AppSettings.default.saveFeedbackVolume)
    XCTAssertEqual(loaded.saveFeedbackSoundID, AppSettings.default.saveFeedbackSoundID)
    XCTAssertEqual(loaded.discordRPCEnabled, AppSettings.default.discordRPCEnabled)
  }
}
