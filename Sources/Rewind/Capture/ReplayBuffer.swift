import Foundation

struct ReplaySegment: Identifiable, Codable {
	let id: UUID
	let url: URL
	let duration: TimeInterval
	let createdAt: Date

	init(url: URL, duration: TimeInterval) {
		id = UUID()
		self.url = url
		self.duration = duration
		createdAt = Date()
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
	/// URLs of every buffered segment, oldest first. Read-only: unlike
	/// `latestSegments` it neither prunes missing files nor locks anything.
	func segmentURLs() -> [URL] {
		segments.map(\.url)
	}

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
		// walk newest-first to determine the exact set of segments to keep, so the
		// removal pass evicts precisely the oldest unlocked segments beyond the
		// duration budget. Tracking IDs (rather than a count) keeps this correct
		// even when locked segments sit in the middle of the buffer.
		var total: TimeInterval = 0
		var keepIDs: Set<UUID> = []
		for segment in segments.reversed() {
			// always keep locked segments
			if lockedSegmentIDs.contains(segment.id) {
				keepIDs.insert(segment.id)
				continue
			}
			if total >= maxDuration { continue }
			total += segment.duration
			keepIDs.insert(segment.id)
		}
		guard keepIDs.count < segments.count else { return [] }

		var toRemove: [URL] = []
		var newSegments: [ReplaySegment] = []
		for segment in segments {
			if keepIDs.contains(segment.id) {
				newSegments.append(segment)
			} else {
				toRemove.append(segment.url)
			}
		}
		segments = newSegments
		return toRemove
	}
}
