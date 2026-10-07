@testable import Rewind
import XCTest

final class DotaGSIServerTests: XCTestCase {
	func testParsesHeroNameAndGameState() {
		let payload = """
		{"hero":{"name":"npc_dota_hero_antimage"},"map":{"game_state":"DOTA_GAMERULES_STATE_GAME_IN_PROGRESS"}}
		""".data(using: .utf8)!
		let state = DotaGSIServer.parseState(fromBody: payload, expectedToken: nil)
		XCTAssertEqual(state?.heroName, "Antimage")
		XCTAssertEqual(state?.gameState, "DOTA_GAMERULES_STATE_GAME_IN_PROGRESS")
	}

	func testHumanizesMultiWordHeroName() {
		let payload = """
		{"hero":{"name":"npc_dota_hero_skeleton_king"}}
		""".data(using: .utf8)!
		let state = DotaGSIServer.parseState(fromBody: payload, expectedToken: nil)
		XCTAssertEqual(state?.heroName, "Skeleton King")
	}

	func testRejectsMismatchedAuthToken() {
		let payload = """
		{"hero":{"name":"npc_dota_hero_antimage"},"auth":{"token":"wrong"}}
		""".data(using: .utf8)!
		let state = DotaGSIServer.parseState(fromBody: payload, expectedToken: "expected")
		XCTAssertNil(state)
	}

	func testAcceptsMatchingAuthToken() {
		let payload = """
		{"hero":{"name":"npc_dota_hero_antimage"},"auth":{"token":"expected"}}
		""".data(using: .utf8)!
		let state = DotaGSIServer.parseState(fromBody: payload, expectedToken: "expected")
		XCTAssertEqual(state?.heroName, "Antimage")
	}

	func testReturnsNilForEmptyPayload() {
		let payload = "{}".data(using: .utf8)!
		let state = DotaGSIServer.parseState(fromBody: payload, expectedToken: nil)
		XCTAssertNil(state)
	}

	func testReturnsNilForMalformedJSON() {
		let payload = "not json".data(using: .utf8)!
		let state = DotaGSIServer.parseState(fromBody: payload, expectedToken: nil)
		XCTAssertNil(state)
	}

	func testSplitCompleteRequestWaitsForFullBody() {
		let partial = Data("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\":1}".utf8)
		XCTAssertNil(DotaGSIServer.splitCompleteRequest(partial))

		let full = Data("POST / HTTP/1.1\r\nContent-Length: 7\r\n\r\n{\"a\":1}".utf8)
		let result = DotaGSIServer.splitCompleteRequest(full)
		XCTAssertEqual(result?.body, Data("{\"a\":1}".utf8))
	}

	func testNegativeContentLengthDoesNotCrashAndIsRejected() {
		let request = Data("POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n{\"a\":1}".utf8)
		let result = DotaGSIServer.splitCompleteRequest(request)
		// Treated as a zero-length body instead of trapping in `prefix(-1)`.
		XCTAssertEqual(result?.body, Data())
	}

	func testContentLengthRejectsNegativeAndOversizedValues() {
		XCTAssertNil(DotaGSIServer.contentLength(fromHeaders: "POST / HTTP/1.1\r\nContent-Length: -5"))
		XCTAssertNil(DotaGSIServer.contentLength(
			fromHeaders: "POST / HTTP/1.1\r\nContent-Length: \(DotaGSIServer.maxRequestBytes + 1)"))
		XCTAssertEqual(
			DotaGSIServer.contentLength(fromHeaders: "POST / HTTP/1.1\r\nContent-Length: \(DotaGSIServer.maxRequestBytes)"),
			DotaGSIServer.maxRequestBytes)
	}

	func testListenerIsRestrictedToLoopback() {
		XCTAssertEqual(DotaGSIServer.listenerParameters().requiredInterfaceType, .loopback)
	}

	func testContentLengthIsCaseInsensitiveAndTrimmed() {
		let headers = "POST / HTTP/1.1\r\ncontent-length:   42  \r\nHost: localhost"
		XCTAssertEqual(DotaGSIServer.contentLength(fromHeaders: headers), 42)
	}
}
