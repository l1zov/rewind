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
	private var _onCaptureStopped: ((String?) -> Void)?
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
	var onCaptureStopped: ((String?) -> Void)? {
		get { callbackLock.withLock { _onCaptureStopped } }
		set { callbackLock.withLock { _onCaptureStopped = newValue } }
	}

	private(set) var displaySize: CGSize?

	private var stream: SCStream?
	private let stopObserver = RewindStreamStopObserver()
	private let videoQueue: DispatchQueue
	private let audioQueue: DispatchQueue
	private var captureResolution: CaptureResolution?
	private var followTask: Task<Void, Never>?

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
		stopObserver.onStop = { [weak self] reason in
			guard let self else { return }
			let stoppedCallback = self.onCaptureStopped
			stoppedCallback?(reason)
		}
	}

	func startCapture(
		contentFilter: UncheckedSendable<SCContentFilter>? = nil,
		resolution: CaptureResolution? = nil,
		quality: QualityPreset = .default,
		frameRate: Int = CaptureFrameRate.default.framesPerSecond,
		recordMicrophone: Bool = false,
		recordDesktopAudio: Bool = true,
		microphoneDeviceID: String? = nil
	) async throws {
		guard stream == nil else { return }

		// A display/window picked via SCContentSharingPicker is captured exactly.
		// A picked app, or no pick at all (frontmost app), is followed across
		// displays: the stream records whichever display shows its frontmost window.
		let providedFilter = contentFilter?.value
		let followTarget: DisplayFollowTarget?
		if let providedFilter {
			followTarget = DisplayFollowTarget(pickerFilter: providedFilter)
		} else {
			followTarget = .frontmostApplication
		}

		let filter: SCContentFilter
		let startLocation: DisplayFollowLocation?
		var nativeWidth = 0
		var nativeHeight = 0
		if let followTarget {
			let content = try await SCShareableContent.loadOnScreen()
			// Start where the target's window is; if it has none on screen yet, use
			// the display the picker chose, else the main display.
			let location = await DisplayFollower.currentLocation(for: followTarget)
			let startID = location?.displayID
				?? providedFilter.flatMap(DisplayFollower.pickedDisplayID(of:))
				?? CGMainDisplayID()
			guard let startDisplay = content.displays.first(where: { $0.displayID == startID })
				?? content.displays.first,
				let largest = DisplayFollower.largestDisplay(in: content)
			else {
				throw CaptureError.noDisplay
			}
			let pid: pid_t? = if let location {
				location.pid
			} else {
				await DisplayFollower.currentPID(for: followTarget)
			}
			// The picked app may have quit since it was chosen; record the pick as-is
			// until it relaunches.
			filter = pid.flatMap {
				DisplayFollower.makeFilter(for: followTarget, pid: $0, on: startDisplay, content: content)
			} ?? providedFilter ?? SCContentFilter(
				display: startDisplay, excludingApplications: [], exceptingWindows: []
			)
			startLocation = DisplayFollowLocation(
				pid: followTarget == .frontmostApplication ? 0 : (pid ?? 0),
				displayID: startDisplay.displayID
			)
			// The writer's size is fixed for the session; size it to the biggest
			// display so following onto it never loses detail.
			nativeWidth = largest.width
			nativeHeight = largest.height
			AppLog.info(
				.capture, "ScreenCaptureService: following", followTarget, "starting on display",
				startDisplay.displayID, "sized to largest display", largest.display.displayID
			)
		} else if let providedFilter {
			filter = providedFilter
			startLocation = nil
			AppLog.debug(.capture, "ScreenCaptureService: using picker-provided content filter")
			if #available(macOS 14.0, *) {
				let scale = CGFloat(filter.pointPixelScale)
				let contentRect = filter.contentRect
				nativeWidth = finitePixelDimension(contentRect.width * scale) ?? 0
				nativeHeight = finitePixelDimension(contentRect.height * scale) ?? 0
				AppLog.debug(
					.capture, "ScreenCaptureService: contentRect:", contentRect.width, "x",
					contentRect.height, "pointPixelScale:", scale
				)
			}
		} else {
			throw CaptureError.noDisplay
		}

		guard nativeWidth > 1, nativeHeight > 1 else {
			throw CaptureError.noDisplay
		}

		AppLog.debug(
			.capture, "ScreenCaptureService: native pixels:", nativeWidth, "x", nativeHeight
		)

		// "Native" resolutions in the menu are a hint; re-derive them from the
		// content actually being captured.
		let targetResolution: CaptureResolution
		if let resolution, !resolution.isNative {
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
		// The writer's video size is fixed for the whole session, so when the stream
		// may hop to a display of a different size it must scale into that size.
		config.scalesToFit = followTarget != nil
			|| (config.width != nativeWidth) || (config.height != nativeHeight)
		config.preservesAspectRatio = true
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

		let stream = SCStream(filter: filter, configuration: config, delegate: stopObserver)
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
		if let followTarget, let startLocation {
			startFollowingDisplay(
				followTarget, stream: UncheckedSendable(stream), startLocation: startLocation
			)
		}
	}

	/// Polls where the target's frontmost window is and retargets the running
	/// stream at that display (and app process), so only one display is recorded
	/// at a time.
	private func startFollowingDisplay(
		_ target: DisplayFollowTarget, stream: UncheckedSendable<SCStream>,
		startLocation: DisplayFollowLocation
	) {
		followTask?.cancel()
		followTask = Task {
			var debouncer = DisplaySwitchDebouncer(current: startLocation)
			while !Task.isCancelled {
				try? await Task.sleep(nanoseconds: DisplayFollower.pollIntervalNanos)
				if Task.isCancelled { break }
				var candidate = await DisplayFollower.currentLocation(for: target)
				if target == .frontmostApplication, let found = candidate {
					// A whole-display filter doesn't depend on which app is in front.
					candidate = DisplayFollowLocation(pid: 0, displayID: found.displayID)
				}
				guard let next = debouncer.observe(candidate) else { continue }
				do {
					let content = try await SCShareableContent.loadOnScreen()
					guard
						let display = content.displays.first(where: { $0.displayID == next.displayID }),
						let filter = DisplayFollower.makeFilter(
							for: target, pid: next.pid, on: display, content: content
						)
					else {
						continue
					}
					if Task.isCancelled { break }
					try await stream.value.updateContentFilter(filter)
					debouncer.didSwitch(to: next)
					AppLog.info(
						.capture, "ScreenCaptureService: switched capture to display", next.displayID,
						"pid", next.pid
					)
				} catch {
					if Task.isCancelled { break }
					AppLog.error(.capture, "ScreenCaptureService: display switch failed", error: error)
				}
			}
		}
	}

	private func capturePixelFormat(for quality: QualityPreset) -> OSType {
		_ = quality
		return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
	}

	func stopCapture() async {
		followTask?.cancel()
		followTask = nil
		guard let stream = stream else { return }
		_ = try? await stream.stopCapture()
		self.stream = nil
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
