import Defaults
import Foundation

enum ClipStorageLocation {
	static let defaultFolder: URL =
		FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?
		.appendingPathComponent("Rewind", isDirectory: true)
		?? FileManager.default.temporaryDirectory.appendingPathComponent(
			"Rewind", isDirectory: true)

	static func folder(outputDirectoryPath: String?) -> URL {
		guard let outputDirectoryPath else { return defaultFolder }
		return URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
	}

	static func current() -> URL {
		folder(outputDirectoryPath: Defaults[.outputDirectoryPath])
	}
}
