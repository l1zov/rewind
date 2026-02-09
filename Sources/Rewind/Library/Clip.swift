import Foundation

struct Clip: Identifiable, Codable {
  let id: UUID
  let url: URL
  let createdAt: Date
  let duration: TimeInterval
  var tags: [String]

  init(id: UUID, url: URL, createdAt: Date, duration: TimeInterval, tags: [String] = []) {
    self.id = id
    self.url = url
    self.createdAt = createdAt
    self.duration = duration
    self.tags = tags
  }

  init(url: URL, duration: TimeInterval, tags: [String] = []) {
    self.id = UUID()
    self.url = url
    self.createdAt = Date()
    self.duration = duration
    self.tags = tags
  }
}
