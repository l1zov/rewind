import Foundation
import XCTest
@testable import Rewind

private actor TestClipStore: ClipStore {
  private let fetchResult: Result<[Clip], Error>
  private var saved: [Clip] = []

  init(fetchResult: Result<[Clip], Error>) {
    self.fetchResult = fetchResult
  }

  func fetchAll() async throws -> [Clip] {
    try fetchResult.get()
  }

  func save(clip: Clip) async throws -> Clip {
    saved.append(clip)
    return clip
  }

  func savedClips() -> [Clip] {
    saved
  }
}

private enum ClipLibraryTestError: Error {
  case fetchFailed
}

@MainActor
final class ClipLibraryTests: XCTestCase {
  private func waitForLoadCompletion(_ library: ClipLibrary, timeout: TimeInterval = 1.0) async {
    let deadline = Date().addingTimeInterval(timeout)
    while library.isLoading && Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertFalse(library.isLoading, "Expected initial clip load to complete")
  }

  private func makeClipFileInMovies() throws -> URL {
    let fm = FileManager.default
    let moviesFolder = fm.urls(for: .moviesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("Rewind", isDirectory: true)
      ?? fm.temporaryDirectory.appendingPathComponent("Rewind", isDirectory: true)
    try fm.createDirectory(at: moviesFolder, withIntermediateDirectories: true)

    let url = moviesFolder.appendingPathComponent("ClipLibraryTests-\(UUID().uuidString).mov")
    fm.createFile(atPath: url.path, contents: Data([1, 2, 3]))
    return url
  }

  func testInitLoadsClipsFromStore() async {
    let expectedClip = Clip(url: URL(fileURLWithPath: "/tmp/clip.mov"), duration: 12)
    let store = TestClipStore(fetchResult: .success([expectedClip]))

    let library = ClipLibrary(store: store)
    await waitForLoadCompletion(library)

    XCTAssertNil(library.loadError)
    XCTAssertEqual(library.clips.count, 1)
    XCTAssertEqual(library.clips.first?.id, expectedClip.id)
    XCTAssertEqual(library.clips.first?.url, expectedClip.url)
  }

  func testInitSetsLoadErrorWhenFetchFails() async {
    let store = TestClipStore(fetchResult: .failure(ClipLibraryTestError.fetchFailed))

    let library = ClipLibrary(store: store)
    await waitForLoadCompletion(library)

    XCTAssertTrue(library.clips.isEmpty)
    XCTAssertNotNil(library.loadError)
  }

  func testAddClipSavesToStoreAndPublishedCollection() async throws {
    let store = TestClipStore(fetchResult: .success([]))
    let library = ClipLibrary(store: store)
    await waitForLoadCompletion(library)

    let sourceURL = try makeClipFileInMovies()
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let clip = try await library.addClip(url: sourceURL, duration: 27.5)

    XCTAssertEqual(clip.url, sourceURL)
    XCTAssertEqual(clip.duration, 27.5)
    XCTAssertEqual(library.clips.count, 1)
    XCTAssertEqual(library.clips.first?.id, clip.id)

    let saved = await store.savedClips()
    XCTAssertEqual(saved.count, 1)
    XCTAssertEqual(saved.first?.id, clip.id)
    XCTAssertEqual(saved.first?.duration, 27.5)
  }
}
