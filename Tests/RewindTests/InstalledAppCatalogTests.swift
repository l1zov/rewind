@testable import Rewind
import XCTest

final class InstalledAppCatalogTests: XCTestCase {
	private var root: URL!

	override func setUpWithError() throws {
		root = FileManager.default.temporaryDirectory
			.appendingPathComponent("InstalledAppCatalogTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	}

	override func tearDownWithError() throws {
		try? FileManager.default.removeItem(at: root)
	}

	/// Creates `<name>.app` with an Info.plist. Pass nil for `bundleID` to omit it.
	private func makeApp(_ name: String, bundleID: String?, displayName: String? = nil, in folder: URL? = nil) throws {
		let contents = (folder ?? root).appendingPathComponent("\(name).app/Contents", isDirectory: true)
		try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
		var plist: [String: Any] = ["CFBundleName": name]
		if let bundleID { plist["CFBundleIdentifier"] = bundleID }
		if let displayName { plist["CFBundleDisplayName"] = displayName }
		let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
		try data.write(to: contents.appendingPathComponent("Info.plist"))
	}

	func testListsAppsWithTheirBundleIDAndNameSortedByName() throws {
		try makeApp("Zed", bundleID: "com.example.zed")
		try makeApp("Alpha", bundleID: "com.example.alpha")

		let apps = InstalledAppCatalog.apps(in: [root])

		XCTAssertEqual(apps.map(\.bundleID), ["com.example.alpha", "com.example.zed"])
		XCTAssertEqual(apps.map(\.name), ["Alpha", "Zed"])
	}

	func testPrefersTheDisplayNameWhenPresent() throws {
		try makeApp("Roblox", bundleID: "com.example.rbx", displayName: "Roblox Player")

		let apps = InstalledAppCatalog.apps(in: [root])

		XCTAssertEqual(apps.first?.name, "Roblox Player")
	}

	func testSkipsAppsWithoutABundleIdentifierAndNonAppFiles() throws {
		try makeApp("NoID", bundleID: nil)
		try "not an app".write(to: root.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
		try makeApp("Good", bundleID: "com.example.good")

		let apps = InstalledAppCatalog.apps(in: [root])

		XCTAssertEqual(apps.map(\.bundleID), ["com.example.good"])
	}

	func testKeepsOneEntryPerBundleIDAcrossFolders() throws {
		let second = root.appendingPathComponent("second", isDirectory: true)
		try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
		try makeApp("Game", bundleID: "com.example.game")
		try makeApp("Game", bundleID: "com.example.game", in: second)

		let apps = InstalledAppCatalog.apps(in: [root, second])

		XCTAssertEqual(apps.map(\.bundleID), ["com.example.game"])
	}

	func testFindsAppsInAFolderDirectlyInsideTheScannedFolder() throws {
		let utilities = root.appendingPathComponent("Utilities", isDirectory: true)
		try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
		try makeApp("Terminal", bundleID: "com.example.terminal", in: utilities)

		let apps = InstalledAppCatalog.apps(in: [root])

		XCTAssertEqual(apps.map(\.bundleID), ["com.example.terminal"])
	}

	func testDoesNotLookMoreThanOneFolderDeep() throws {
		let deep = root.appendingPathComponent("a/b", isDirectory: true)
		try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
		try makeApp("Deep", bundleID: "com.example.deep", in: deep)

		XCTAssertEqual(InstalledAppCatalog.apps(in: [root]), [])
	}

	func testRunningAppsAreSortedByName() {
		let running = [
			InstalledAppCatalog.RunningApp(bundleID: "com.example.zed", name: "Zed", isRegular: true),
			InstalledAppCatalog.RunningApp(bundleID: "com.example.alpha", name: "Alpha", isRegular: true),
		]

		let entries = InstalledAppCatalog.runningEntries(from: running, excluding: nil)

		XCTAssertEqual(entries.map(\.name), ["Alpha", "Zed"])
	}

	func testRunningAppsSkipBackgroundAppsAppsWithoutABundleIDAndRewindItself() {
		let running = [
			InstalledAppCatalog.RunningApp(bundleID: "com.example.agent", name: "Agent", isRegular: false),
			InstalledAppCatalog.RunningApp(bundleID: nil, name: "hl2_osx", isRegular: true),
			InstalledAppCatalog.RunningApp(bundleID: "com.rewind.app", name: "Rewind", isRegular: true),
			InstalledAppCatalog.RunningApp(bundleID: "com.example.game", name: "Game", isRegular: true),
		]

		let entries = InstalledAppCatalog.runningEntries(from: running, excluding: "com.rewind.app")

		XCTAssertEqual(entries.map(\.bundleID), ["com.example.game"])
	}

	func testRunningAppsKeepOneEntryPerBundleID() {
		let running = [
			InstalledAppCatalog.RunningApp(bundleID: "com.example.game", name: "Game", isRegular: true),
			InstalledAppCatalog.RunningApp(bundleID: "com.example.game", name: "Game", isRegular: true),
		]

		XCTAssertEqual(InstalledAppCatalog.runningEntries(from: running, excluding: nil).count, 1)
	}

	func testRunningAppWithoutANameFallsBackToItsBundleID() {
		let running = [InstalledAppCatalog.RunningApp(bundleID: "com.example.game", name: nil, isRegular: true)]

		XCTAssertEqual(InstalledAppCatalog.runningEntries(from: running, excluding: nil).first?.name, "com.example.game")
	}

	func testMissingFolderIsIgnored() {
		let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)

		XCTAssertEqual(InstalledAppCatalog.apps(in: [missing]), [])
	}
}
