import Foundation

enum ClipFileReplacer {
	/// Swaps `replacement` in for the clip at `url` without a window where
	/// neither exists. `replaceItemAt` is atomic on one volume and, across
	/// volumes (e.g. a clips folder on an external drive), only removes the
	/// original after the new contents are fully in place, so a full disk or
	/// an ejected drive mid-copy leaves the original clip intact.
	static func replace(at url: URL, with replacement: URL) throws {
		_ = try FileManager.default.replaceItemAt(url, withItemAt: replacement)
	}
}
