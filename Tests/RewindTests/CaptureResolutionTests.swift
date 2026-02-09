import XCTest
@testable import Rewind

final class CaptureResolutionTests: XCTestCase {
  func testAlignedSizeRoundsDownToMultipleOf16() {
    let resolution = CaptureResolution(id: "test", label: "Test", width: 1919, height: 1079, isNative: false)
    let aligned = resolution.alignedSize
    XCTAssertEqual(Int(aligned.width), 1904)
    XCTAssertEqual(Int(aligned.height), 1072)
  }

  func testAlignedSizeMinimum16() {
    let resolution = CaptureResolution(id: "tiny", label: "Tiny", width: 1, height: 2, isNative: false)
    let aligned = resolution.alignedSize
    XCTAssertEqual(Int(aligned.width), 16)
    XCTAssertEqual(Int(aligned.height), 16)
  }

  func testNativeFactorySetsFields() {
    let resolution = CaptureResolution.native(width: 2560, height: 1440)
    XCTAssertEqual(resolution.id, "native")
    XCTAssertTrue(resolution.isNative)
    XCTAssertEqual(resolution.width, 2560)
    XCTAssertEqual(resolution.height, 1440)
  }
}
