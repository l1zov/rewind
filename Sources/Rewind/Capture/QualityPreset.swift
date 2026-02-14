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
      id: "competitive",
      label: "Competitive",
      description: "Sharp enough for gameplay, smallest files",
      bitsPerPixel: 0.045,
      minBitrateMbps: 4,
      maxBitrateMbps: 40
    ),
    QualityPreset(
      id: "performance",
      label: "Performance",
      description: "More detail while staying storage-friendly",
      bitsPerPixel: 0.055,
      minBitrateMbps: 6,
      maxBitrateMbps: 50
    ),
    QualityPreset(
      id: "balanced",
      label: "Balanced",
      description: "Best mix of clarity and size",
      bitsPerPixel: 0.065,
      minBitrateMbps: 8,
      maxBitrateMbps: 60
    ),
    QualityPreset(
      id: "high",
      label: "High",
      description: "High clarity for fast gameplay",
      bitsPerPixel: 0.078,
      minBitrateMbps: 10,
      maxBitrateMbps: 75
    ),
    QualityPreset(
      id: "ultra",
      label: "Ultra",
      description: "Near-max quality with larger files",
      bitsPerPixel: 0.092,
      minBitrateMbps: 14,
      maxBitrateMbps: 90
    ),
    QualityPreset(
      id: "max",
      label: "Max",
      description: "Maximum practical quality",
      bitsPerPixel: 0.110,
      minBitrateMbps: 18,
      maxBitrateMbps: 110
    )
  ]

  static let `default` = presets.first { $0.id == "balanced" }!
}
