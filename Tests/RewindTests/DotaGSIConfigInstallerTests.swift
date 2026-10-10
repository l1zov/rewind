@testable import Rewind
import XCTest

final class DotaGSIConfigInstallerTests: XCTestCase {
	func testConfigContentsIncludePortAndToken() {
		let contents = DotaGSIConfigInstaller.configContents(port: 39285, authToken: "secret-token")
		XCTAssertTrue(contents.contains("http://127.0.0.1:39285/"))
		XCTAssertTrue(contents.contains("\"token\"         \"secret-token\""))
	}

	func testParsesLibraryFolderPaths() {
		let vdf = """
		"libraryfolders"
		{
			"0"
			{
				"path"		"/Users/test/Library/Application Support/Steam"
				"label"		""
			}
			"1"
			{
				"path"		"/Volumes/ExternalDrive/SteamLibrary"
				"label"		""
			}
		}
		"""
		let paths = DotaGSIConfigInstaller.parseLibraryFolderPaths(from: vdf)
		XCTAssertEqual(paths, [
			"/Users/test/Library/Application Support/Steam",
			"/Volumes/ExternalDrive/SteamLibrary",
		])
	}

	func testParsesEmptyVDFAsNoPaths() {
		XCTAssertEqual(DotaGSIConfigInstaller.parseLibraryFolderPaths(from: ""), [])
	}

	func testInstallSkipsLibrariesWithoutDota2() throws {
		let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let installed = DotaGSIConfigInstaller.install(port: 39285, authToken: "token", steamLibraries: [tempDir])
		XCTAssertTrue(installed.isEmpty)
	}

	func testInstallWritesConfigWhenDota2Present() throws {
		let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let dota2Root = tempDir.appendingPathComponent("steamapps/common/dota 2 beta", isDirectory: true)
		try FileManager.default.createDirectory(at: dota2Root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let installed = DotaGSIConfigInstaller.install(port: 39285, authToken: "token", steamLibraries: [tempDir])
		XCTAssertEqual(installed.count, 1)
		let contents = try String(contentsOf: installed[0], encoding: .utf8)
		XCTAssertTrue(contents.contains("39285"))

		// Re-installing with identical content should be idempotent (no error, same path).
		let reinstalled = DotaGSIConfigInstaller.install(port: 39285, authToken: "token", steamLibraries: [tempDir])
		XCTAssertEqual(reinstalled, installed)
	}

	func testConfigAsksDotaForUpdatesAtAGentleRate() {
		let contents = DotaGSIConfigInstaller.configContents(port: 39285, authToken: "t")
		// Rewind only needs the hero and game state, checked every few seconds; the
		// old 0.1 s values made Dota POST up to ten times a second.
		XCTAssertTrue(contents.contains("\"buffer\"        \"2.0\""), contents)
		XCTAssertTrue(contents.contains("\"throttle\"      \"5.0\""), contents)
	}
}
