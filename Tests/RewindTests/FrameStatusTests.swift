import CoreMedia
import CoreVideo
@testable import Rewind
@preconcurrency import ScreenCaptureKit
import XCTest

final class FrameStatusTests: XCTestCase {
	private func frame(status: SCFrameStatus?) -> CMSampleBuffer {
		var pixelBuffer: CVPixelBuffer?
		CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &pixelBuffer)
		var format: CMVideoFormatDescription?
		CMVideoFormatDescriptionCreateForImageBuffer(
			allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer!, formatDescriptionOut: &format)
		var sample: CMSampleBuffer?
		var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
		CMSampleBufferCreateForImageBuffer(
			allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer!, dataReady: true,
			makeDataReadyCallback: nil, refcon: nil, formatDescription: format!,
			sampleTiming: &timing, sampleBufferOut: &sample)
		if let status {
			let array = CMSampleBufferGetSampleAttachmentsArray(sample!, createIfNecessary: true)!
			let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(array, 0), to: CFMutableDictionary.self)
			CFDictionarySetValue(
				dictionary,
				Unmanaged.passUnretained(SCStreamFrameInfo.status.rawValue as CFString).toOpaque(),
				Unmanaged.passUnretained(NSNumber(value: status.rawValue)).toOpaque())
		}
		return sample!
	}

	func testFramesWithoutAStatusAreTreatedAsComplete() {
		XCTAssertNil(ScreenCaptureService.frameStatus(of: frame(status: nil)))
		XCTAssertTrue(ScreenCaptureService.isDeliverable(status: nil))
	}

	func testReadsTheStatusFromTheFrameAttachments() {
		for status in [SCFrameStatus.complete, .idle, .blank, .suspended, .started, .stopped] {
			XCTAssertEqual(ScreenCaptureService.frameStatus(of: frame(status: status)), status, "\(status)")
		}
	}

	func testOnlyCompleteAndIdleFramesAreDelivered() {
		XCTAssertTrue(ScreenCaptureService.isDeliverable(status: .complete))
		XCTAssertTrue(ScreenCaptureService.isDeliverable(status: .idle))
		for status in [SCFrameStatus.blank, .suspended, .started, .stopped] {
			XCTAssertFalse(ScreenCaptureService.isDeliverable(status: status), "\(status)")
		}
	}
}
