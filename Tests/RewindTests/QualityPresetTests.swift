import XCTest
@testable import Rewind

final class QualityPresetTests: XCTestCase {
  func testDefaultIsHigh() {
    XCTAssertEqual(QualityPreset.default.id, "high")
  }

  func testPresetsHaveUniqueIds() {
    let ids = QualityPreset.presets.map(\.id)
    XCTAssertEqual(Set(ids).count, ids.count)
  }

  func testPresetsStayWithinExpectedRange() {
    for preset in QualityPreset.presets {
      XCTAssertGreaterThanOrEqual(preset.quality, 0.0)
      XCTAssertLessThanOrEqual(preset.quality, 1.0)
      XCTAssertFalse(preset.label.isEmpty)
    }
  }
}
