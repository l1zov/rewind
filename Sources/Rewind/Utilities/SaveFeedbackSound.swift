import Foundation

struct SaveFeedbackSound: Hashable, Identifiable, Sendable {
  let id: String
  let label: String
  let systemSoundName: String

  static let cling = SaveFeedbackSound(
    id: "cling",
    label: "Cling",
    systemSoundName: "Glass"
  )

  static let ping = SaveFeedbackSound(
    id: "ping",
    label: "Ping",
    systemSoundName: "Ping"
  )

  static let pop = SaveFeedbackSound(
    id: "pop",
    label: "Pop",
    systemSoundName: "Pop"
  )

  static let options: [SaveFeedbackSound] = [.cling, .ping, .pop]
  static let `default` = cling
}
