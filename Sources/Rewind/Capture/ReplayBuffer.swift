import Foundation

struct ReplaySegment: Identifiable, Codable {
  let id: UUID
  let url: URL
  let duration: TimeInterval
  let createdAt: Date

  init(url: URL, duration: TimeInterval) {
    self.id = UUID()
    self.url = url
    self.duration = duration
    self.createdAt = Date()
  }

  /// check if the underlying file still exists
  var fileExists: Bool {
    FileManager.default.fileExists(atPath: url.path)
  }
}

actor ReplayBuffer {
  private var segments: [ReplaySegment] = []
  /// segments currently being used for export (protected from pruning)
  private var lockedSegmentIDs: Set<UUID> = []

  func appendSegment(url: URL, duration: TimeInterval, maxDuration: TimeInterval) -> [URL] {
    segments.append(ReplaySegment(url: url, duration: duration))
    return prune(maxDuration: maxDuration)
  }

  /// returns segments for the requested duration, filtering out any with missing files.
  /// locks the returned segments to prevent pruning during export.
  func latestSegments(totalDuration: TimeInterval) -> [ReplaySegment] {
    // first, clean up any segments with missing files
    segments.removeAll { !$0.fileExists && !lockedSegmentIDs.contains($0.id) }

    var remaining = totalDuration
    var results: [ReplaySegment] = []
    for segment in segments.reversed() {
      guard remaining > 0 else { break }
      guard segment.fileExists else { continue }
      results.append(segment)
      remaining -= segment.duration
    }
    let validSegments = results.reversed()

    // lock these segments to prevent pruning during export
    for segment in validSegments {
      lockedSegmentIDs.insert(segment.id)
    }

    return Array(validSegments)
  }

  /// unlocks segments after export completes, allowing them to be pruned
  func unlockSegments(_ segments: [ReplaySegment]) {
    for segment in segments {
      lockedSegmentIDs.remove(segment.id)
    }
  }

  func clear() -> [URL] {
    let urls = segments.map(\.url)
    segments.removeAll()
    lockedSegmentIDs.removeAll()
    return urls
  }

  private func prune(maxDuration: TimeInterval) -> [URL] {
    guard maxDuration > 0 else { return [] }
    var total: TimeInterval = 0
    var keepCount = 0
    for segment in segments.reversed() {
      // always keep locked segments
      if lockedSegmentIDs.contains(segment.id) {
        keepCount += 1
        continue
      }
      if total >= maxDuration { break }
      total += segment.duration
      keepCount += 1
    }
    guard keepCount < segments.count else { return [] }
    // only remove unlocked segments
    var toRemove: [URL] = []
    var removeCount = segments.count - keepCount
    var newSegments: [ReplaySegment] = []
    for segment in segments {
      if removeCount > 0 && !lockedSegmentIDs.contains(segment.id) {
        toRemove.append(segment.url)
        removeCount -= 1
      } else {
        newSegments.append(segment)
      }
    }
    segments = newSegments
    return toRemove
  }
}
