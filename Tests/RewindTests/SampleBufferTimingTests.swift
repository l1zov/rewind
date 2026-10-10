import CoreMedia
import CoreVideo
@testable import Rewind
import XCTest

final class SampleBufferTimingTests: XCTestCase {
	private func frame(at seconds: Double) -> CMSampleBuffer {
		var pixelBuffer: CVPixelBuffer?
		CVPixelBufferCreate(
			kCFAllocatorDefault, 16, 16, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &pixelBuffer)
		var format: CMVideoFormatDescription?
		CMVideoFormatDescriptionCreateForImageBuffer(
			allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer!, formatDescriptionOut: &format)
		var sample: CMSampleBuffer?
		var timing = CMSampleTimingInfo(
			duration: .invalid, presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 1_000_000),
			decodeTimeStamp: .invalid)
		CMSampleBufferCreateForImageBuffer(
			allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer!, dataReady: true,
			makeDataReadyCallback: nil, refcon: nil, formatDescription: format!,
			sampleTiming: &timing, sampleBufferOut: &sample)
		return sample!
	}

	private struct Result {
		var times: [Double]   // output PTS (relative to session start)
		var raw: [Double]     // matching input PTS (relative to session start)
		var dropped: Int
	}

	/// Feeds frames at the given source times through the quantizer the way the
	/// writer does (carrying `lastVideoPTS` forward).
	private func run(rawTimes: [Double], fps: Int) -> Result {
		let start = rawTimes[0]
		let sessionStart = CMTime(seconds: start, preferredTimescale: 1_000_000)
		var last = CMTime.invalid
		var result = Result(times: [], raw: [], dropped: 0)
		for t in rawTimes {
			guard let out = SampleBufferTiming.quantizedVideo(
				frame(at: t), offset: .zero, sessionStartPTS: sessionStart, lastVideoPTS: last, defaultFrameRate: fps)
			else {
				result.dropped += 1
				continue
			}
			let pts = CMSampleBufferGetPresentationTimeStamp(out)
			last = pts
			result.times.append((pts - sessionStart).seconds)
			result.raw.append(t - start)
		}
		return result
	}

	private func assertMonotonic(_ times: [Double], file: StaticString = #filePath, line: UInt = #line) {
		for (a, b) in zip(times, times.dropFirst()) {
			XCTAssertLessThan(a, b, "timestamps must strictly increase", file: file, line: line)
		}
	}

	func testSteadyStreamAtTheConfiguredRateKeepsEveryFrameOnTime() {
		let raw = (0 ..< 600).map { 1000 + Double($0) / 120 }
		let result = run(rawTimes: raw, fps: 120)
		XCTAssertEqual(result.dropped, 0)
		assertMonotonic(result.times)
		for (out, input) in zip(result.times, result.raw) {
			XCTAssertEqual(out, input, accuracy: 1.0 / 120 / 2)
		}
	}

	func testSourceFasterThanTheConfiguredRateDoesNotStretchTheTimeline() {
		// 130 frames/s delivered into a 120 fps setting for 5 s of real time.
		let raw = (0 ..< 650).map { 1000 + Double($0) / 130 }
		let result = run(rawTimes: raw, fps: 120)

		assertMonotonic(result.times)
		let realSeconds = raw.last! - raw.first!
		let writtenSeconds = result.times.last!
		XCTAssertEqual(writtenSeconds / realSeconds, 1.0, accuracy: 0.01,
			"Written video was \(writtenSeconds)s for \(realSeconds)s of real time (slow motion)")
		// no frame may drift more than ~1.5 frames behind real time
		for (out, input) in zip(result.times, result.raw) {
			XCTAssertLessThan(out - input, 1.5 / 120 + 0.0005)
		}
		XCTAssertGreaterThan(result.dropped, 0, "Surplus frames are dropped instead of delaying everything after them")
	}

	func testSlowSourceKeepsItsRealSpacing() {
		// a 60 Hz display feeding a 120 fps setting
		let raw = (0 ..< 300).map { 1000 + Double($0) / 60 }
		let result = run(rawTimes: raw, fps: 120)
		XCTAssertEqual(result.dropped, 0)
		for (a, b) in zip(result.times, result.times.dropFirst()) {
			XCTAssertEqual(b - a, 1.0 / 60, accuracy: 0.0005)
		}
	}

	func testJitterNeverBreaksMonotonicityOrDriftsAway() {
		var generator = SystemRandomNumberGenerator()
		var raw: [Double] = []
		var last = 0.0
		for i in 0 ..< 1200 {
			let t = max(last + 0.0005, Double(i) / 120 + Double.random(in: -0.004 ... 0.004, using: &generator))
			raw.append(1000 + t)
			last = t
		}
		let result = run(rawTimes: raw, fps: 120)

		assertMonotonic(result.times)
		for (out, input) in zip(result.times, result.raw) {
			XCTAssertGreaterThan(out - input, -1.0 / 120)
			XCTAssertLessThan(out - input, 1.5 / 120 + 0.0005)
		}
		XCTAssertLessThan(Double(result.dropped) / 1200, 0.15, "Jitter alone should cost few frames")
	}

	func testAFrameStampedNoLaterThanThePreviousOneIsDropped() {
		let sessionStart = CMTime(seconds: 1000, preferredTimescale: 1_000_000)
		let first = SampleBufferTiming.quantizedVideo(
			frame(at: 1000), offset: .zero, sessionStartPTS: sessionStart, lastVideoPTS: .invalid, defaultFrameRate: 60)
		let firstPTS = CMSampleBufferGetPresentationTimeStamp(first!)
		let duplicate = SampleBufferTiming.quantizedVideo(
			frame(at: 1000), offset: .zero, sessionStartPTS: sessionStart, lastVideoPTS: firstPTS, defaultFrameRate: 60)
		XCTAssertNotNil(duplicate, "A duplicate within one frame of lag may still be shifted forward one frame")
		let stale = SampleBufferTiming.quantizedVideo(
			frame(at: 999.9), offset: .zero, sessionStartPTS: sessionStart, lastVideoPTS: CMTime(seconds: 1001, preferredTimescale: 1_000_000), defaultFrameRate: 60)
		XCTAssertNil(stale, "A frame far behind the timeline must be dropped, not pushed after it")
	}
}
