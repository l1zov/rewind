import Foundation
@testable import Rewind
import XCTest

final class ClipFileReplacerTests: XCTestCase {
	private func makeFolder() throws -> URL {
		let folder = FileManager.default.temporaryDirectory
			.appendingPathComponent("ClipFileReplacerTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return folder
	}

	func testReplacesOriginalContents() throws {
		let folder = try makeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let original = folder.appendingPathComponent("clip.mov")
		let replacement = folder.appendingPathComponent("trimmed.mov")
		try Data("old".utf8).write(to: original)
		try Data("new".utf8).write(to: replacement)

		try ClipFileReplacer.replace(at: original, with: replacement)

		XCTAssertEqual(try Data(contentsOf: original), Data("new".utf8))
		XCTAssertFalse(FileManager.default.fileExists(atPath: replacement.path))
	}

	func testMissingReplacementLeavesOriginalUntouched() throws {
		let folder = try makeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let original = folder.appendingPathComponent("clip.mov")
		try Data("old".utf8).write(to: original)

		XCTAssertThrowsError(
			try ClipFileReplacer.replace(at: original, with: folder.appendingPathComponent("never-written.mov")))

		XCTAssertEqual(try Data(contentsOf: original), Data("old".utf8))
	}
}
