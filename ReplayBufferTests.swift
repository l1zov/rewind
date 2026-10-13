import Foundation
@testable import Rewind
import XCTest

final class ReplayBufferTests: XCTestCase {
	private func makeTempDirectory() throws -> URL {
		let base = FileManager.default.temporaryDirectory
		let dir = base.appendingPathComponent("RewindTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private func createFile(in directory: URL, name: String) throws -> URL {
		let url = directory.appendingPathComponent(name)
		FileManager.default.createFile(atPath: url.path, contents: Data())
		return url
	}

	func testAppendSegmentPrunesOldestUnlockedSegments() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let url1 = try createFile(in: directory, name: "seg1.mov")
		let url2 = try createFile(in: directory, name: "seg2.mov")
		let url3 = try createFile(in: directory, name: "seg3.mov")

		let buffer = ReplayBuffer()
		_ = await buffer.appendSegment(url: url1, duration: 5, maxDuration: 10)
		_ = await buffer.appendSegment(url: url2, duration: 5, maxDuration: 10)
		let removed = await buffer.appendSegment(url: url3, duration: 5, maxDuration: 10)

		XCTAssertEqual(removed, [url1])
	}

	func testLatestSegmentsFiltersMissingFiles() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let existingURL = try createFile(in: directory, name: "existing.mov")
		let missingURL = directory.appendingPathComponent("missing.mov")

		let buffer = ReplayBuffer()
		_ = await buffer.appendSegment(url: existingURL, duration: 5, maxDuration: 20)
		_ = await buffer.appendSegment(url: missingURL, duration: 5, maxDuration: 20)

		let segments = await buffer.latestSegments(totalDuration: 20)
		XCTAssertEqual(segments.count, 1)
		XCTAssertEqual(segments.first?.url, existingURL)
	}

	func testLockedSegmentsAreNotPrunedUntilUnlocked() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let url1 = try createFile(in: directory, name: "seg1.mov")
		let url2 = try createFile(in: directory, name: "seg2.mov")
		let url3 = try createFile(in: directory, name: "seg3.mov")
		let url4 = try createFile(in: directory, name: "seg4.mov")

		let buffer = ReplayBuffer()
		_ = await buffer.appendSegment(url: url1, duration: 5, maxDuration: 10)
		_ = await buffer.appendSegment(url: url2, duration: 5, maxDuration: 10)

		let locked = await buffer.latestSegments(totalDuration: 10)
		XCTAssertEqual(locked.map(\.url), [url1, url2])

		let removedWhileLocked = await buffer.appendSegment(url: url3, duration: 5, maxDuration: 10)
		XCTAssertTrue(removedWhileLocked.isEmpty)

		await buffer.unlockSegments(locked)
		let removedAfterUnlock = await buffer.appendSegment(url: url4, duration: 5, maxDuration: 10)
		XCTAssertEqual(removedAfterUnlock, [url1, url2])
	}

	func testPrunePreservesOrderAndKeepsNewestWhenOldSegmentsAreLocked() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let urls = try (1 ... 5).map { try createFile(in: directory, name: "seg\($0).mov") }

		let buffer = ReplayBuffer()
		_ = await buffer.appendSegment(url: urls[0], duration: 5, maxDuration: 100)
		_ = await buffer.appendSegment(url: urls[1], duration: 5, maxDuration: 100)

		// Lock the two oldest segments (simulating an in-flight export holding them).
		let locked = await buffer.latestSegments(totalDuration: 10)
		XCTAssertEqual(locked.map(\.url), [urls[0], urls[1]])

		// Append newer segments with a tight budget. Locked segments must always be kept,
		// and the unlocked segments removed must be the oldest ones, preserving order.
		_ = await buffer.appendSegment(url: urls[2], duration: 5, maxDuration: 5)
		_ = await buffer.appendSegment(url: urls[3], duration: 5, maxDuration: 5)
		_ = await buffer.appendSegment(url: urls[4], duration: 5, maxDuration: 5)

		// Locked oldest segments are still present; the newest segment is retained;
		// and remaining segments stay in chronological order with no gaps/reordering.
		let remaining = await buffer.latestSegments(totalDuration: 1000)
		XCTAssertTrue(remaining.contains(where: { $0.url == urls[0] }))
		XCTAssertTrue(remaining.contains(where: { $0.url == urls[1] }))
		XCTAssertTrue(remaining.contains(where: { $0.url == urls[4] }))

		let remainingURLs = remaining.map(\.url)
		let expectedOrder = urls.filter { remainingURLs.contains($0) }
		XCTAssertEqual(remainingURLs, expectedOrder, "segments must remain in chronological order")
	}
}
