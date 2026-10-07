import Foundation

enum ClipUploadError: LocalizedError, Equatable {
	case clipUnreadable
	case clipTooLarge(limit: Int64, actual: Int64)
	case server(status: Int, body: String)
	case unreadableResponse
	case badLink(String)

	var errorDescription: String? {
		switch self {
		case .clipUnreadable:
			return "The clip file couldn't be read."
		case let .clipTooLarge(limit, actual):
			let format = { (bytes: Int64) in
				ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
			}
			return "This clip is \(format(actual)), but the host only accepts \(format(limit))."
		case let .server(status, body):
			let detail = body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140)
			if detail.isEmpty {
				return "The host rejected the upload (HTTP \(status))."
			}
			return "The host rejected the upload (HTTP \(status)): \(detail)"
		case .unreadableResponse:
			return "The host's reply couldn't be understood."
		case let .badLink(value):
			return "The host returned something that isn't a link: \(value)"
		}
	}
}

/// Uploads a clip to one of the `ClipUploadProvider` hosts.
///
/// The multipart body is staged on disk and streamed from there rather than being
/// assembled in memory: a long replay can run to hundreds of megabytes.
final class ClipUploader: @unchecked Sendable {
	static let shared = ClipUploader()

	private let session: URLSession
	private let chunkSize: Int

	init(session: URLSession = .shared, chunkSize: Int = 1 << 20) {
		self.session = session
		self.chunkSize = chunkSize
	}

	/// Uploads `clipURL` and returns the link the host handed back.
	///
	/// Cancelling the surrounding `Task` cancels the transfer.
	func upload(
		clipAt clipURL: URL,
		provider: ClipUploadProvider,
		expirationID: String? = nil,
		onProgress: @escaping @Sendable (Double) -> Void = { _ in }
	) async throws -> URL {
		let size = try clipSize(at: clipURL)
		if let limit = provider.maxFileSizeBytes, size > limit {
			throw ClipUploadError.clipTooLarge(limit: limit, actual: size)
		}

		let boundary = "RewindBoundary-\(UUID().uuidString)"
		let bodyURL = try writeMultipartBody(
			clipURL: clipURL,
			provider: provider,
			expirationID: expirationID,
			boundary: boundary
		)
		defer { try? FileManager.default.removeItem(at: bodyURL) }

		var request = URLRequest(url: provider.endpoint)
		request.httpMethod = "POST"
		request.setValue(
			"multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
		)
		// Several of these hosts turn away requests that arrive without a real
		// User-Agent, so always send one.
		request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

		let (data, status) = try await send(request, bodyURL: bodyURL, onProgress: onProgress)
		guard (200 ..< 300).contains(status) else {
			throw ClipUploadError.server(status: status, body: String(decoding: data, as: UTF8.self))
		}
		return try Self.parseLink(from: data, provider: provider)
	}

	// - Response parsing ---

	/// Pulls the clip link out of a successful response body.
	static func parseLink(from data: Data, provider: ClipUploadProvider) throws -> URL {
		let raw: String
		switch provider.parser {
		case .plainText:
			raw = String(decoding: data, as: UTF8.self)
		case let .json(path):
			guard let value = jsonString(at: path, in: data) else {
				throw ClipUploadError.unreadableResponse
			}
			raw = value
		}

		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = URL(string: trimmed),
		      let scheme = url.scheme?.lowercased(),
		      scheme == "https" || scheme == "http",
		      url.host?.isEmpty == false
		else {
			throw ClipUploadError.badLink(String(trimmed.prefix(140)))
		}
		return url
	}

	private static func jsonString(
		at path: [ClipUploadProvider.JSONPathComponent], in data: Data
	) -> String? {
		guard var node = try? JSONSerialization.jsonObject(with: data) else { return nil }
		for component in path {
			switch component {
			case let .key(key):
				guard let object = node as? [String: Any], let next = object[key] else { return nil }
				node = next
			case let .index(index):
				guard let array = node as? [Any], array.indices.contains(index) else { return nil }
				node = array[index]
			}
		}
		return node as? String
	}

	// - Request body ---

	private func writeMultipartBody(
		clipURL: URL,
		provider: ClipUploadProvider,
		expirationID: String?,
		boundary: String
	) throws -> URL {
		let bodyURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("rewind-upload-\(UUID().uuidString).multipart")
		guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
			throw ClipUploadError.clipUnreadable
		}
		// Staging can fail part-way (unreadable clip, disk full); don't leave a
		// clip-sized partial body behind in the temp folder when it does.
		var staged = false
		defer { if !staged { try? FileManager.default.removeItem(at: bodyURL) } }

		let output = try FileHandle(forWritingTo: bodyURL)
		defer { try? output.close() }

		var fields = provider.staticFields
		if let field = provider.expirationFieldName,
		   let option = provider.expiration(id: expirationID)
		{
			fields[field] = option.id
		}
		// Sorted so a given upload always produces the same body, which makes two
		// failing requests comparable.
		for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
			var part = "--\(boundary)\r\n"
			part += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
			part += "\(value)\r\n"
			try output.write(contentsOf: Data(part.utf8))
		}

		var header = "--\(boundary)\r\n"
		header += "Content-Disposition: form-data; name=\"\(provider.fileFieldName)\";"
		header += " filename=\"\(Self.safeFilename(for: clipURL))\"\r\n"
		header += "Content-Type: \(Self.mimeType(for: clipURL))\r\n\r\n"
		try output.write(contentsOf: Data(header.utf8))

		let input = try FileHandle(forReadingFrom: clipURL)
		defer { try? input.close() }
		while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
			try output.write(contentsOf: chunk)
		}

		try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
		staged = true
		return bodyURL
	}

	private func clipSize(at url: URL) throws -> Int64 {
		guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
			throw ClipUploadError.clipUnreadable
		}
		return Int64(size)
	}

	/// Quotes and newlines would break the `Content-Disposition` header.
	static func safeFilename(for url: URL) -> String {
		let cleaned = url.lastPathComponent
			.components(separatedBy: CharacterSet(charactersIn: "\"\\\r\n"))
			.joined()
		return cleaned.isEmpty ? "clip.\(url.pathExtension)" : cleaned
	}

	static func mimeType(for url: URL) -> String {
		switch url.pathExtension.lowercased() {
		case "mp4": return "video/mp4"
		case "mov": return "video/quicktime"
		case "m4v": return "video/x-m4v"
		default: return "application/octet-stream"
		}
	}

	private static let userAgent: String = {
		let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
			as? String ?? "dev"
		return "Rewind/\(version) (+https://github.com/l1zov/rewind)"
	}()

	// - Transfer ---

	private func send(
		_ request: URLRequest,
		bodyURL: URL,
		onProgress: @escaping @Sendable (Double) -> Void
	) async throws -> (Data, Int) {
		let handle = TransferHandle()
		return try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation {
				(continuation: CheckedContinuation<(Data, Int), Error>) in
				let task = session.uploadTask(with: request, fromFile: bodyURL) { data, response, error in
					handle.finish()
					if let error {
						let nsError = error as NSError
						if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
							continuation.resume(throwing: CancellationError())
						} else {
							continuation.resume(throwing: error)
						}
						return
					}
					let status = (response as? HTTPURLResponse)?.statusCode ?? 0
					continuation.resume(returning: (data ?? Data(), status))
				}
				let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
					onProgress(progress.fractionCompleted)
				}
				handle.start(task: task, observation: observation)
			}
		} onCancel: {
			handle.cancel()
		}
	}
}

/// Bridges `Task` cancellation onto the `URLSessionTask`, including a cancel that
/// lands before the transfer has started.
private final class TransferHandle: @unchecked Sendable {
	private let lock = NSLock()
	private var task: URLSessionTask?
	private var observation: NSKeyValueObservation?
	private var isCancelled = false

	func start(task: URLSessionTask, observation: NSKeyValueObservation) {
		lock.lock()
		let cancelledEarly = isCancelled
		if !cancelledEarly {
			self.task = task
			self.observation = observation
		}
		lock.unlock()

		// Always resume, even when already cancelled, so the completion handler
		// runs and the continuation is guaranteed to resume exactly once.
		task.resume()
		if cancelledEarly {
			observation.invalidate()
			task.cancel()
		}
	}

	func cancel() {
		lock.lock()
		isCancelled = true
		let task = self.task
		let observation = self.observation
		self.task = nil
		self.observation = nil
		lock.unlock()

		observation?.invalidate()
		task?.cancel()
	}

	func finish() {
		lock.lock()
		let observation = self.observation
		self.observation = nil
		task = nil
		lock.unlock()

		observation?.invalidate()
	}
}
