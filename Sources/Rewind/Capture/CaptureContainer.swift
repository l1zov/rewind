import AVFoundation
import Foundation

struct CaptureContainer: Hashable, Identifiable, Sendable {
  let id: String
  let label: String
  let fileExtension: String
  let avFileType: AVFileType

  static let mov = CaptureContainer(
    id: "mov",
    label: "MOV",
    fileExtension: "mov",
    avFileType: .mov
  )

  static let mp4 = CaptureContainer(
    id: "mp4",
    label: "MP4",
    fileExtension: "mp4",
    avFileType: .mp4
  )

  static let options: [CaptureContainer] = [.mov, .mp4]
  static let `default` = mov
}
