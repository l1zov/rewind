import Foundation
import SQLite3

@MainActor
final class ClipLibrary: ObservableObject {
  @Published private(set) var clips: [Clip] = []
  @Published private(set) var isLoading = true
  @Published private(set) var loadError: Error?

  private let store: ClipStore
  private var loadTask: Task<Void, Never>?

  init(store: ClipStore = SQLiteClipStore()) {
    self.store = store
    loadTask = Task { [weak self] in
      await self?.load()
    }
  }

  deinit {
    loadTask?.cancel()
  }

  func addClip(url: URL, duration: TimeInterval) async throws -> Clip {
    let exportedURL = try ensureExported(url: url)
    var clip = Clip(url: exportedURL, duration: duration)
    clip = try await store.save(clip: clip)
    clips.append(clip)
    return clip
  }

  private func load() async {
    isLoading = true
    loadError = nil
    do {
      clips = try await store.fetchAll()
    } catch {
      loadError = error
      clips = []
      AppLog.error(.library, "ClipLibrary: failed to load clips:", error)
    }
    isLoading = false
  }

  private func ensureExported(url: URL) throws -> URL {
    let fm = FileManager.default
    let moviesFolder = fm.urls(for: .moviesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("Rewind", isDirectory: true)
      ?? fm.temporaryDirectory.appendingPathComponent("Rewind", isDirectory: true)
    try fm.createDirectory(at: moviesFolder, withIntermediateDirectories: true)

    if url.path.hasPrefix(moviesFolder.path + "/") {
      return url
    }

    let baseName = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
    let uniqueName = "\(baseName)_\(Int(Date().timeIntervalSince1970)).\(ext)"
    let targetURL = moviesFolder.appendingPathComponent(uniqueName)

    do {
      try fm.moveItem(at: url, to: targetURL)
    } catch {
      try fm.copyItem(at: url, to: targetURL)
    }
    return targetURL
  }
}

protocol ClipStore: Actor {
  func fetchAll() async throws -> [Clip]
  func save(clip: Clip) async throws -> Clip
}

enum ClipStoreError: Error {
  case sqliteFailure(String)
}

actor SQLiteClipStore: ClipStore {
  private final class SQLiteHandle: @unchecked Sendable {
    let pointer: OpaquePointer?

    init(pointer: OpaquePointer?) {
      self.pointer = pointer
    }

    deinit {
      if let pointer {
        sqlite3_close(pointer)
      }
    }
  }

  private let dbURL: URL
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder
  private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private let db: SQLiteHandle

  init(fileManager: FileManager = .default) {
    decoder = JSONDecoder()
    encoder = JSONEncoder()
    let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    let folder = base?.appendingPathComponent("Rewind", isDirectory: true)
      ?? fileManager.temporaryDirectory.appendingPathComponent("Rewind", isDirectory: true)
    dbURL = folder.appendingPathComponent("clips.sqlite")
    try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    let openedDB = Self.openDB(at: dbURL)
    db = SQLiteHandle(pointer: openedDB)
    Self.createSchema(db: openedDB)
  }

  func fetchAll() async throws -> [Clip] {
    guard let db = db.pointer else { throw ClipStoreError.sqliteFailure("Database unavailable") }
    let sql = """
    SELECT id, url, created_at, duration, tags
    FROM clips
    ORDER BY created_at DESC;
    """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ClipStoreError.sqliteFailure(sqliteErrorMessage(db))
    }
    defer { sqlite3_finalize(statement) }

    var results: [Clip] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let idText = sqlite3_column_text(statement, 0),
            let urlText = sqlite3_column_text(statement, 1) else {
        continue
      }
      let idString = String(cString: idText)
      let urlString = String(cString: urlText)
      let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
      let duration = sqlite3_column_double(statement, 3)
      let tagsString = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "[]"

      guard let id = UUID(uuidString: idString),
            let url = URL(string: urlString) else {
        continue
      }
      let tagsData = Data(tagsString.utf8)
      let tags = (try? decoder.decode([String].self, from: tagsData)) ?? []
      results.append(Clip(id: id, url: url, createdAt: createdAt, duration: duration, tags: tags))
    }
    return results
  }

  func save(clip: Clip) async throws -> Clip {
    guard let db = db.pointer else { throw ClipStoreError.sqliteFailure("Database unavailable") }
    let sql = """
    INSERT OR REPLACE INTO clips (id, url, created_at, duration, tags)
    VALUES (?, ?, ?, ?, ?);
    """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ClipStoreError.sqliteFailure(sqliteErrorMessage(db))
    }
    defer { sqlite3_finalize(statement) }

    let tagsData = (try? encoder.encode(clip.tags)) ?? Data("[]".utf8)
    let tagsString = String(decoding: tagsData, as: UTF8.self)

    bindText(statement, 1, clip.id.uuidString)
    bindText(statement, 2, clip.url.absoluteString)
    sqlite3_bind_double(statement, 3, clip.createdAt.timeIntervalSince1970)
    sqlite3_bind_double(statement, 4, clip.duration)
    bindText(statement, 5, tagsString)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ClipStoreError.sqliteFailure(sqliteErrorMessage(db))
    }
    return clip
  }

  private static func openDB(at url: URL) -> OpaquePointer? {
    var openedDB: OpaquePointer?
    if sqlite3_open_v2(url.path, &openedDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
      return nil
    }
    return openedDB
  }

  private static func createSchema(db: OpaquePointer?) {
    guard let db else { return }
    let sql = """
    CREATE TABLE IF NOT EXISTS clips (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      created_at REAL NOT NULL,
      duration REAL NOT NULL,
      tags TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS clips_created_at_idx ON clips(created_at DESC);
    """
    sqlite3_exec(db, sql, nil, nil, nil)
  }

  private func sqliteErrorMessage(_ db: OpaquePointer?) -> String {
    guard let message = sqlite3_errmsg(db) else { return "SQLite error" }
    return String(cString: message)
  }

  private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
    _ = value.withCString { ptr in
      sqlite3_bind_text(statement, index, ptr, -1, sqliteTransient)
    }
  }
}
