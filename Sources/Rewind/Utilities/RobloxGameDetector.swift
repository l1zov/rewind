import Foundation

actor RobloxGameDetector {
	private var universeIDCache: [String: String] = [:]
	private var nameCache: [String: String] = [:]
	private var iconCache: [String: String] = [:]
	private let session: URLSession
	private let staleThreshold: TimeInterval
	private let logsDirectoryOverride: URL?
	private let logTail = RobloxLogTail()
	/// Lookups that just failed are not retried for this long (they used to hit
	/// the network again on every 10 s poll).
	private let failureBackoff: TimeInterval
	private var failedLookupsUntil: [String: Date] = [:]

	init(session: URLSession = URLSession(configuration: .ephemeral),
	     staleThreshold: TimeInterval = 120,
	     logsDirectory: URL? = nil,
	     failureBackoff: TimeInterval = 60) {
		self.session = session
		self.staleThreshold = staleThreshold
		logsDirectoryOverride = logsDirectory
		self.failureBackoff = failureBackoff
	}
	
	struct Session: Equatable {
		let placeID: String
		let jobID: String?
	}

	struct Experience: Equatable {
		let name: String
		let joinURL: String?
		let iconURL: String?
	}

	func currentExperience() async -> Experience? {
		guard let session = currentSession() else { return nil }
		guard let universeID = await universeID(forPlace: session.placeID) else { return nil }
		guard let name = await gameName(forUniverse: universeID) else { return nil }
		let iconURL = await gameIcon(forUniverse: universeID)
		let joinURL = session.jobID.map {
			"https://www.roblox.com/games/start?placeId=\(session.placeID)&gameInstanceId=\($0)"
		}
		return Experience(name: name, joinURL: joinURL, iconURL: iconURL)
	}

	// - Log parsing ---

	private func logsDirectory() -> URL {
		logsDirectoryOverride ?? FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Logs/Roblox", isDirectory: true)
	}

	private func currentSession() -> Session? {
		guard let (logURL, modified) = newestLog() else { return nil }
		guard Date().timeIntervalSince(modified) < staleThreshold else { return nil }
		return logTail.latestSession(in: logURL)
	}

	func lastSession(in log: String) -> Session? {
		Self.parseSession(in: log)
	}

	static func parseSession(in log: String) -> Session? {
		if let regex = try? NSRegularExpression(pattern: #"Joining game '([^']*)' place (\d+)"#) {
			let range = NSRange(log.startIndex..., in: log)
			var session: Session?
			regex.enumerateMatches(in: log, range: range) { match, _, _ in
				guard let match, match.numberOfRanges > 2,
				      let jobRange = Range(match.range(at: 1), in: log),
				      let placeRange = Range(match.range(at: 2), in: log) else { return }
				let job = String(log[jobRange])
				session = Session(placeID: String(log[placeRange]), jobID: job.isEmpty ? nil : job)
			}
			if let session { return session }
		}
		
		if let placeID = lastPlaceID(inLog: log) {
			return Session(placeID: placeID, jobID: nil)
		}
		return nil
	}

	private func isBackedOff(_ key: String) -> Bool {
		guard let until = failedLookupsUntil[key] else { return false }
		if until > Date() { return true }
		failedLookupsUntil[key] = nil
		return false
	}

	private func markFailed(_ key: String) {
		failedLookupsUntil[key] = Date().addingTimeInterval(failureBackoff)
	}

	private func newestLog() -> (URL, Date)? {
		let fm = FileManager.default
		guard let files = try? fm.contentsOfDirectory(
			at: logsDirectory(),
			includingPropertiesForKeys: [.contentModificationDateKey],
			options: [.skipsHiddenFiles]
		) else { return nil }

		return files
			.filter { $0.pathExtension == "log" }
			.compactMap { url -> (URL, Date)? in
				let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
					.contentModificationDate
				return date.map { (url, $0) }
			}
			.max { $0.1 < $1.1 }
	}

	func lastPlaceID(in log: String) -> String? {
		Self.lastPlaceID(inLog: log)
	}

	static func lastPlaceID(inLog log: String) -> String? {
		let patterns = [
			#"Joining game '[^']*' place (\d+)"#,
			#"[Pp]lace[Ii]d[:\s\"=]+(\d+)"#,
		]
		for pattern in patterns {
			guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
			let range = NSRange(log.startIndex..., in: log)
			var last: String?
			regex.enumerateMatches(in: log, range: range) { match, _, _ in
				guard let match, match.numberOfRanges > 1,
				      let captured = Range(match.range(at: 1), in: log) else { return }
				last = String(log[captured])
			}
			if let last { return last }
		}
		return nil
	}

	// - Name resolution ---

	private func universeID(forPlace placeID: String) async -> String? {
		if let cached = universeIDCache[placeID] { return cached }
		let failureKey = "universe:\(placeID)"
		if isBackedOff(failureKey) { return nil }
		let urlString = "https://apis.roblox.com/universes/v1/places/\(placeID)/universe"
		guard let url = URL(string: urlString),
		      let (data, _) = try? await session.data(from: url),
		      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else {
			markFailed(failureKey)
			return nil
		}
		let id = (json["universeId"] as? Int).map(String.init) ?? json["universeId"] as? String
		if let id { universeIDCache[placeID] = id } else { markFailed(failureKey) }
		return id
	}

	private func gameName(forUniverse universeID: String) async -> String? {
		if let cached = nameCache[universeID] { return cached }
		let failureKey = "name:\(universeID)"
		if isBackedOff(failureKey) { return nil }
		let urlString = "https://games.roblox.com/v1/games?universeIds=\(universeID)"
		guard let url = URL(string: urlString),
		      let (data, _) = try? await session.data(from: url),
		      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let entries = json["data"] as? [[String: Any]],
		      let name = entries.first?["name"] as? String
		else {
			markFailed(failureKey)
			return nil
		}
		nameCache[universeID] = name
		return name
	}

	private func gameIcon(forUniverse universeID: String) async -> String? {
		if let cached = iconCache[universeID] { return cached }
		let failureKey = "icon:\(universeID)"
		if isBackedOff(failureKey) { return nil }
		let urlString = "https://thumbnails.roblox.com/v1/games/icons?universeIds=\(universeID)&size=512x512&format=Png&isCircular=false"
		guard let url = URL(string: urlString),
		      let (data, _) = try? await session.data(from: url),
		      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let entries = json["data"] as? [[String: Any]],
		      let first = entries.first,
		      first["state"] as? String == "Completed",
		      let imageURL = first["imageUrl"] as? String
		else {
			markFailed(failureKey)
			return nil
		}
		iconCache[universeID] = imageURL
		return imageURL
	}
}
