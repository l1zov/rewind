import Foundation
@testable import Rewind
import XCTest

final class DotaGSIAuthTokenTests: XCTestCase {
	private func makeDefaults() -> UserDefaults {
		let name = "DotaGSIAuthTokenTests-\(UUID().uuidString)"
		addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
		return UserDefaults(suiteName: name)!
	}

	func testTokenIsStableAcrossLaunches() {
		let defaults = makeDefaults()
		let first = DotaGSIAuthToken.current(defaults: defaults)
		let second = DotaGSIAuthToken.current(defaults: defaults)
		XCTAssertFalse(first.isEmpty)
		XCTAssertEqual(first, second, "A relaunch must not invalidate the token a running Dota 2 already has")
	}

	func testEachInstallGetsItsOwnToken() {
		XCTAssertNotEqual(
			DotaGSIAuthToken.current(defaults: makeDefaults()),
			DotaGSIAuthToken.current(defaults: makeDefaults()))
	}

	func testBlankStoredValueIsReplaced() {
		let defaults = makeDefaults()
		defaults.set("   ", forKey: DotaGSIAuthToken.defaultsKey)
		let token = DotaGSIAuthToken.current(defaults: defaults)
		XCTAssertFalse(token.trimmingCharacters(in: .whitespaces).isEmpty)
		XCTAssertEqual(DotaGSIAuthToken.current(defaults: defaults), token)
	}
}
