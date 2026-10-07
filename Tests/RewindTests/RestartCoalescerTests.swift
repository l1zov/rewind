@testable import Rewind
import XCTest

@MainActor
final class RestartCoalescerTests: XCTestCase {
	func testRapidRequestsCoalesceIntoOneFollowUpRun() async throws {
		let coalescer = RestartCoalescer()
		var runs = 0
		var inFlight = 0
		var maxInFlight = 0
		let work: @MainActor () async -> Void = {
			inFlight += 1
			maxInFlight = max(maxInFlight, inFlight)
			runs += 1
			try? await Task.sleep(nanoseconds: 100_000_000)
			inFlight -= 1
		}

		coalescer.request(work)
		try await Task.sleep(nanoseconds: 30_000_000) // the first run is now in flight
		coalescer.request(work)
		coalescer.request(work)
		coalescer.request(work)
		try await Task.sleep(nanoseconds: 500_000_000)

		XCTAssertEqual(runs, 2, "Three requests during a run collapse into a single follow-up run")
		XCTAssertEqual(maxInFlight, 1, "Restarts must never overlap")
	}

	func testRequestAfterCompletionRunsAgain() async throws {
		let coalescer = RestartCoalescer()
		var runs = 0
		coalescer.request { runs += 1 }
		try await Task.sleep(nanoseconds: 100_000_000)
		coalescer.request { runs += 1 }
		try await Task.sleep(nanoseconds: 100_000_000)
		XCTAssertEqual(runs, 2)
	}

	func testCompletionRunsAfterTheWorkThatCoversTheRequest() async throws {
		let coalescer = RestartCoalescer()
		var events: [String] = []
		coalescer.request({
			events.append("work-start")
			try? await Task.sleep(nanoseconds: 50_000_000)
			events.append("work-end")
		}, completion: { events.append("done") })
		try await Task.sleep(nanoseconds: 300_000_000)
		XCTAssertEqual(events, ["work-start", "work-end", "done"])
	}

	func testCompletionOfAMergedRequestWaitsForTheFollowUpRun() async throws {
		let coalescer = RestartCoalescer()
		var events: [String] = []
		var runs = 0
		let work: @MainActor () async -> Void = {
			runs += 1
			let id = runs
			events.append("run\(id)-start")
			try? await Task.sleep(nanoseconds: 60_000_000)
			events.append("run\(id)-end")
		}
		coalescer.request(work)
		try await Task.sleep(nanoseconds: 20_000_000)
		coalescer.request(work, completion: { events.append("done") })
		try await Task.sleep(nanoseconds: 500_000_000)

		XCTAssertEqual(events.last, "done")
		XCTAssertEqual(events.firstIndex(of: "done"), events.count - 1)
		XCTAssertEqual(runs, 2, "The merged request's completion must follow the follow-up run, which has the newest settings")
	}
}
