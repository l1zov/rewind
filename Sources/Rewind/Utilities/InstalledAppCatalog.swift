import AppKit

/// Lists the apps a user can pick to record while they're open: apps installed in
/// the usual folders (read straight from their Info.plist, so they don't have to
/// be running) and the apps that are running right now.
enum InstalledAppCatalog {
	struct Entry: Equatable, Identifiable {
		let bundleID: String
		let name: String

		var id: String { bundleID }
	}

	/// A running app as the system reports it, kept plain so the filtering can be tested.
	struct RunningApp {
		let bundleID: String?
		let name: String?
		let isRegular: Bool
	}

	static var defaultFolders: [URL] {
		let home = FileManager.default.homeDirectoryForCurrentUser
		return [
			URL(fileURLWithPath: "/Applications", isDirectory: true),
			home.appendingPathComponent("Applications", isDirectory: true),
			URL(fileURLWithPath: "/System/Applications", isDirectory: true),
			// Steam keeps each game in its own folder here.
			home.appendingPathComponent("Library/Application Support/Steam/steamapps/common", isDirectory: true),
		]
	}

	/// Apps found in `folders` and in the folders directly inside them (Utilities,
	/// a Steam game's own folder, ...), one per bundle ID, sorted by name. Folders
	/// that don't exist are skipped.
	static func apps(in folders: [URL] = defaultFolders) -> [Entry] {
		var seen = Set<String>()
		var entries: [Entry] = []
		for folder in folders {
			for appURL in appBundles(in: folder) {
				guard let entry = entry(forAppAt: appURL), seen.insert(entry.bundleID).inserted else { continue }
				entries.append(entry)
			}
		}
		return sorted(entries)
	}

	/// Regular (Dock) apps that are running, one per bundle ID, sorted by name.
	/// Background agents, processes without a bundle ID and `ownBundleID` are left out.
	static func runningEntries(from apps: [RunningApp], excluding ownBundleID: String?) -> [Entry] {
		var seen = Set<String>()
		var entries: [Entry] = []
		for app in apps where app.isRegular {
			guard let bundleID = app.bundleID, !bundleID.isEmpty, bundleID != ownBundleID,
			      seen.insert(bundleID).inserted
			else { continue }
			entries.append(Entry(bundleID: bundleID, name: app.name ?? bundleID))
		}
		return sorted(entries)
	}

	@MainActor
	static func runningApps() -> [Entry] {
		let running = NSWorkspace.shared.runningApplications.map { app in
			RunningApp(
				bundleID: app.bundleIdentifier,
				name: app.localizedName,
				isRegular: app.activationPolicy == .regular
			)
		}
		return runningEntries(from: running, excluding: Bundle.main.bundleIdentifier)
	}

	/// `.app` bundles directly in `folder`, plus those one folder further down.
	private static func appBundles(in folder: URL) -> [URL] {
		var bundles: [URL] = []
		for child in contents(of: folder) {
			if child.pathExtension == "app" {
				bundles.append(child)
			} else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
				bundles += contents(of: child).filter { $0.pathExtension == "app" }
			}
		}
		return bundles
	}

	private static func contents(of folder: URL) -> [URL] {
		(try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
	}

	private static func sorted(_ entries: [Entry]) -> [Entry] {
		entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	private static func entry(forAppAt appURL: URL) -> Entry? {
		let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
		guard let data = try? Data(contentsOf: plistURL),
		      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
		      let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty
		else { return nil }

		let name = (info["CFBundleDisplayName"] as? String)
			?? (info["CFBundleName"] as? String)
			?? appURL.deletingPathExtension().lastPathComponent
		return Entry(bundleID: bundleID, name: name)
	}
}
