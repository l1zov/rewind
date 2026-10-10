import AVFoundation
import CoreGraphics
import RewindObjCSupport
@preconcurrency import ScreenCaptureKit

/// this type is used across CaptureManager actor isolation and ScreenCaptureKit callback queues
/// callback handlers and cross queue debug flags are lock protected and blah blah too complicated
final class ScreenCaptureService: NSObject, SCStreamOutput, @unchecked Sendable {
	private let callbackLock = NSLock()
	private var _onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?
	private var _onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?
	private var _onMicSampleBuffer: ((CMSampleBuffer) -> Void)?
	private var _onCaptureStopped: ((UInt64, String?) -> Void)?
	private let stateLock = NSLock()
	private var _loggedNonCompleteFrame = false
	private var _loggedMissingImageBuffer = false
	private var _loggedFirstFrame = false

	var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)? {
		get { callbackLock.withLock { _onVideoSampleBuffer } }
		set { callbackLock.withLock { _onVideoSampleBuffer = newValue } }
	}

	var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)? {
		get { callbackLock.withLock { _onAudioSampleBuffer } }
		set { callbackLock.withLock { _onAudioSampleBuffer = newValue } }
	}

	var onMicSampleBuffer: ((CMSampleBuffer) -> Void)? {
		get { callbackLock.withLock { _onMicSampleBuffer } }
		set { callbackLock.withLock { _onMicSampleBuffer = newValue } }
	}

	/// Reports the stop reason as a plain string rather than an `Error`. See
	/// `RewindStreamStopObserver` — the framework's error object cannot be
	/// safely bridged into Swift or held past the delegate callback.
	var onCaptureStopped: ((UInt64, String?) -> Void)? {
		get { callbackLock.withLock { _onCaptureStopped } }
		set { callbackLock.withLock { _onCaptureStopped = newValue } }
	}

	private(set) var displaySize: CGSize?

	private var stream: SCStream?
	private var stopObserver: RewindStreamStopObserver?
	private var nextStreamGeneration: UInt64 = 0
	private let videoQueue: DispatchQueue
	private let audioQueue: DispatchQueue
	private var captureResolution: CaptureResolution?

	private var loggedNonCompleteFrame: Bool {
		get { stateLock.withLock { _loggedNonCompleteFrame } }
		set { stateLock.withLock { _loggedNonCompleteFrame = newValue } }
	}

	private var loggedMissingImageBuffer: Bool {
		get { stateLock.withLock { _loggedMissingImageBuffer } }
		set { stateLock.withLock { _loggedMissingImageBuffer = newValue } }
	}

	private var loggedFirstFrame: Bool {
		get { stateLock.withLock { _loggedFirstFrame } }
		set { stateLock.withLock { _loggedFirstFrame = newValue } }
	}

	init(
		sampleQueue: DispatchQueue = DispatchQueue(label: "rewind.screencapture.video"),
		audioQueue: DispatchQueue = DispatchQueue(label: "rewind.screencapture.audio")
	) {
		videoQueue = sampleQueue
		self.audioQueue = audioQueue
		super.init()
	}

	func startCapture(
		contentFilter: UncheckedSendable<SCContentFilter>? = nil,
		resolution: CaptureResolution? = nil,
		quality: QualityPreset = .default,
		frameRate: Int = CaptureFrameRate.default.framesPerSecond,
		recordMicrophone: Bool = false,
		recordDesktopAudio: Bool = true,
		microphoneDeviceID: String? = nil
	) async throws -> UInt64 {
		guard stream == nil else { throw CaptureManager.SessionError.alreadyActive }

		// When the user picked a display/window/app via SCContentSharingPicker we
		// capture exactly that; otherwise fall back to the primary display.
		let filter: SCContentFilter
		let display: SCDisplay?
		if let providedFilter = contentFilter?.value {
			filter = providedFilter
			display = nil
			AppLog.debug(.capture, "ScreenCaptureService: using picker-provided content filter")
		} else {
			let content: SCShareableContent
			if #available(macOS 14.0, *) {
				content = try await SCShareableContent.excludingDesktopWindows(
					false, onScreenWindowsOnly: true
				)
			} else {
				content = try await SCShareableContent.current
			}
			guard let primaryDisplay = content.displays.first else {
				throw CaptureError.noDisplay
			}
			display = primaryDisplay
			filter = SCContentFilter(
				display: primaryDisplay, excludingApplications: [], exceptingWindows: []
			)
		}

		var nativeWidth = 0
		var nativeHeight = 0

		if #available(macOS 14.0, *) {
			let scale = CGFloat(filter.pointPixelScale)
			let contentRect = filter.contentRect
			nativeWidth = finitePixelDimension(contentRect.width * scale) ?? 0
			nativeHeight = finitePixelDimension(contentRect.height * scale) ?? 0
			AppLog.debug(
				.capture, "ScreenCaptureService: contentRect:", contentRect.width, "x",
				contentRect.height
			)
			AppLog.debug(.capture, "ScreenCaptureService: pointPixelScale:", scale)
		}

		// The display-based fallback only applies to a whole-display capture; a
		// picker-provided window/app filter always reports a valid contentRect.
		if nativeWidth <= 1 || nativeHeight <= 1, let display {
			let displayID = display.displayID
			if let mode = CGDisplayCopyDisplayMode(displayID) {
				nativeWidth = mode.pixelWidth
				nativeHeight = mode.pixelHeight
				AppLog.debug(
					.capture, "ScreenCaptureService: fallback to CGDisplayMode pixels:",
					nativeWidth, "x", nativeHeight
				)
			} else {
				nativeWidth = display.width
				nativeHeight = display.height
				AppLog.debug(
					.capture, "ScreenCaptureService: fallback to display properties:", nativeWidth,
					"x", nativeHeight
				)
			}
		}

		guard nativeWidth > 1, nativeHeight > 1 else {
			throw CaptureError.noDisplay
		}

		AppLog.debug(
			.capture, "ScreenCaptureService: native pixels:", nativeWidth, "x", nativeHeight
		)

		let targetResolution: CaptureResolution
		if let resolution {
			targetResolution = resolution
		} else {
			targetResolution = .native(width: nativeWidth, height: nativeHeight)
		}

		captureResolution = targetResolution
		var outputSize = targetResolution.alignedSize

		#if arch(x86_64)
			// intel hardware hevc encoder crash if initialized above 4K
			// cap the maximum capture dimensions to 4k (3840x2160 or 4096x2160)
			let maxIntelWidth: CGFloat = 4096
			let maxIntelHeight: CGFloat = 2160
			if outputSize.width > maxIntelWidth || outputSize.height > maxIntelHeight {
				let scale = min(
					maxIntelWidth / outputSize.width, maxIntelHeight / outputSize.height
				)
				let newWidth = Int((outputSize.width * scale).rounded())
				let newHeight = Int((outputSize.height * scale).rounded())
				outputSize = CGSize(
					width: max(2, newWidth - (newWidth % 2)),
					height: max(2, newHeight - (newHeight % 2))
				)
				AppLog.info(
					.capture,
					"Capped Intel capture resolution to \(outputSize.width)x\(outputSize.height)"
				)
			}
		#endif

		let config = SCStreamConfiguration()
		config.width = Int(outputSize.width)
		config.height = Int(outputSize.height)
		config.scalesToFit = (config.width != nativeWidth) || (config.height != nativeHeight)
		config.queueDepth = 8
		config.pixelFormat = capturePixelFormat(for: quality)
		config.colorSpaceName = CGColorSpace.sRGB
		config.capturesAudio = recordDesktopAudio
		// user controlled
		let clampedFrameRate = max(30, min(frameRate, 120))
		config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(clampedFrameRate))
		config.showsCursor = true

		AppLog.debug(
			.capture,
			"ScreenCaptureService: capture/output config:",
			config.width,
			"x",
			config.height,
			"native:",
			nativeWidth,
			"x",
			nativeHeight,
			targetResolution.isNative ? "(native)" : "(scaled)",
			"scalesToFit:",
			config.scalesToFit
		)

				if #available(macOS 15.0, *) {
			config.captureMicrophone = recordMicrophone
			// nil selects the system default input
			config.microphoneCaptureDeviceID = recordMicrophone ? microphoneDeviceID : nil
		}

		displaySize = outputSize
		loggedFirstFrame = false

		nextStreamGeneration &+= 1
		let generation = nextStreamGeneration
		let observer = RewindStreamStopObserver()
		observer.onStop = { [weak self] reason in
			guard let self else { return }
			let stoppedCallback = self.onCaptureStopped
			stoppedCallback?(generation, reason)
		}
		let stream = SCStream(filter: filter, configuration: config, delegate: observer)
		try stream.addStreamOutput(
			self, type: SCStreamOutputType.screen, sampleHandlerQueue: videoQueue
		)
		if recordDesktopAudio {
			try stream.addStreamOutput(
				self, type: SCStreamOutputType.audio, sampleHandlerQueue: audioQueue
			)
		}
		if #available(macOS 15.0, *) {
			if recordMicrophone {
				try stream.addStreamOutput(
					self, type: SCStreamOutputType.microphone, sampleHandlerQueue: audioQueue
				)
			}
		}
		try await stream.startCapture()
		self.stream = stream
		stopObserver = observer
		return generation
	}

	private func capturePixelFormat(for quality: QualityPreset) -> OSType {
		_ = quality
		return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
	}

	func stopCapture() async {
		guard let stream = stream else { return }
		_ = try? await stream.stopCapture()
		self.stream = nil
		stopObserver = nil
		displaySize = nil
	}

	func stream(
		_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
		of outputType: SCStreamOutputType
	) {
		switch outputType {
		case .screen:
			guard isCompleteVideoFrame(sampleBuffer) else { return }
			guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
				if !loggedMissingImageBuffer {
					AppLog.debug(
						.capture,
						"ScreenCaptureService: missing image buffer for video sample; dropping."
					)
					loggedMissingImageBuffer = true
				}
				return
			}
			// log actual captured frame dimensions once to verify
			if !loggedFirstFrame {
				let actualWidth = CVPixelBufferGetWidth(imageBuffer)
				let actualHeight = CVPixelBufferGetHeight(imageBuffer)
				AppLog.debug(
					.capture, "ScreenCaptureService: actual frame pixels:", actualWidth, "x",
					actualHeight
				)
				loggedFirstFrame = true
			}
			let videoCallback = onVideoSampleBuffer
			videoCallback?(sampleBuffer)
		case .audio:
			let audioCallback = onAudioSampleBuffer
			audioCallback?(sampleBuffer)
		case .microphone:
			let micCallback = onMicSampleBuffer
			micCallback?(sampleBuffer)
		@unknown default:
			return
		}
	}

	private func isCompleteVideoFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
		guard
			let attachments = CMSampleBufferGetSampleAttachmentsArray(
				sampleBuffer, createIfNecessary: false
			)
			as? [[SCStreamFrameInfo: Any]],
			let first = attachments.first,
			let statusValue = first[.status]
		else {
			return true
		}
		let status: SCFrameStatus?
		if let typed = statusValue as? SCFrameStatus {
			status = typed
		} else if let number = statusValue as? NSNumber {
			status = SCFrameStatus(rawValue: number.intValue)
		} else {
			status = nil
		}
		if let status, status != .complete, status != .idle {
			if !loggedNonCompleteFrame {
				AppLog.debug(
					.capture, "ScreenCaptureService: dropping non-complete frame status:",
					status.rawValue
				)
				loggedNonCompleteFrame = true
			}
			return false
		}
		return true
	}
}

extension SCShareableContent: @retroactive @unchecked Sendable {}
