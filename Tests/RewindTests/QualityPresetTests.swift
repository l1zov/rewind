import XCTest
@testable import Rewind

final class QualityPresetTests: XCTestCase {
  func testDefaultIsBalanced() {
    XCTAssertEqual(QualityPreset.default.id, "balanced")
  }

  func testPresetsHaveUniqueIds() {
    let ids = QualityPreset.presets.map(\.id)
    XCTAssertEqual(Set(ids).count, ids.count)
  }

  func testPresetLadderHasSixExpectedTiers() {
    XCTAssertEqual(
      QualityPreset.presets.map(\.id),
      ["competitive", "performance", "balanced", "high", "ultra", "max"]
    )
  }

  func testPresetsHaveValidBitrateConfig() {
    for preset in QualityPreset.presets {
      XCTAssertGreaterThan(preset.bitsPerPixel, 0)
      XCTAssertGreaterThan(preset.minBitrateMbps, 0)
      XCTAssertGreaterThanOrEqual(preset.maxBitrateMbps, preset.minBitrateMbps)
      XCTAssertFalse(preset.label.isEmpty)
    }
  }
}
