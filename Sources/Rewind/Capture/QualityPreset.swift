import Foundation

struct QualityPreset: Hashable, Identifiable, Sendable {
  let id: String
  let label: String
  let description: String
  /// quality value used by HEVC presets 
  /// the lossless and near_lossless presets use dedicated codec paths and do not rely on these values
  let quality: Float

  static let presets: [QualityPreset] = [
    QualityPreset(
      id: "lossless",
      label: "Lossless",
      description: "Perfect quality, largest files",
      quality: 1.0
    ),
    QualityPreset(
      id: "near_lossless",
      label: "Near Lossless",
      description: "Extremely high quality, much larger files",
      quality: 0.95
    ),
    QualityPreset(
      id: "ultra",
      label: "Ultra",
      description: "Ultra quality, larger files",
      quality: 0.90
    ),
    QualityPreset(
      id: "high",
      label: "High",
      description: "Very high quality for screen content",
      quality: 0.78
    ),
    QualityPreset(
      id: "balanced",
      label: "Balanced",
      description: "Good quality, really good file size",
      quality: 0.62
    ),
    QualityPreset(
      id: "efficient",
      label: "Efficient",
      description: "Some would say a bit too efficient",
      quality: 0.35
    )
  ]

  static let `default` = presets.first { $0.id == "high" }!
}
