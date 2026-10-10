import Foundation

/// Finds the current Roblox session by reading the newest log incrementally.
///
/// The detector polls every 10 s while recording, and Roblox logs grow into the
/// megabytes. Reading and regex-scanning the whole file each time wasted CPU and
/// memory for no benefit, so this remembers how far it has read and only parses
/// what was appended since. The first read of a big log is limited to its tail.
final class RobloxLogTail: @unchecked Sendable {
	private let initialWindow: Int
	private let lock = NSLock()
	private var path: String?
	private var offset: UInt64 = 0
	private var session: RobloxGameDetector.Session?
	private var totalBytesRead = 0

	/// Total bytes read from disk so far (for tests and diagnostics).
	var bytesRead: Int { lock.withLock { totalBytesRead } }

	init(initialWindow: Int = 256 * 1024) {
		self.initialWindow = initialWindow
	}

	func latestSession(in url: URL) -> RobloxGameDetector.Session? {
		lock.lock()
		defer { lock.unlock() }

		guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value
		else { return session }

		// A different file, or one that shrank (rotated / rewritten): start over.
		if path != url.path || size < offset {
			path = url.path
			session = nil
			offset = size > UInt64(initialWindow) ? size - UInt64(initialWindow) : 0
		}
		guard size > offset else { return session }

		guard let handle = try? FileHandle(forReadingFrom: url) else { return session }
		defer { try? handle.close() }
		guard (try? handle.seek(toOffset: offset)) != nil,
		      let data = try? handle.read(upToCount: Int(size - offset)),
		      !data.isEmpty
		else { return session }
		totalBytesRead += data.count

		// Only consume whole lines, so a join line that is still being written is
		// picked up complete on the next poll instead of being cut in half.
		guard let lastNewline = data.lastIndex(of: 0x0A) else { return session }
		let complete = data[data.startIndex ... lastNewline]
		offset += UInt64(complete.count)

		if let found = RobloxGameDetector.parseSession(in: String(decoding: complete, as: UTF8.self)) {
			session = found
		}
		return session
	}
}
