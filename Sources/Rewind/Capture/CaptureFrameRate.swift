import Foundation

struct CaptureFrameRate: Hashable, Identifiable, Sendable {
  let framesPerSecond: Int
  let label: String
  let description: String

  var id: Int { framesPerSecond }

  static let fps30 = CaptureFrameRate(
    framesPerSecond: 30,
    label: "30 FPS",
    description: "Smaller files, good for mostly static screens"
  )

  static let fps60 = CaptureFrameRate(
    framesPerSecond: 60,
    label: "60 FPS",
    description: "Smoother motion, larger files"
  )

  static let options: [CaptureFrameRate] = [fps30, fps60]
  static let `default` = fps60
}
