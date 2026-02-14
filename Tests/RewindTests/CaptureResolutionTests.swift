import XCTest
@testable import Rewind

final class CaptureResolutionTests: XCTestCase {
  func testAlignedSizeRoundsDownToEvenDimensions() {
    let resolution = CaptureResolution(id: "test", label: "Test", width: 1919, height: 1079, isNative: false)
    let aligned = resolution.alignedSize
    XCTAssertEqual(Int(aligned.width), 1918)
    XCTAssertEqual(Int(aligned.height), 1078)
  }

  func testAlignedSizeMinimum2() {
    let resolution = CaptureResolution(id: "tiny", label: "Tiny", width: 1, height: 2, isNative: false)
    let aligned = resolution.alignedSize
    XCTAssertEqual(Int(aligned.width), 2)
    XCTAssertEqual(Int(aligned.height), 2)
  }

  func testNativeFactorySetsFields() {
    let resolution = CaptureResolution.native(width: 2560, height: 1440)
    XCTAssertEqual(resolution.id, "native")
    XCTAssertTrue(resolution.isNative)
    XCTAssertEqual(resolution.width, 2560)
    XCTAssertEqual(resolution.height, 1440)
  }
}
