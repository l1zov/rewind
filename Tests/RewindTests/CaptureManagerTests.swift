@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
@testable import Rewind
@preconcurrency import ScreenCaptureKit
import XCTest

/// A latch a test can open to let a suspended fake continue.
private final class Gate: @unchecked Sendable {
	private let lock = NSLock()
	private var isOpen = false
	private var waiters: [CheckedContinuation<Void, Never>] = []

	func wait() async {
		await withCheckedContinuation { continuation in
			lock.lock()
			if isOpen {
				lock.unlock()
				continuation.resume()
			} else {
				waiters.append(continuation)
				lock.unlock()
			}
		}
	}

	func open() {
		lock.lock()
		isOpen = true
		let pending = waiters
		waiters = []
		lock.unlock()
		pending.forEach { $0.resume() }
	}
}

private final class FakeCaptureSource: CaptureSource, @unchecked Sendable {
	private let lock = NSLock()
	private var _startCalls = 0
	private var _stopCalls = 0
	private var _activeStarts = 0
	private var _maxActiveStarts = 0
	private var _events: [String] = []

	var displaySize: CGSize? { CGSize(width: 1280, height: 720) }
	var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?
	var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?
	var onMicSampleBuffer: ((CMSampleBuffer) -> Void)?
	var onCaptureStopped: ((String?) -> Void)?

	var startGate: Gate?
	var stopGate: Gate?

	var startCalls: Int { lock.withLock { _startCalls } }
	var stopCalls: Int { lock.withLock { _stopCalls } }
	var maxConcurrentStarts: Int { lock.withLock { _maxActiveStarts } }
	var events: [String] { lock.withLock { _events } }

	func startCapture(
		contentFilter _: UncheckedSendable<SCContentFilter>?, resolution _: CaptureResolution?,
		quality _: QualityPreset, frameRate _: Int, recordMicrophone _: Bool,
		recordDesktopAudio _: Bool, microphoneDeviceID _: String?
	) async throws {
		lock.withLock {
			_startCalls += 1
			_activeStarts += 1
			_maxActiveStarts = max(_maxActiveStarts, _activeStarts)
			_events.append("start-begin")
		}
		await startGate?.wait()
		lock.withLock {
			_activeStarts -= 1
			_events.append("start-end")
		}
	}

	func stopCapture() async {
		lock.withLock {
			_stopCalls += 1
			_events.append("stop-begin")
		}
		await stopGate?.wait()
		lock.withLock { _events.append("stop-end") }
	}
}

private final class FakeWriter: SegmentWriter, @unchecked Sendable {
	private let lock = NSLock()
	private var url: URL?
	private let behavior: @Sendable (Int) async throws -> Void
	private let index: Int

	init(index: Int, behavior: @escaping @Sendable (Int) async throws -> Void) {
		self.index = index
		self.behavior = behavior
	}

	func configureSegment(
		outputURL: URL, videoSize _: CGSize, includeAudio _: Bool, audioSettings _: [String: Any]?,
		quality _: QualityPreset, frameRate _: Int, recordMicrophone _: Bool,
		videoCodec _: CaptureVideoCodec
	) throws {
		lock.withLock { url = outputURL }
	}

	func finishWriting() async throws -> URL {
		try await behavior(index)
		guard let url = lock.withLock({ url }) else { throw CaptureError.writerUnavailable }
		return url
	}

	func appendVideo(_: CMSampleBuffer) {}
	func appendAudio(_: CMSampleBuffer) {}
	func appendMic(_: CMSampleBuffer) {}
}

/// Hands out numbered fake writers and records the order/overlap of `finishWriting`.
private final class WriterLog: @unchecked Sendable {
	private let lock = NSLock()
	private var created = 0
	private var active = 0
	private var _maxActive = 0
	private var _finished: [Int] = []

	var maxConcurrentFinishes: Int { lock.withLock { _maxActive } }
	var finishedOrder: [Int] { lock.withLock { _finished } }

	func makeWriter(behavior: @escaping @Sendable (Int) async throws -> Void = { _ in }) -> SegmentWriter {
		let index = lock.withLock { () -> Int in
			created += 1
			return created
		}
		return FakeWriter(index: index) { [self] index in
			lock.withLock {
				active += 1
				_maxActive = max(_maxActive, active)
			}
			defer { lock.withLock { active -= 1 } }
			try await behavior(index)
			lock.withLock { _finished.append(index) }
		}
	}
}

final class CaptureManagerTests: XCTestCase {
	private func makeManager(
		source: FakeCaptureSource = FakeCaptureSource(),
		writers: WriterLog = WriterLog(),
		behavior: @escaping @Sendable (Int) async throws -> Void = { _ in }
	) -> CaptureManager {
		CaptureManager(
			captureSource: source,
			makeWriter: { _ in writers.makeWriter(behavior: behavior) },
			inspectSegment: { _ in 10 },
			segmentDuration: 3600
		)
	}

	private func start(_ manager: CaptureManager) async throws {
		try await manager.start()
	}

	// - #3: concurrent starts ---

	func testConcurrentStartsCreateOnlyOneCaptureStream() async throws {
		let source = FakeCaptureSource()
		let gate = Gate()
		source.startGate = gate
		let manager = makeManager(source: source)

		let first = Task { try await manager.start() }
		let second = Task { try await manager.start() }
		try await Task.sleep(nanoseconds: 100_000_000)
		gate.open()
		try await first.value
		try await second.value

		XCTAssertEqual(source.startCalls, 1, "A second start must see the first one's result, not build another stream")
		XCTAssertEqual(source.maxConcurrentStarts, 1)
		let running = await manager.isCaptureRunning()
		XCTAssertTrue(running)
		await manager.stop()
	}

	// - #7: start must not run while a stop is still in flight ---

	func testStartWaitsForInFlightStopAndThenActuallyStarts() async throws {
		let source = FakeCaptureSource()
		let manager = makeManager(source: source)
		try await start(manager)
		XCTAssertEqual(source.startCalls, 1)

		let stopGate = Gate()
		source.stopGate = stopGate
		let stopTask = Task { await manager.stop() }
		try await Task.sleep(nanoseconds: 100_000_000)
		let startTask = Task { try await manager.start() }
		try await Task.sleep(nanoseconds: 100_000_000)
		XCTAssertEqual(source.startCalls, 1, "start() must wait for the stop that is still suspended")

		stopGate.open()
		await stopTask.value
		try await startTask.value

		XCTAssertEqual(source.startCalls, 2, "The queued start must really start, not silently no-op")
		let running = await manager.isCaptureRunning()
		XCTAssertTrue(running)
		XCTAssertEqual(source.events.suffix(3), ["stop-end", "start-begin", "start-end"])
		await manager.stop()
	}

	// - #2: rotations never overlap ---

	func testConcurrentRotationsAreSerialized() async throws {
		let source = FakeCaptureSource()
		let writers = WriterLog()
		let manager = makeManager(source: source, writers: writers) { _ in
			try await Task.sleep(nanoseconds: 50_000_000)
		}
		try await start(manager)

		async let a: Void = manager.rotateSegment()
		async let b: Void = manager.rotateSegment()
		_ = await (a, b)

		XCTAssertEqual(writers.maxConcurrentFinishes, 1, "Two rotations finished writers at the same time")
		let buffered = await manager.bufferedSegmentURLs()
		XCTAssertEqual(buffered.count, 2)
		XCTAssertEqual(writers.finishedOrder, writers.finishedOrder.sorted(), "Segments must finish in rotation order")
		await manager.stop()
	}

	// - #6: save must tolerate an empty final segment ---

	func testSaveRotationToleratesEmptyFinalSegmentWhenBufferHasFootage() async throws {
		let manager = makeManager { index in
			if index == 2 { throw CaptureError.noFramesCaptured }
		}
		try await start(manager)
		await manager.rotateSegment() // writer #1 -> buffered

		// writer #2 is empty, but there are minutes of earlier footage to save
		try await manager.rotateForSave()

		let buffered = await manager.bufferedSegmentURLs()
		XCTAssertEqual(buffered.count, 1)
		await manager.stop()
	}

	func testSaveRotationStillFailsWhenThereIsNothingToSave() async throws {
		let manager = makeManager { _ in throw CaptureError.noFramesCaptured }
		try await start(manager)

		do {
			try await manager.rotateForSave()
			XCTFail("Expected noFramesCaptured with an empty buffer")
		} catch {
			XCTAssertEqual(error as? CaptureError, .noFramesCaptured)
		}
		await manager.stop()
	}

	// - #5: a bad segment must not wipe the buffer ---

	func testEmptySegmentIsSkippedAndKeepsBufferedReplay() async throws {
		let source = FakeCaptureSource()
		let manager = makeManager(source: source) { index in
			// writer #1 is the initial active writer, #2 the first standby, ...
			if index == 2 { throw CaptureError.noFramesCaptured }
		}
		let interrupted = ExpectationBox()
		await manager.setOnCaptureInterruptedHandler { _ in interrupted.fire() }
		try await start(manager)

		await manager.rotateSegment() // finishes writer #1: ok, buffered
		let afterFirst = await manager.bufferedSegmentURLs()
		XCTAssertEqual(afterFirst.count, 1)

		await manager.rotateSegment() // finishes writer #2: no frames
		await manager.rotateSegment() // finishes writer #3: ok

		let buffered = await manager.bufferedSegmentURLs()
		XCTAssertEqual(buffered.count, 2, "The empty segment must be dropped without clearing earlier ones")
		let running = await manager.isCaptureRunning()
		XCTAssertTrue(running, "An empty segment must not stop capture")
		XCTAssertFalse(interrupted.fired)
		await manager.stop()
	}

	func testSingleRotationFailureKeepsBufferAndKeepsRecording() async throws {
		let manager = makeManager { index in
			if index == 2 { throw CaptureError.exportFailed }
		}
		let interrupted = ExpectationBox()
		await manager.setOnCaptureInterruptedHandler { _ in interrupted.fire() }
		try await start(manager)

		await manager.rotateSegment() // ok
		await manager.rotateSegment() // fails once
		await manager.rotateSegment() // ok again, resets the failure streak

		let buffered = await manager.bufferedSegmentURLs()
		XCTAssertEqual(buffered.count, 2)
		let running = await manager.isCaptureRunning()
		XCTAssertTrue(running)
		XCTAssertFalse(interrupted.fired)
		await manager.stop()
	}

	func testRepeatedRotationFailuresStopCaptureAndNotifyOnce() async throws {
		let manager = makeManager { _ in throw CaptureError.exportFailed }
		let interrupted = ExpectationBox()
		await manager.setOnCaptureInterruptedHandler { _ in interrupted.fire() }
		try await start(manager)

		await manager.rotateSegment()
		await manager.rotateSegment()
		let stillRunning = await manager.isCaptureRunning()
		XCTAssertTrue(stillRunning, "Two failures in a row are still tolerated")
		await manager.rotateSegment()

		let running = await manager.isCaptureRunning()
		XCTAssertFalse(running)
		XCTAssertEqual(interrupted.count, 1)
	}

	func testHandlerCanRestartCaptureWithoutDeadlock() async throws {
		let source = FakeCaptureSource()
		let manager = makeManager(source: source) { _ in throw CaptureError.exportFailed }
		let restarted = ExpectationBox()
		await manager.setOnCaptureInterruptedHandler { _ in
			Task {
				try? await manager.start()
				restarted.fire()
			}
		}
		try await start(manager)
		for _ in 0..<3 { await manager.rotateSegment() }
		try await Task.sleep(nanoseconds: 200_000_000)

		XCTAssertTrue(restarted.fired)
		XCTAssertEqual(source.startCalls, 2)
		await manager.stop()
	}
}

private final class ExpectationBox: @unchecked Sendable {
	private let lock = NSLock()
	private var _count = 0
	var count: Int { lock.withLock { _count } }
	var fired: Bool { count > 0 }
	func fire() { lock.withLock { _count += 1 } }
}
