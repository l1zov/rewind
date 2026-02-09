import Foundation
import XCTest
@testable import Rewind

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
}
