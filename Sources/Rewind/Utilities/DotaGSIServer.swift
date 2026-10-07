import Foundation
import Network

/// Reads live match state from Dota 2 via Valve's own Game State Integration
/// (GSI) feature: once `DotaGSIConfigInstaller` has written a config file
/// naming this server's endpoint, Dota 2 itself POSTs JSON describing the
/// current match to it. Nothing is injected into the game and no input is
/// simulated; this only listens for what Dota 2 chooses to send.
///
/// A plain class (not an actor) because `Network.framework`'s listener and
/// connection APIs are callback-based, not async/await-based; a lock guards
/// the small bit of shared state so `currentState()` stays a cheap, ordinary
/// synchronous call for callers like `GamePresenceDetector`.
final class DotaGSIServer: @unchecked Sendable {
	struct State: Equatable {
		let heroName: String?
		let gameState: String?
	}

	/// Local port Rewind listens on for Dota 2's GSI POSTs. Must match the
	/// `uri` written into the config file by `DotaGSIConfigInstaller`.
	static let defaultPort: UInt16 = 39285

	/// Upper bound on a GSI request (headers + body). Real payloads are a few
	/// KB; anything larger is a malformed or hostile client and is dropped
	/// instead of letting it grow the receive buffer without limit.
	static let maxRequestBytes = 1_048_576

	/// Listener parameters pinned to the loopback interface so the server is
	/// only reachable from this machine, as the Dota GSI config expects.
	static func listenerParameters() -> NWParameters {
		let parameters = NWParameters.tcp
		parameters.requiredInterfaceType = .loopback
		return parameters
	}

	private let port: NWEndpoint.Port
	private let authToken: String?
	private let staleThreshold: TimeInterval
	private let queue = DispatchQueue(label: "com.rewind.DotaGSIServer")
	private let lock = NSLock()
	private var listener: NWListener?
	private var latestState: State?
	private var lastReceivedAt: Date?

	/// - Parameters:
	///   - port: local TCP port to listen on; must match the `uri` written
	///     into the GSI config file by `DotaGSIConfigInstaller`.
	///   - authToken: when set, payloads whose `auth.token` field doesn't
	///     match are ignored (defense in depth; the listener is restricted to
	///     the loopback interface, see `listenerParameters()`).
	///   - staleThreshold: `currentState()` returns nil once this long has
	///     passed without a new payload (GSI sends a heartbeat periodically
	///     while the game runs, so a gap this long means the match/game ended).
	init?(port: UInt16, authToken: String? = nil, staleThreshold: TimeInterval = 45) {
		guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return nil }
		self.port = endpointPort
		self.authToken = authToken
		self.staleThreshold = staleThreshold
	}

	func start() {
		queue.async { [weak self] in
			guard let self, self.listener == nil else { return }
			guard let listener = try? NWListener(using: Self.listenerParameters(), on: self.port) else {
				AppLog.error(.app, "DotaGSIServer failed to bind port \(self.port)")
				return
			}
			listener.newConnectionHandler = { [weak self] connection in
				self?.accept(connection)
			}
			listener.start(queue: self.queue)
			self.listener = listener
		}
	}

	func stop() {
		queue.async { [weak self] in
			self?.listener?.cancel()
			self?.listener = nil
		}
	}

	/// The most recent match state, or nil if Dota 2 hasn't posted anything
	/// recently (or ever).
	func currentState() -> State? {
		lock.lock()
		defer { lock.unlock() }
		guard let lastReceivedAt, Date().timeIntervalSince(lastReceivedAt) < staleThreshold else { return nil }
		return latestState
	}

	// MARK: - Connection handling

	private func accept(_ connection: NWConnection) {
		connection.start(queue: queue)
		receiveRequest(on: connection, buffer: Data())
	}

	private func receiveRequest(on connection: NWConnection, buffer: Data) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
			guard let self else {
				connection.cancel()
				return
			}
			var buffer = buffer
			if let data { buffer.append(data) }

			if let (_, body) = Self.splitCompleteRequest(buffer) {
				self.handle(body: body)
				self.respondOK(on: connection)
				return
			}
			if isComplete || error != nil || buffer.count > Self.maxRequestBytes {
				connection.cancel()
				return
			}
			self.receiveRequest(on: connection, buffer: buffer)
		}
	}

	private func handle(body: Data) {
		guard let state = Self.parseState(fromBody: body, expectedToken: authToken) else { return }
		lock.lock()
		latestState = state
		lastReceivedAt = Date()
		lock.unlock()
	}

	private func respondOK(on connection: NWConnection) {
		let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
		connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
			connection.cancel()
		})
	}

	// MARK: - Pure parsing (testable without a real socket)

	/// Splits a raw HTTP/1.1 request buffer into (headers, body) once the full
	/// `Content-Length` worth of body has arrived. Returns nil while more data
	/// is still needed.
	static func splitCompleteRequest(_ buffer: Data) -> (headers: String, body: Data)? {
		guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
		let headerData = buffer[..<headerEndRange.lowerBound]
		guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
		let body = buffer[headerEndRange.upperBound...]
		let expectedLength = contentLength(fromHeaders: headerText) ?? 0
		guard body.count >= expectedLength else { return nil }
		return (headerText, body.prefix(expectedLength))
	}

	static func contentLength(fromHeaders headers: String) -> Int? {
		for line in headers.split(separator: "\r\n") {
			let parts = line.split(separator: ":", maxSplits: 1)
			guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
			else { continue }
			// A negative or absurdly large length is malformed; treat it as
			// absent so `splitCompleteRequest` never slices with a bad count.
			guard let length = Int(parts[1].trimmingCharacters(in: .whitespaces)),
			      (0...maxRequestBytes).contains(length)
			else { return nil }
			return length
		}
		return nil
	}

	/// Parses a Dota 2 GSI JSON payload into the bits Rewind cares about.
	/// Returns nil if the auth token doesn't match (when one is expected) or
	/// if the payload has neither a hero name nor a game state to report.
	static func parseState(fromBody body: Data, expectedToken: String?) -> State? {
		guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
		if let expectedToken {
			let providedToken = (json["auth"] as? [String: Any])?["token"] as? String
			guard providedToken == expectedToken else { return nil }
		}
		let map = json["map"] as? [String: Any]
		let hero = json["hero"] as? [String: Any]
		let heroName = (hero?["name"] as? String).flatMap(humanizeHeroName)
		let gameState = map?["game_state"] as? String
		guard heroName != nil || gameState != nil else { return nil }
		return State(heroName: heroName, gameState: gameState)
	}

	/// Dota 2 reports hero internal names like `npc_dota_hero_antimage` or
	/// `npc_dota_hero_skeleton_king`; turn that into "Antimage" / "Skeleton King".
	static func humanizeHeroName(_ raw: String) -> String? {
		var name = raw
		let prefix = "npc_dota_hero_"
		guard name.hasPrefix(prefix) else { return nil }
		name.removeFirst(prefix.count)
		guard !name.isEmpty else { return nil }
		return name.split(separator: "_")
			.map { $0.prefix(1).uppercased() + $0.dropFirst() }
			.joined(separator: " ")
	}
}
