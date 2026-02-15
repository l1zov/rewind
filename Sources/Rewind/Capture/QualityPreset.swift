import Foundation

struct QualityPreset: Hashable, Identifiable, Sendable {
  let id: String
  let label: String
  let description: String
  /// bpp/f used to compute bitrate from output resolution and fps
  let bitsPerPixel: Double
  let minBitrateMbps: Double
  let maxBitrateMbps: Double

  static let presets: [QualityPreset] = [
    QualityPreset(
      id: "very-low",
      label: "Very Low",
      description: "Smallest files, softest detail",
      bitsPerPixel: 0.045,
      minBitrateMbps: 4,
      maxBitrateMbps: 40
    ),
    QualityPreset(
      id: "low",
      label: "Low",
      description: "Smaller files with basic detail",
      bitsPerPixel: 0.055,
      minBitrateMbps: 6,
      maxBitrateMbps: 50
    ),
    QualityPreset(
      id: "medium",
      label: "Medium",
      description: "Balanced quality and file size",
      bitsPerPixel: 0.065,
      minBitrateMbps: 8,
      maxBitrateMbps: 60
    ),
    QualityPreset(
      id: "high",
      label: "High",
      description: "Sharper detail with larger files",
      bitsPerPixel: 0.078,
      minBitrateMbps: 10,
      maxBitrateMbps: 75
    ),
    QualityPreset(
      id: "very-high",
      label: "Very High",
      description: "High clarity for fast motion",
      bitsPerPixel: 0.092,
      minBitrateMbps: 14,
      maxBitrateMbps: 90
    ),
    QualityPreset(
      id: "maximum",
      label: "Maximum",
      description: "Best quality, largest files",
      bitsPerPixel: 0.110,
      minBitrateMbps: 18,
      maxBitrateMbps: 110
    )
  ]

  static let `default` = presets.first { $0.id == "medium" }!
}
