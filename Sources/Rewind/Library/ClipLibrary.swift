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
		var clip = Clip(url: url, duration: duration)
		clip = try await store.save(clip: clip)
		clips.insert(clip, at: 0)
		return clip
	}

	func toggleFavorite(clip: Clip) {
		var updatedClip = clip
		if updatedClip.isFavorite {
			updatedClip.tags.removeAll { $0 == "favorite" }
		} else {
			updatedClip.tags.append("favorite")
		}
		
		if let idx = clips.firstIndex(where: { $0.id == updatedClip.id }) {
			clips[idx] = updatedClip
		}

		Task {
			do {
				_ = try await store.save(clip: updatedClip)
			} catch {
				AppLog.error(.library, "Unable to favorite clip:", error)
				if let idx = clips.firstIndex(where: { $0.id == updatedClip.id }) {
					clips[idx] = clip
				}
			}
		}
	}

	func deleteClip(_ clip: Clip) async {
		do {
			try await store.delete(id: clip.id)
		} catch {
			AppLog.error(.library, "Unable to delete clip from store:", error)
			return
		}

		let fm = FileManager.default
		if clip.url.isFileURL, fm.fileExists(atPath: clip.url.path) {
			do {
				try fm.removeItem(at: clip.url)
			} catch {
				AppLog.error(.library, "Deleted clip row but failed to remove file:", error)
			}
		}

		clips.removeAll { $0.id == clip.id }
		// Otherwise the thumbnails directory grows forever.
		ClipThumbnailCache.shared.invalidate(clipID: clip.id)
	}

	private func load() async {
		isLoading = true
		loadError = nil
		do {
			clips = await pruningMissingFiles(from: try await store.fetchAll())
		} catch {
			loadError = error
			clips = []
			AppLog.error(.library, "ClipLibrary: failed to load clips:", error)
		}
		isLoading = false
	}

	/// True for `/Volumes/<name>/...` paths whose `/Volumes/<name>` mount point is gone.
	nonisolated static func isOnUnmountedVolume(_ url: URL) -> Bool {
		let components = url.standardizedFileURL.pathComponents
		guard components.count > 3, components[1] == "Volumes" else { return false }
		return !FileManager.default.fileExists(atPath: "/Volumes/\(components[2])")
	}

	private func pruningMissingFiles(from stored: [Clip]) async -> [Clip] {
		let fm = FileManager.default
		var surviving: [Clip] = []
		for clip in stored {
			guard clip.url.isFileURL, !fm.fileExists(atPath: clip.url.path) else {
				surviving.append(clip)
				continue
			}
			// An unmounted external drive or network share: keep the metadata and
			// favorites so they come back with the volume, and hide the clip until
			// then. A missing folder on a volume that *is* mounted was deleted, so
			// its rows are pruned like any other missing file.
			if Self.isOnUnmountedVolume(clip.url) {
				AppLog.debug(.library, "ClipLibrary: keeping clip on unmounted volume:", clip.url.path)
				continue
			}
			do {
				try await store.delete(id: clip.id)
			} catch {
				AppLog.error(.library, "ClipLibrary: failed to prune missing clip:", error)
			}
		}
		return surviving
	}

}

protocol ClipStore: Actor {
	func fetchAll() async throws -> [Clip]
	func save(clip: Clip) async throws -> Clip
	func delete(id: UUID) async throws
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
			      let urlText = sqlite3_column_text(statement, 1)
			else {
				continue
			}
			let idString = String(cString: idText)
			let urlString = String(cString: urlText)
			let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
			let duration = sqlite3_column_double(statement, 3)
			let tagsString = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "[]"

			guard let id = UUID(uuidString: idString),
			      let url = URL(string: urlString)
			else {
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

	func delete(id: UUID) async throws {
		guard let db = db.pointer else { throw ClipStoreError.sqliteFailure("Database unavailable") }
		let sql = "DELETE FROM clips WHERE id = ?;"
		var statement: OpaquePointer?
		guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
			throw ClipStoreError.sqliteFailure(sqliteErrorMessage(db))
		}
		defer { sqlite3_finalize(statement) }

		bindText(statement, 1, id.uuidString)

		guard sqlite3_step(statement) == SQLITE_DONE else {
			throw ClipStoreError.sqliteFailure(sqliteErrorMessage(db))
		}
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
