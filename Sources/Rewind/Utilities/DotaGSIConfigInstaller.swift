import Foundation

/// Installs the config file that turns on Dota 2's Game State Integration
/// (GSI) feature and points it at `DotaGSIServer`'s local endpoint. This only
/// writes a small text file that Valve's own client reads on launch — nothing
/// is injected into the game process, and no Steam settings are touched.
///
/// Dota 2 also needs `-gamestateintegration` added to its Steam launch
/// options once, by hand (Library -> Dota 2 -> Properties -> Launch
/// Options) — that's a one-time manual step in Steam's own UI.
/// The shared secret between Rewind and the GSI config file it writes. Persisted
/// so a Rewind relaunch while Dota 2 is running doesn't leave Dota posting the
/// previous launch's token (which the server would reject) until Dota restarts.
enum DotaGSIAuthToken {
	static let defaultsKey = "dotaGSI.authToken"

	static func current(defaults: UserDefaults = .standard) -> String {
		if let stored = defaults.string(forKey: defaultsKey),
		   !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		{
			return stored
		}
		let token = UUID().uuidString
		defaults.set(token, forKey: defaultsKey)
		return token
	}
}

enum DotaGSIConfigInstaller {
	static let configFileName = "gamestate_integration_rewind.cfg"

	/// Writes the GSI config into every Steam library that has Dota 2
	/// installed, unless it's already present with this exact content.
	/// Returns the config file paths that are installed and up to date.
	@discardableResult
	static func install(port: UInt16, authToken: String, steamLibraries: [URL]? = nil) -> [URL] {
		let contents = configContents(port: port, authToken: authToken)
		var installed: [URL] = []
		for library in steamLibraries ?? steamLibraryPaths() {
			let dota2Root = library.appendingPathComponent("steamapps/common/dota 2 beta", isDirectory: true)
			guard FileManager.default.fileExists(atPath: dota2Root.path) else { continue }

			let cfgDir = dota2Root.appendingPathComponent("game/dota/cfg/gamestate_integration", isDirectory: true)
			let fileURL = cfgDir.appendingPathComponent(configFileName)

			if let existing = try? String(contentsOf: fileURL, encoding: .utf8), existing == contents {
				installed.append(fileURL)
				continue
			}
			do {
				try FileManager.default.createDirectory(at: cfgDir, withIntermediateDirectories: true)
				try contents.write(to: fileURL, atomically: true, encoding: .utf8)
				installed.append(fileURL)
			} catch {
				AppLog.error(.app, "Failed to install Dota 2 GSI config at \(fileURL.path):", error: error)
			}
		}
		return installed
	}

	/// The VDF/KeyValues config Dota 2's client expects. `buffer`/`throttle` are a
	/// few seconds: Rewind only reads the hero and game state (polled every 10 s), and
	/// 0.1 s made Dota POST up to ten times a second; `heartbeat` lets
	/// `DotaGSIServer` tell a live-but-quiet match apart from a closed one.
	static func configContents(port: UInt16, authToken: String) -> String {
		"""
		"Rewind GSI"
		{
			"uri"           "http://127.0.0.1:\(port)/"
			"timeout"       "5.0"
			"buffer"        "2.0"
			"throttle"      "5.0"
			"heartbeat"     "30.0"
			"data"
			{
				"provider"      "0"
				"map"           "1"
				"player"        "0"
				"hero"          "1"
				"abilities"     "0"
				"items"         "0"
				"buildings"     "0"
				"draft"         "0"
				"wearables"     "0"
			}
			"auth"
			{
				"token"         "\(authToken)"
			}
		}
		"""
	}

	/// Every Steam library folder: the default install location plus whatever
	/// additional libraries are listed in Steam's own `libraryfolders.vdf`.
	static func steamLibraryPaths(
		steamRoot: URL = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
	) -> [URL] {
		var paths = [steamRoot]
		let vdfURL = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
		if let text = try? String(contentsOf: vdfURL, encoding: .utf8) {
			paths += parseLibraryFolderPaths(from: text).map { URL(fileURLWithPath: $0, isDirectory: true) }
		}
		return paths
	}

	/// Pure parser for `libraryfolders.vdf`'s `"path"  "..."` lines, split out
	/// so it's testable without touching the filesystem.
	static func parseLibraryFolderPaths(from vdf: String) -> [String] {
		guard let regex = try? NSRegularExpression(pattern: #""path"\s+"([^"]+)""#) else { return [] }
		let range = NSRange(vdf.startIndex..., in: vdf)
		var paths: [String] = []
		regex.enumerateMatches(in: vdf, range: range) { match, _, _ in
			guard let match, match.numberOfRanges > 1, let matchRange = Range(match.range(at: 1), in: vdf) else { return }
			paths.append(String(vdf[matchRange]).replacingOccurrences(of: "\\\\", with: "\\"))
		}
		return paths
	}
}
