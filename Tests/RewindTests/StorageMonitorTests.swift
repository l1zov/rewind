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
}
