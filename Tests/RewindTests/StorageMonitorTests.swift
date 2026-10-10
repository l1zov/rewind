import Foundation
@testable import Rewind
import XCTest

final class StorageMonitorTests: XCTestCase {
	private let gb: Int64 = 1024 * 1024 * 1024

	func testNoWarningWhenBothVolumesHaveRoom() {
		XCTAssertNil(StorageMonitor.warning(outputFreeBytes: 100 * gb, scratchFreeBytes: 50 * gb))
	}

	func testWarnsWhenOutputVolumeIsLow() throws {
		let message = try XCTUnwrap(StorageMonitor.warning(outputFreeBytes: 1 * gb, scratchFreeBytes: 50 * gb))
		XCTAssertTrue(message.hasPrefix("Low disk space"))
	}

	func testWarnsWhenOnlyTheLiveRecordingScratchVolumeIsLow() throws {
		// Clips go to a big external drive, but the rolling live segments are
		// written to the (nearly full) system volume.
		let message = try XCTUnwrap(StorageMonitor.warning(outputFreeBytes: 500 * gb, scratchFreeBytes: 1 * gb))
		XCTAssertTrue(message.contains("recording"), message)
	}

	func testUnknownCapacityDoesNotWarn() {
		XCTAssertNil(StorageMonitor.warning(outputFreeBytes: nil, scratchFreeBytes: nil))
		XCTAssertNil(StorageMonitor.warning(outputFreeBytes: nil, scratchFreeBytes: 50 * gb))
	}

	func testAvailableBytesForExistingAndMissingFolders() {
		let temp = FileManager.default.temporaryDirectory
		XCTAssertGreaterThan(StorageMonitor.availableBytes(forFolder: temp) ?? 0, 0)
		let missing = temp.appendingPathComponent("does/not/exist-\(UUID().uuidString)")
		XCTAssertGreaterThan(StorageMonitor.availableBytes(forFolder: missing) ?? 0, 0)
	}

	// - Refresh behaviour ---

	@MainActor
	func testOnlyReportsWhenTheWarningChanges() async throws {
		var reports: [String?] = []
		let samples = SampleBox([
			StorageMonitor.Sample(output: 100 * gb, scratch: 100 * gb),
			StorageMonitor.Sample(output: 100 * gb, scratch: 100 * gb),
			StorageMonitor.Sample(output: 1 * gb, scratch: 100 * gb),
			StorageMonitor.Sample(output: 1 * gb, scratch: 100 * gb),
		])
		let monitor = StorageMonitor(sampler: { samples.next() }) { reports.append($0) }

		for _ in 0 ..< 4 {
			monitor.refresh()
			try await Task.sleep(nanoseconds: 80_000_000)
		}

		XCTAssertEqual(reports.count, 2, "Healthy-then-healthy and low-then-low must not re-publish (it re-renders the menu)")
		XCTAssertNil(reports[0] ?? nil)
		XCTAssertTrue((reports[1] ?? "").hasPrefix("Low disk space"))
	}

	@MainActor
	func testSamplingHappensOffTheMainThread() async throws {
		let sawMainThread = SampleBox<Bool>([])
		let monitor = StorageMonitor(sampler: {
			sawMainThread.record(Thread.isMainThread)
			return StorageMonitor.Sample(output: nil, scratch: nil)
		}) { _ in }
		monitor.refresh()
		try await Task.sleep(nanoseconds: 150_000_000)
		XCTAssertEqual(sawMainThread.recorded, [false], "Volume capacity queries take ~40 ms and must not block the main thread")
	}

	func testTemporaryAndOutputFoldersOnOneVolumeAreQueriedOnce() {
		let temp = FileManager.default.temporaryDirectory
		XCTAssertTrue(StorageMonitor.sameVolume(temp, temp.appendingPathComponent("sub/dir")))
	}
}

private final class SampleBox<T: Sendable>: @unchecked Sendable {
	private let lock = NSLock()
	private var queue: [T]
	private var seen: [T] = []

	init(_ values: [T]) { queue = values }

	func next() -> T {
		lock.withLock { queue.count > 1 ? queue.removeFirst() : queue[0] }
	}

	func record(_ value: T) { lock.withLock { seen.append(value) } }
	var recorded: [T] { lock.withLock { seen } }
}
