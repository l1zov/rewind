@testable import Rewind
import XCTest

final class GameArtResolverTests: XCTestCase {
	func testAcceptsExactMatch() {
		XCTAssertTrue(GameArtResolver.matches(query: "Terraria", result: "Terraria"))
		XCTAssertTrue(GameArtResolver.matches(query: "Baldur's Gate 3", result: "Baldur's Gate 3"))
	}

	func testAcceptsEditionSuffix() {
		XCTAssertTrue(GameArtResolver.matches(query: "Football Manager", result: "Football Manager 26"))
	}

	func testIgnoresPunctuationAndTrademarks() {
		XCTAssertTrue(GameArtResolver.matches(query: "The Sims 4", result: "The Sims™ 4"))
	}

	func testRejectsOffTargetHit() {

		XCTAssertFalse(GameArtResolver.matches(query: "Minecraft", result: "Minecraft Dungeons"))
		XCTAssertFalse(GameArtResolver.matches(query: "Old School RuneScape", result: "RuneScape"))
	}

	// - Lookup caching ---

	private final class StubProtocol: URLProtocol {
		nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, Int))?
		nonisolated(unsafe) static var requestCount = 0

		override class func canInit(with _: URLRequest) -> Bool { true }
		override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
		override func stopLoading() {}
		override func startLoading() {
			Self.requestCount += 1
			do {
				let (data, status) = try XCTUnwrap(Self.handler)(request)
				let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
				client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
				client?.urlProtocol(self, didLoad: data)
				client?.urlProtocolDidFinishLoading(self)
			} catch {
				client?.urlProtocol(self, didFailWithError: error)
			}
		}
	}

	private func makeResolver() -> GameArtResolver {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [StubProtocol.self]
		StubProtocol.requestCount = 0
		return GameArtResolver(session: URLSession(configuration: configuration))
	}

	func testTransientNetworkFailureIsNotCachedForever() async {
		let resolver = makeResolver()
		StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
		let first = await resolver.artURL(for: "Terraria")
		XCTAssertNil(first)

		StubProtocol.handler = { _ in
			(Data(#"{"items":[{"id":105600,"name":"Terraria"}]}"#.utf8), 200)
		}
		let second = await resolver.artURL(for: "Terraria")
		XCTAssertEqual(second, "https://cdn.cloudflare.steamstatic.com/steam/apps/105600/header.jpg")
	}

	func testGenuineNoMatchIsStillCached() async {
		let resolver = makeResolver()
		StubProtocol.handler = { _ in (Data(#"{"items":[]}"#.utf8), 200) }
		_ = await resolver.artURL(for: "Some Unknown Game")
		_ = await resolver.artURL(for: "Some Unknown Game")
		XCTAssertEqual(StubProtocol.requestCount, 1)
	}
}
