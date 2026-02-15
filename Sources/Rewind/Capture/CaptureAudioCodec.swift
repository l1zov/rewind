import Foundation

struct CaptureAudioCodec: Hashable, Identifiable, Sendable {
  let id: String
  let label: String
  let description: String

  static let linearPCM = CaptureAudioCodec(
    id: "pcm",
    label: "Linear PCM",
    description: "Uncompressed audio, largest files"
  )

  static let appleLossless = CaptureAudioCodec(
    id: "alac",
    label: "Apple Lossless",
    description: "Lossless compression, smaller files"
  )

  static let aac = CaptureAudioCodec(
    id: "aac",
    label: "AAC",
    description: "Compressed audio, smallest files"
  )

  static let options: [CaptureAudioCodec] = [.linearPCM, .appleLossless, .aac]
  static let `default` = appleLossless
}
