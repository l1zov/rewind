import CoreGraphics
import Foundation
import XCTest
@testable import Rewind

final class ReplayWriterTests: XCTestCase {
  private func makeTempDirectory() throws -> URL {
    let base = FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("ReplayWriterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func assertCaptureError(_ error: Error, is expected: CaptureError, file: StaticString = #filePath, line: UInt = #line) {
    guard let captureError = error as? CaptureError else {
      XCTFail("Expected CaptureError, got \(type(of: error))", file: file, line: line)
      return
    }

    switch (captureError, expected) {
    case (.writerUnavailable, .writerUnavailable),
         (.noFramesCaptured, .noFramesCaptured),
         (.exportFailed, .exportFailed),
         (.saveInProgress, .saveInProgress),
         (.invalidDuration, .invalidDuration),
         (.noDisplay, .noDisplay),
         (.noAudioDevice, .noAudioDevice):
      break
    default:
      XCTFail("Expected \(expected), got \(captureError)", file: file, line: line)
    }
  }

  func testFinishWritingWithoutConfigureThrowsWriterUnavailable() async {
    let writer = ReplayWriter(queue: DispatchQueue(label: "ReplayWriterTests.noConfig"))

    do {
      _ = try await writer.finishWriting()
      XCTFail("Expected finishWriting to throw")
    } catch {
      assertCaptureError(error, is: .writerUnavailable)
    }
  }

  func testConfigureRejectsNonFileOutputURL() {
    let writer = ReplayWriter(queue: DispatchQueue(label: "ReplayWriterTests.invalidURL"))
    let nonFileURL = URL(string: "https://example.com/output.mov")!

    XCTAssertThrowsError(
      try writer.configure(
        outputURL: nonFileURL,
        videoSize: CGSize(width: 1280, height: 720),
        includeAudio: false,
        audioSettings: nil
      )
    ) { error in
      self.assertCaptureError(error, is: .exportFailed)
    }
  }

  func testFinishWritingWithoutFramesThrowsNoFramesCaptured() async throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let writer = ReplayWriter(queue: DispatchQueue(label: "ReplayWriterTests.noFrames"))
    let outputURL = directory.appendingPathComponent("segment.mov")
    try writer.configure(
      outputURL: outputURL,
      videoSize: CGSize(width: 1280, height: 720),
      includeAudio: false,
      audioSettings: nil
    )

    do {
      _ = try await writer.finishWriting()
      XCTFail("Expected finishWriting to throw")
    } catch {
      assertCaptureError(error, is: .noFramesCaptured)
    }
  }
}
