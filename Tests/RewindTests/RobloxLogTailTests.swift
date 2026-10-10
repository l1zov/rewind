import Foundation
@testable import Rewind
import XCTest

final class RobloxLogTailTests: XCTestCase {
	private func makeFolder() throws -> URL {
		let folder = FileManager.default.temporaryDirectory
			.appendingPathComponent("RobloxLogTailTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return folder
	}

	private func append(_ text: String, to url: URL) throws {
		if let handle = try? FileHandle(forWritingTo: url) {
			defer { try? handle.close() }
			try handle.seekToEnd()
			try handle.write(contentsOf: Data(text.utf8))
		} else {
			try Data(text.utf8).write(to: url)
		}
	}

	private let join = "2026-10-07T10:00:00.000Z,0.1,0,6 Joining game 'job-abc' place 1818 at 1.2.3.4\n"

	func testFindsTheMostRecentSession() throws {
		let folder = try makeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let log = folder.appendingPathComponent("a.log")
		try append("noise\n" + join + "more noise\n", to: log)

		let tail = RobloxLogTail()
		XCTAssertEqual(tail.latestSession(in: log), RobloxGameDetector.Session(placeID: "1818", jobID: "job-abc"))
	}

	func testReadsOnlyNewBytesOnLaterPolls() throws {
		let folder = try makeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let log = folder.appendingPathComponent("a.log")
		try append(String(repeating: "filler line of log text\n", count: 20_000) + join, to: log)
		let tail = RobloxLogTail(initialWindow: 1 << 20)

		_ = tail.latestSession(in: log)
		let firstRead = tail.bytesRead
		XCTAssertGreaterThan(firstRead, 0)

		_ = tail.latestSession(in: log)
		XCTAssertEqual(tail.bytesRead, firstRead, "Nothing was appended, so nothing should be read")

		try append("2026-10-07T10:05:00.000Z,0.1,0,6 Joining game 'job-new' place 4242 at 5.6.7.8\n", to: log)
		XCTAssertEqual(tail.latestSession(in: log), RobloxGameDetector.Session(placeID: "4242", jobID: "job-new"))
		XCTAssertLessThan(tail.bytesRead - firstRead, 500, "Only the appended line should be read")
	}

	func testKeepsTheEarlierSessionWhenNothingNewIsJoined() throws {
		let folder = try makeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let log = folder.appendingPathComponent("a.log")
		try append(join, to: log)
		let tail = RobloxLogTail()
		_ = tail.latestSession(in: log)

		try append("just some more output\n", to: log)
		XCTAssertEqual(tail.latestSession(in: log)?.placeID, "1818")
	}

	func testHugeLogIsReadFromTheTailOnly() throws {
		let folder = try makeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let log = folder.appendingPathComponent("big.log")
		// ~4 MB of filler, then the join line near the end
		try append(String(repeating: "x filler line xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n", count: 80_000) + join, to: log)

		let tail = RobloxLogTail(initialWindow: 256 * 1024)
		XCTAssertEqual(tail.latestSession(in: log)?.placeID, "1818")
		XCTAssertLessThanOrEqual(tail.bytesRead, 256 * 1024 + 4096, "The first read must be bounded, not the whole 4 MB")
	}

	func testALineSplitAcrossTwoPollsIsStillFound() throws {
		let folder = try makeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let log = folder.appendingPathComponent("a.log")
		let tail = RobloxLogTail()
		try append("start\n2026-10-07T10:00:00.000Z,0.1,0,6 Joining game 'job-s", to: log)
		XCTAssertNil(tail.latestSession(in: log))

		try append("plit' place 777 at 1.1.1.1\n", to: log)
		XCTAssertEqual(tail.latestSession(in: log), RobloxGameDetector.Session(placeID: "777", jobID: "job-split"))
	}

	func testANewOrTruncatedFileStartsFresh() throws {
		let folder = try makeFolder()
		defer { try? FileManager.default.removeItem(at: folder) }
		let first = folder.appendingPathComponent("first.log")
		let second = folder.appendingPathComponent("second.log")
		try append(join, to: first)
		try append("2026-10-07T11:00:00.000Z,0.1,0,6 Joining game 'job-2' place 99 at 9.9.9.9\n", to: second)
		let tail = RobloxLogTail()

		XCTAssertEqual(tail.latestSession(in: first)?.placeID, "1818")
		XCTAssertEqual(tail.latestSession(in: second)?.placeID, "99", "A different log file must not reuse the old session")

		try Data("fresh\n".utf8).write(to: second) // truncated and rewritten
		XCTAssertNil(tail.latestSession(in: second), "A truncated log must not keep the old session")
	}
}
