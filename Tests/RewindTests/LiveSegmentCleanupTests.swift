import Foundation
@testable import Rewind
import XCTest

final class LiveSegmentCleanupTests: XCTestCase {
	private func makeFolder() throws -> URL {
		let folder = FileManager.default.temporaryDirectory
			.appendingPathComponent("LiveSegmentCleanupTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return folder
	}

	func testRemovesOnlyLeftoverLiveSegments() throws {
		let folder = try makeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		for name in ["Rewind_live_A.mov", "Rewind_live_B.mov", "keep.txt", "Rewind_export.mp4"] {
			try Data("x".utf8).write(to: folder.appendingPathComponent(name))
		}

		let removed = LiveSegmentCleanup.removeAll(in: folder)

		XCTAssertEqual(removed, 2)
		let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
		XCTAssertEqual(left, ["Rewind_export.mp4", "keep.txt"])
	}

	func testMissingFolderIsFine() {
		let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
		XCTAssertEqual(LiveSegmentCleanup.removeAll(in: missing), 0)
	}

	func testDefaultFolderMatchesWhereSegmentsAreWritten() {
		XCTAssertEqual(
			LiveSegmentCleanup.defaultFolder,
			FileManager.default.temporaryDirectory.appendingPathComponent("Rewind", isDirectory: true))
	}
}
