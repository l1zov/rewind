import AppKit

/// Figures out which game the user is currently playing so it can be shown in
/// Discord Rich Presence ("Clipping <game>").
///
/// Detection is app-based: it asks macOS for the running GUI applications
/// (`NSWorkspace`) and matches them against a table of known games plus the
/// bundled Discord catalog. Roblox is enriched with the specific experience name
/// via its logs (see `RobloxGameDetector`). Returns nil when no known game is up.
actor GamePresenceDetector {
	/// A known game and the substrings that identify its running app. `needles`
	/// are matched case-insensitively against each app's name, bundle id, and
	/// executable name. Order matters: earlier entries win.
	struct Game {
		let name: String
		let needles: [String]
	}

	struct RunningApp: Equatable {
		let name: String
		let bundleID: String
		let executable: String

		var haystacks: [String] { [name, bundleID, executable] }
	}

	static let defaultCatalog: [Game] = [
		Game(name: "Roblox", needles: ["roblox"]),
		Game(name: "Minecraft", needles: ["minecraft", "lunarclient", "prismlauncher"]),
		Game(name: "League of Legends", needles: ["leagueclient", "league of legends"]),
		Game(name: "Teamfight Tactics", needles: ["teamfight"]),
		Game(name: "Team Fortress 2", needles: ["tf2", "hl2_osx"]),
		Game(name: "Terraria", needles: ["terraria"]),
		Game(name: "Stardew Valley", needles: ["stardew"]),
		Game(name: "Balatro", needles: ["balatro"]),
		Game(name: "Hades II", needles: ["hades ii", "hades2"]),
		Game(name: "Hades", needles: ["hades"]),
		Game(name: "Celeste", needles: ["celeste"]),
		Game(name: "Vampire Survivors", needles: ["vampiresurvivors", "vampire survivors"]),
		Game(name: "Factorio", needles: ["factorio"]),
		Game(name: "Among Us", needles: ["among us"]),
		Game(name: "World of Warcraft", needles: ["world of warcraft"]),
		Game(name: "Final Fantasy XIV", needles: ["ffxiv", "final fantasy xiv"]),
		Game(name: "Old School RuneScape", needles: ["runelite", "old school runescape"]),
		Game(name: "osu!", needles: ["osu!"]),
		Game(name: "Baldur's Gate 3", needles: ["baldur", "bg3"]),
		Game(name: "Cyberpunk 2077", needles: ["cyberpunk"]),
		Game(name: "Resident Evil 4", needles: ["resident evil 4"]),
		Game(name: "Resident Evil Village", needles: ["resident evil village"]),
		Game(name: "No Man's Sky", needles: ["no man", "nomanssky"]),
		Game(name: "Civilization VI", needles: ["civilization vi", "civ6"]),
		Game(name: "Stray", needles: ["stray"]),
		Game(name: "The Sims 4", needles: ["sims 4", "thesims4"]),
		Game(name: "Hollow Knight", needles: ["hollow knight", "hollow_knight"]),
		Game(name: "Slay the Spire", needles: ["slay the spire", "slaythespire"]),
		Game(name: "Disco Elysium", needles: ["disco elysium", "discoelysium"]),
		Game(name: "Cities: Skylines", needles: ["cities: skylines", "cities skylines", "citiesskylines"]),
		Game(name: "Divinity: Original Sin 2", needles: ["divinity", "original sin"]),
		Game(name: "Don't Starve Together", needles: ["starve", "dontstarve"]),
		Game(name: "RimWorld", needles: ["rimworld"]),
		Game(name: "Portal 2", needles: ["portal 2", "portal2"]),
		Game(name: "Football Manager", needles: ["football manager", "footballmanager"]),
		Game(name: "Total War", needles: ["total war", "totalwar"]),
		Game(name: "Cult of the Lamb", needles: ["cult of the lamb", "cultofthelamb"]),
		Game(name: "Dave the Diver", needles: ["dave the diver", "davethediver"]),
		Game(name: "Baba Is You", needles: ["baba is you", "babaisyou"]),
		Game(name: "Frostpunk", needles: ["frostpunk"]),
		Game(name: "Dead Cells", needles: ["dead cells", "deadcells"]),
		Game(name: "Northgard", needles: ["northgard"]),
	]

	private let catalog: [Game]
	private let roblox: RobloxGameDetector
	private let art: GameArtResolver
	private let bundledCatalogURL: URL?
	/// Lazily-parsed `executable-basename -> game name` map distilled from
	/// Discord's detectable-games database (see scripts/generate-game-catalog.py).
	private var bundledCatalog: [String: String]?

	init(catalog: [Game] = GamePresenceDetector.defaultCatalog,
	     roblox: RobloxGameDetector = RobloxGameDetector(),
	     art: GameArtResolver = GameArtResolver(),
	     bundledCatalogURL: URL? = Bundle.main.url(forResource: "games", withExtension: "tsv")) {
		self.catalog = catalog
		self.roblox = roblox
		self.art = art
		self.bundledCatalogURL = bundledCatalogURL
	}

	/// A detected game plus an optional server-join URL (Roblox only).
	struct Presence: Equatable {
		let name: String
		let joinURL: String?
		let artURL: String?

		init(name: String, joinURL: String? = nil, artURL: String? = nil) {
			self.name = name
			self.joinURL = joinURL
			self.artURL = artURL
		}
	}

	func currentGame(enrichRoblox: Bool = true) async -> Presence? {
		let apps = runningApps()
		// 1. Curated list first: Roblox's experience/join enrichment plus titles
		if let game = matchCatalog(apps: apps) {
			if game.name == "Roblox" {
				if enrichRoblox, let experience = await roblox.currentExperience() {
					return Presence(name: experience.name, joinURL: experience.joinURL, artURL: experience.iconURL)
				}
				return Presence(name: "Roblox")
			}
			return Presence(name: game.name, artURL: await art.artURL(for: game.name))
		}
		// 2. Discord's detectable-games catalog (native macOS games).
		if let name = matchBundledCatalog(apps: apps) {
			return Presence(name: name, artURL: await art.artURL(for: name))
		}
		return nil
	}

	/// First catalog game whose app is currently running.
	func matchCatalog(apps: [RunningApp]? = nil) -> Game? {
		let running = apps ?? runningApps()
		return catalog.first { game in
			game.needles.contains { needle in
				running.contains { app in
					app.haystacks.contains { $0.range(of: needle, options: .caseInsensitive) != nil }
				}
			}
		}
	}

	/// Match running apps against the bundled Discord catalog by basename.
	func matchBundledCatalog(apps: [RunningApp]) -> String? {
		let catalog = loadBundledCatalog()
		guard !catalog.isEmpty else { return nil }
		return Self.match(apps: apps, in: catalog)
	}

	/// Pure basename lookup, split out so it can be tested without the bundle.
	static func match(apps: [RunningApp], in catalog: [String: String]) -> String? {
		for app in apps {
			// executable basename is precise
			// the localized name is a looser fallback
			for candidate in [app.executable, app.name] {
				let key = candidate.lowercased()
				if key.isEmpty { continue }
				if let name = catalog[key] { return name }
				if key.hasSuffix(".app"), let name = catalog[String(key.dropLast(4))] { return name }
			}
		}
		return nil
	}

	private func loadBundledCatalog() -> [String: String] {
		if let bundledCatalog { return bundledCatalog }
		var map: [String: String] = [:]
		if let bundledCatalogURL,
		   let text = try? String(contentsOf: bundledCatalogURL, encoding: .utf8) {
			for line in text.split(separator: "\n") {
				let parts = line.split(separator: "\t", maxSplits: 1)
				if parts.count == 2 { map[String(parts[0])] = String(parts[1]) }
			}
		}
		bundledCatalog = map
		return map
	}

	private func runningApps() -> [RunningApp] {
		NSWorkspace.shared.runningApplications.compactMap { app in
			// only foreground GUI app
			guard app.activationPolicy == .regular else { return nil }
			let running = RunningApp(
				name: app.localizedName ?? "",
				bundleID: app.bundleIdentifier ?? "",
				executable: app.executableURL?.lastPathComponent ?? ""
			)
			guard running.haystacks.contains(where: { !$0.isEmpty }) else { return nil }
			return running
		}
	}
}
