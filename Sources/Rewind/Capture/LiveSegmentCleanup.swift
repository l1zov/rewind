import Foundation

/// The rolling live segments (`Rewind_live_*.mov`, up to ~5 minutes of video) are
/// only deleted when capture is stopped, so a quit or crash would leave them in
/// the temp folder for days. Sweep them at launch and on quit.
enum LiveSegmentCleanup {
	static let prefix = "Rewind_live_"

	static var defaultFolder: URL {
		FileManager.default.temporaryDirectory.appendingPathComponent("Rewind", isDirectory: true)
	}

	/// - Returns: how many leftover segment files were removed.
	@discardableResult
	static func removeAll(in folder: URL = defaultFolder) -> Int {
		let fileManager = FileManager.default
		guard let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
			return 0
		}
		var removed = 0
		for url in urls where url.lastPathComponent.hasPrefix(prefix) {
			if (try? fileManager.removeItem(at: url)) != nil { removed += 1 }
		}
		return removed
	}
}
