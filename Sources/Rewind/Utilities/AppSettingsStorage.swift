import Foundation

struct AppSettings: Codable, Sendable {
  static let replayDurationRange: ClosedRange<TimeInterval> = 10...120
  static let replayDurationStep: TimeInterval = 5
  static let replayDurationQuickOptions = [15, 30, 45, 60, 90, 120]
  static let saveFeedbackVolumeRange: ClosedRange<Double> = 1...100
  static let saveFeedbackVolumeStep: Double = 1

  var replayDuration: TimeInterval
  var resolutionID: String?
  var qualityID: String
  var frameRate: Int
  var containerID: String
  var hotkey: Hotkey
  var startRecordingHotkey: Hotkey
  var saveFeedbackEnabled: Bool
  var saveFeedbackVolume: Double
  var saveFeedbackSoundID: String
  var discordRPCEnabled: Bool

  static let `default` = AppSettings(
    replayDuration: 30,
    resolutionID: nil,
    qualityID: QualityPreset.default.id,
    frameRate: CaptureFrameRate.default.framesPerSecond,
    containerID: CaptureContainer.default.id,
    hotkey: .default,
    startRecordingHotkey: .startRecordingDefault,
    saveFeedbackEnabled: true,
    saveFeedbackVolume: 20,
    saveFeedbackSoundID: SaveFeedbackSound.default.id,
    discordRPCEnabled: true
  )

  private enum CodingKeys: String, CodingKey {
    case replayDuration
    case resolutionID
    case qualityID
    case frameRate
    case containerID
    case hotkey
    case startRecordingHotkey
    case saveFeedbackEnabled
    case saveFeedbackVolume
    case saveFeedbackSoundID
    case discordRPCEnabled
  }

  init(
    replayDuration: TimeInterval,
    resolutionID: String?,
    qualityID: String,
    frameRate: Int,
    containerID: String,
    hotkey: Hotkey,
    startRecordingHotkey: Hotkey,
    saveFeedbackEnabled: Bool,
    saveFeedbackVolume: Double,
    saveFeedbackSoundID: String,
    discordRPCEnabled: Bool
  ) {
    self.replayDuration = replayDuration
    self.resolutionID = resolutionID
    self.qualityID = qualityID
    self.frameRate = frameRate
    self.containerID = containerID
    self.hotkey = hotkey
    self.startRecordingHotkey = startRecordingHotkey
    self.saveFeedbackEnabled = saveFeedbackEnabled
    self.saveFeedbackVolume = saveFeedbackVolume
    self.saveFeedbackSoundID = saveFeedbackSoundID
    self.discordRPCEnabled = discordRPCEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    replayDuration = try container.decode(TimeInterval.self, forKey: .replayDuration)
    resolutionID = try container.decodeIfPresent(String.self, forKey: .resolutionID)
    qualityID = try container.decode(String.self, forKey: .qualityID)
    frameRate = try container.decode(Int.self, forKey: .frameRate)
    containerID = try container.decodeIfPresent(String.self, forKey: .containerID) ?? CaptureContainer.default.id
    hotkey = try container.decode(Hotkey.self, forKey: .hotkey)
    startRecordingHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .startRecordingHotkey)
      ?? .startRecordingDefault
    saveFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .saveFeedbackEnabled) ?? true
    saveFeedbackVolume = try container.decodeIfPresent(Double.self, forKey: .saveFeedbackVolume)
      ?? AppSettings.default.saveFeedbackVolume
    saveFeedbackSoundID = try container.decodeIfPresent(String.self, forKey: .saveFeedbackSoundID)
      ?? SaveFeedbackSound.default.id
    discordRPCEnabled = try container.decodeIfPresent(Bool.self, forKey: .discordRPCEnabled) ?? true
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

  var saveFeedbackSound: SaveFeedbackSound {
    SaveFeedbackSound.options.first(where: { $0.id == saveFeedbackSoundID }) ?? .default
  }
}

enum AppSettingsStorage {
  private static let key = "settings.app.v1"

  static func load() -> AppSettings {
    if let data = UserDefaults.standard.data(forKey: key),
       let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
      return normalize(decoded)
    }

    return .default
  }

  static func save(_ settings: AppSettings) {
    let normalized = normalize(settings)
    guard let data = try? JSONEncoder().encode(normalized) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }

  private static func normalize(_ settings: AppSettings) -> AppSettings {
    var normalized = settings
    normalized.replayDuration = min(
      max(normalized.replayDuration, AppSettings.replayDurationRange.lowerBound),
      AppSettings.replayDurationRange.upperBound
    )
    if QualityPreset.presets.contains(where: { $0.id == normalized.qualityID }) == false {
      normalized.qualityID = QualityPreset.default.id
    }
    if CaptureFrameRate.options.contains(where: { $0.framesPerSecond == normalized.frameRate }) == false {
      normalized.frameRate = CaptureFrameRate.default.framesPerSecond
    }
    if CaptureContainer.options.contains(where: { $0.id == normalized.containerID }) == false {
      normalized.containerID = CaptureContainer.default.id
    }
    normalized.saveFeedbackVolume = min(
      max(normalized.saveFeedbackVolume, AppSettings.saveFeedbackVolumeRange.lowerBound),
      AppSettings.saveFeedbackVolumeRange.upperBound
    )
    if SaveFeedbackSound.options.contains(where: { $0.id == normalized.saveFeedbackSoundID }) == false {
      normalized.saveFeedbackSoundID = SaveFeedbackSound.default.id
    }
    return normalized
  }
}
