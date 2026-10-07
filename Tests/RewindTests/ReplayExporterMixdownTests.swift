import AVFoundation
import CoreMedia
import CoreVideo
@testable import Rewind
import XCTest

/// Exercises the real writer -> exporter path with tone audio, so the mixed level
/// of each source can be measured in the saved clip.
final class ReplayExporterMixdownTests: XCTestCase {
	private let sampleRate = 48_000.0
	private let fps: Int32 = 30
	private let seconds = 5

	private var audioSettings: [String: Any] {
		[
			AVFormatIDKey: kAudioFormatLinearPCM,
			AVSampleRateKey: 48_000,
			AVNumberOfChannelsKey: 2,
			AVLinearPCMBitDepthKey: 16,
			AVLinearPCMIsFloatKey: false,
			AVLinearPCMIsBigEndianKey: false,
			"AVLinearPCMIsNonInterleaved": false,
		]
	}

	private func makeTempDirectory() throws -> URL {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("ReplayExporterMixdownTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private func videoBuffer(pts: CMTime, size: CGSize = CGSize(width: 320, height: 240)) -> CMSampleBuffer? {
		var pixelBuffer: CVPixelBuffer?
		CVPixelBufferCreate(
			kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
			[kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pixelBuffer)
		guard let pixelBuffer else { return nil }
		var format: CMVideoFormatDescription?
		CMVideoFormatDescriptionCreateForImageBuffer(
			allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
		guard let format else { return nil }
		var sample: CMSampleBuffer?
		var timing = CMSampleTimingInfo(
			duration: CMTime(value: 1, timescale: fps), presentationTimeStamp: pts, decodeTimeStamp: .invalid)
		CMSampleBufferCreateForImageBuffer(
			allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true,
			makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
			sampleTiming: &timing, sampleBufferOut: &sample)
		return sample
	}

	/// 16-bit interleaved stereo sine wave. `amplitude` is 0...1 of full scale.
	private func toneBuffer(startFrame: Int, frames: Int, frequency: Double, amplitude: Double) -> CMSampleBuffer? {
		var asbd = AudioStreamBasicDescription(
			mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
			mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
			mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
			mBitsPerChannel: 16, mReserved: 0)
		var format: CMAudioFormatDescription?
		CMAudioFormatDescriptionCreate(
			allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
			magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
		guard let format else { return nil }

		var samples = [Int16](repeating: 0, count: frames * 2)
		for i in 0 ..< frames {
			let value = sin(2 * .pi * frequency * Double(startFrame + i) / sampleRate) * amplitude
			let int = Int16(max(-1, min(1, value)) * Double(Int16.max))
			samples[i * 2] = int
			samples[i * 2 + 1] = int
		}
		let byteCount = samples.count * MemoryLayout<Int16>.size
		var block: CMBlockBuffer?
		CMBlockBufferCreateWithMemoryBlock(
			allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
			blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
			dataLength: byteCount, flags: 0, blockBufferOut: &block)
		guard let block else { return nil }
		samples.withUnsafeBytes {
			_ = CMBlockBufferReplaceDataBytes(
				with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
		}
		var sample: CMSampleBuffer?
		var timing = CMSampleTimingInfo(
			duration: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(sampleRate)),
			presentationTimeStamp: CMTime(value: CMTimeValue(startFrame), timescale: CMTimeScale(sampleRate)),
			decodeTimeStamp: .invalid)
		CMSampleBufferCreate(
			allocator: kCFAllocatorDefault, dataBuffer: block, dataReady: true,
			makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleCount: frames,
			sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0,
			sampleSizeArray: nil, sampleBufferOut: &sample)
		return sample
	}

	/// Records a 5 s segment: desktop tone (440 Hz) and, optionally, a mic tone (880 Hz).
	private func makeSegment(
		in directory: URL, desktopAmplitude: Double?, micAmplitude: Double?,
		size: CGSize = CGSize(width: 320, height: 240)
	) async throws -> ReplaySegment {
		let writer = ReplayWriter(queue: DispatchQueue(label: "mixdown.\(UUID().uuidString)"))
		let url = directory.appendingPathComponent("segment-\(UUID().uuidString).mov")
		try writer.configure(
			outputURL: url, videoSize: size,
			includeAudio: desktopAmplitude != nil, audioSettings: audioSettings,
			frameRate: Int(fps), recordMicrophone: micAmplitude != nil)

		let framesPerBuffer = 1024
		let totalAudioFrames = Int(sampleRate) * seconds
		var audioFrame = 0
		for frame in 0 ..< Int(fps) * seconds {
			let pts = CMTime(value: CMTimeValue(frame), timescale: fps)
			if let video = videoBuffer(pts: pts, size: size) { writer.appendVideo(video) }
			// keep audio roughly in step with video
			let audioTarget = min(totalAudioFrames, Int(Double(frame + 1) / Double(fps) * sampleRate))
			while audioFrame + framesPerBuffer <= audioTarget {
				if let amplitude = desktopAmplitude,
				   let buffer = toneBuffer(startFrame: audioFrame, frames: framesPerBuffer, frequency: 440, amplitude: amplitude)
				{
					writer.appendAudio(buffer)
				}
				if let amplitude = micAmplitude,
				   let buffer = toneBuffer(startFrame: audioFrame, frames: framesPerBuffer, frequency: 880, amplitude: amplitude)
				{
					writer.appendMic(buffer)
				}
				audioFrame += framesPerBuffer
			}
		}
		try await Task.sleep(nanoseconds: 300_000_000)
		let finished = try await writer.finishWriting()
		return ReplaySegment(url: finished, duration: Double(seconds))
	}

	private func audioTrackCount(of url: URL) async throws -> Int {
		try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).count
	}

	/// RMS (0...1 of full scale) of the first audio track, decoded to float PCM.
	private func rms(of url: URL) async throws -> Double {
		let asset = AVURLAsset(url: url)
		let audioTracks = try await asset.loadTracks(withMediaType: .audio)
		let track = try XCTUnwrap(audioTracks.first)
		let reader = try AVAssetReader(asset: asset)
		let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
			AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
			AVLinearPCMIsBigEndianKey: false, "AVLinearPCMIsNonInterleaved": false,
			AVNumberOfChannelsKey: 2, AVSampleRateKey: 48_000,
		])
		reader.add(output)
		XCTAssertTrue(reader.startReading())
		var sumSquares = 0.0
		var count = 0
		while let sample = output.copyNextSampleBuffer() {
			guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
			var length = 0
			var pointer: UnsafeMutablePointer<Int8>?
			CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
			guard let pointer else { continue }
			pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { floats in
				for i in 0 ..< length / 4 {
					sumSquares += Double(floats[i]) * Double(floats[i])
					count += 1
				}
			}
		}
		return count == 0 ? 0 : (sumSquares / Double(count)).squareRoot()
	}

	/// True when the `moov` index comes before the media data, i.e. the file can
	/// start playing (and be previewed) before it is fully downloaded.
	private func hasIndexAtFront(_ url: URL) throws -> Bool {
		let data = try Data(contentsOf: url)
		let moov = data.range(of: Data("moov".utf8))?.lowerBound
		let mdat = data.range(of: Data("mdat".utf8))?.lowerBound
		guard let moov, let mdat else { return false }
		return moov < mdat
	}

	// - Tests ---

	func testMicAndDesktopAreFoldedIntoOneTrackThatContainsBoth() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let segment = try await makeSegment(in: directory, desktopAmplitude: 0.5, micAmplitude: 0.5)
		let recordedTracks = try await audioTrackCount(of: segment.url)
		XCTAssertEqual(recordedTracks, 2, "Precondition: the writer records the mic as a second track")

		let output = try await ReplayExporter().export(
			segments: [segment], seconds: 4, container: .mp4,
			audioMix: ExportAudioMix(roles: [.desktop, .microphone], desktopVolume: 1, microphoneVolume: 1))
		defer { try? FileManager.default.removeItem(at: output) }

		let tracks = try await audioTrackCount(of: output)
		XCTAssertEqual(tracks, 1, "Players that only play the first track would otherwise never play the mic")
		// two uncorrelated 0.5-amplitude sines: rms = sqrt(2 * (0.5/sqrt2)^2) = 0.5
		let level = try await rms(of: output)
		XCTAssertEqual(level, 0.5, accuracy: 0.08)
	}

	func testMicrophoneVolumeScalesOnlyTheMic() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let segment = try await makeSegment(in: directory, desktopAmplitude: 0.5, micAmplitude: 0.5)

		let micMuted = try await ReplayExporter().export(
			segments: [segment], seconds: 4, container: .mp4,
			audioMix: ExportAudioMix(roles: [.desktop, .microphone], desktopVolume: 1, microphoneVolume: 0))
		defer { try? FileManager.default.removeItem(at: micMuted) }
		let desktopMuted = try await ReplayExporter().export(
			segments: [segment], seconds: 4, container: .mp4,
			audioMix: ExportAudioMix(roles: [.desktop, .microphone], desktopVolume: 0, microphoneVolume: 1))
		defer { try? FileManager.default.removeItem(at: desktopMuted) }

		// a single 0.5-amplitude sine: rms = 0.5 / sqrt2 = 0.354
		let desktopOnly = try await rms(of: micMuted)
		let micOnly = try await rms(of: desktopMuted)
		XCTAssertEqual(desktopOnly, 0.354, accuracy: 0.07)
		XCTAssertEqual(micOnly, 0.354, accuracy: 0.07)
	}

	func testDesktopVolumeOfHalfLowersALoneDesktopTrack() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let segment = try await makeSegment(in: directory, desktopAmplitude: 0.8, micAmplitude: nil)

		let full = try await ReplayExporter().export(
			segments: [segment], seconds: 4, container: .mp4,
			audioMix: ExportAudioMix(roles: [.desktop], desktopVolume: 1, microphoneVolume: 1))
		defer { try? FileManager.default.removeItem(at: full) }
		let half = try await ReplayExporter().export(
			segments: [segment], seconds: 4, container: .mp4,
			audioMix: ExportAudioMix(roles: [.desktop], desktopVolume: 0.5, microphoneVolume: 1))
		defer { try? FileManager.default.removeItem(at: half) }

		let fullLevel = try await rms(of: full)
		let halfLevel = try await rms(of: half)
		XCTAssertEqual(halfLevel / fullLevel, 0.5, accuracy: 0.08)
	}

	func testBothPathsProduceAStreamableFile() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let twoTrack = try await makeSegment(in: directory, desktopAmplitude: 0.5, micAmplitude: 0.5)
		let oneTrack = try await makeSegment(in: directory, desktopAmplitude: 0.5, micAmplitude: nil)

		let mixed = try await ReplayExporter().export(
			segments: [twoTrack], seconds: 3, container: .mp4,
			audioMix: ExportAudioMix(roles: [.desktop, .microphone], desktopVolume: 1, microphoneVolume: 1))
		defer { try? FileManager.default.removeItem(at: mixed) }
		let passthrough = try await ReplayExporter().export(segments: [oneTrack], seconds: 3, container: .mp4)
		defer { try? FileManager.default.removeItem(at: passthrough) }

		XCTAssertTrue(try hasIndexAtFront(mixed), "mixdown path: moov must precede mdat")
		XCTAssertTrue(try hasIndexAtFront(passthrough), "passthrough path: moov must precede mdat")
	}

	func testMixdownKeepsTheVideoAndTheRequestedLength() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let segment = try await makeSegment(in: directory, desktopAmplitude: 0.5, micAmplitude: 0.5)

		// 2 s from the end: starts mid-GOP, which the video copy must handle cleanly
		let output = try await ReplayExporter().export(
			segments: [segment], seconds: 2, container: .mp4,
			audioMix: ExportAudioMix(roles: [.desktop, .microphone], desktopVolume: 1, microphoneVolume: 1))
		defer { try? FileManager.default.removeItem(at: output) }

		let asset = AVURLAsset(url: output)
		let videoTracks = try await asset.loadTracks(withMediaType: .video)
		let video = try XCTUnwrap(videoTracks.first)
		let videoRange = try await video.load(.timeRange)
		XCTAssertEqual(videoRange.duration.seconds, 2, accuracy: 0.25)
		let audioTracks = try await asset.loadTracks(withMediaType: .audio)
		let audio = try XCTUnwrap(audioTracks.first)
		let audioRange = try await audio.load(.timeRange)
		XCTAssertEqual(audioRange.duration.seconds, 2, accuracy: 0.25)

		// the first stored video sample must be decodable on its own (a keyframe)
		let reader = try AVAssetReader(asset: asset)
		let output2 = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
		reader.add(output2)
		XCTAssertTrue(reader.startReading())
		let first = try XCTUnwrap(output2.copyNextSampleBuffer())
		let attachments = CMSampleBufferGetSampleAttachmentsArray(first, createIfNecessary: false) as? [[CFString: Any]]
		let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
		XCTAssertFalse(notSync, "Clip must begin on a keyframe")

		let formats = try await video.load(.formatDescriptions)
		let format = try XCTUnwrap(formats.first)
		XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_H264, "Video should be copied, not re-encoded")
	}

	func testMixdownAcrossSeveralSegments() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let first = try await makeSegment(in: directory, desktopAmplitude: 0.5, micAmplitude: 0.5)
		let second = try await makeSegment(in: directory, desktopAmplitude: 0.5, micAmplitude: 0.5)

		let output = try await ReplayExporter().export(
			segments: [first, second], seconds: 8, container: .mp4,
			audioMix: ExportAudioMix(roles: [.desktop, .microphone], desktopVolume: 1, microphoneVolume: 1))
		defer { try? FileManager.default.removeItem(at: output) }

		let tracks = try await audioTrackCount(of: output)
		XCTAssertEqual(tracks, 1)
		let asset = AVURLAsset(url: output)
		let duration = try await asset.load(.duration).seconds
		XCTAssertEqual(duration, 8, accuracy: 0.4)
		let level = try await rms(of: output)
		XCTAssertEqual(level, 0.5, accuracy: 0.08)
	}

	func testMixdownWhenSegmentsDifferInVideoSize() async throws {
		let directory = try makeTempDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		// e.g. the captured window was resized between two rotations
		let first = try await makeSegment(
			in: directory, desktopAmplitude: 0.5, micAmplitude: 0.5, size: CGSize(width: 320, height: 240))
		let second = try await makeSegment(
			in: directory, desktopAmplitude: 0.5, micAmplitude: 0.5, size: CGSize(width: 160, height: 120))

		let output = try await ReplayExporter().export(
			segments: [first, second], seconds: 8, container: .mp4,
			audioMix: ExportAudioMix(roles: [.desktop, .microphone], desktopVolume: 1, microphoneVolume: 1))
		defer { try? FileManager.default.removeItem(at: output) }

		let asset = AVURLAsset(url: output)
		let videoTracks = try await asset.loadTracks(withMediaType: .video)
		let video = try XCTUnwrap(videoTracks.first)
		let range = try await video.load(.timeRange)
		XCTAssertEqual(range.duration.seconds, 8, accuracy: 0.5, "Both segments' video must survive the copy")
		// the whole file must decode end to end
		let reader = try AVAssetReader(asset: asset)
		let out = AVAssetReaderTrackOutput(track: video, outputSettings: [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
		])
		reader.add(out)
		XCTAssertTrue(reader.startReading())
		var frames = 0
		while out.copyNextSampleBuffer() != nil { frames += 1 }
		XCTAssertEqual(reader.status, .completed, "\(String(describing: reader.error))")
		XCTAssertGreaterThan(frames, Int(fps) * 7)
	}
}
