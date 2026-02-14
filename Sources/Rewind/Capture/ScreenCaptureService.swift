import AVFoundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

// this type is used across CaptureManager actor isolation and ScreenCaptureKit callback queues
// callback handlers and cross queue debug flags are lock protected and blah blah too complicated
final class ScreenCaptureService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
  private let callbackLock = NSLock()
  private var _onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?
  private var _onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?
  private var _onCaptureStopped: ((Error?) -> Void)?
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

  var onCaptureStopped: ((Error?) -> Void)? {
    get { callbackLock.withLock { _onCaptureStopped } }
    set { callbackLock.withLock { _onCaptureStopped = newValue } }
  }
  private(set) var displaySize: CGSize?

  private var stream: SCStream?
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
    self.videoQueue = sampleQueue
    self.audioQueue = audioQueue
    super.init()
  }

  func startCapture(
    resolution: CaptureResolution? = nil,
    quality: QualityPreset = .default,
    frameRate: Int = CaptureFrameRate.default.framesPerSecond
  ) async throws {
    guard stream == nil else { return }

    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first else {
      throw CaptureError.noDisplay
    }

    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

    let nativeWidth: Int
    let nativeHeight: Int

    if #available(macOS 14.0, *) {
      let scale = CGFloat(filter.pointPixelScale)
      let contentRect = filter.contentRect
      nativeWidth = Int(contentRect.width * scale)
      nativeHeight = Int(contentRect.height * scale)
      AppLog.debug(.capture, "ScreenCaptureService: contentRect:", contentRect.width, "x", contentRect.height)
      AppLog.debug(.capture, "ScreenCaptureService: pointPixelScale:", scale)
    } else {
      let displayID = display.displayID
      guard let mode = CGDisplayCopyDisplayMode(displayID) else {
        throw CaptureError.noDisplay
      }
      nativeWidth = mode.pixelWidth
      nativeHeight = mode.pixelHeight
      AppLog.debug(.capture, "ScreenCaptureService: CGDisplayMode pixels:", nativeWidth, "x", nativeHeight)
    }

    AppLog.debug(.capture, "ScreenCaptureService: native pixels:", nativeWidth, "x", nativeHeight)

    let targetResolution: CaptureResolution
    if let resolution {
      targetResolution = resolution
    } else {
      targetResolution = .native(width: nativeWidth, height: nativeHeight)
    }

    captureResolution = targetResolution
    let outputSize = targetResolution.alignedSize

    let config = SCStreamConfiguration()
    config.width = nativeWidth
    config.height = nativeHeight
    config.scalesToFit = false
    config.queueDepth = 15
    config.pixelFormat = capturePixelFormat(for: quality)
    config.colorSpaceName = CGColorSpace.extendedSRGB
    config.capturesAudio = true
    // user controlled
    let clampedFrameRate = max(30, min(frameRate, 60))
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(clampedFrameRate))
    config.showsCursor = true

    AppLog.debug(
      .capture,
      "ScreenCaptureService: capture config:",
      config.width,
      "x",
      config.height,
      "output target:",
      Int(outputSize.width),
      "x",
      Int(outputSize.height),
      targetResolution.isNative ? "(native)" : "(scaled)",
      "scalesToFit:",
      config.scalesToFit
    )

    displaySize = outputSize
    loggedFirstFrame = false

    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: SCStreamOutputType.screen, sampleHandlerQueue: videoQueue)
    try stream.addStreamOutput(self, type: SCStreamOutputType.audio, sampleHandlerQueue: audioQueue)
    try await stream.startCapture()
    self.stream = stream
  }

  private func capturePixelFormat(for quality: QualityPreset) -> OSType {
    _ = quality
    return kCVPixelFormatType_32BGRA
  }

  func stopCapture() async {
    guard let stream = stream else { return }
    _ = try? await stream.stopCapture()
    self.stream = nil
    displaySize = nil
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
    switch outputType {
    case .screen:
      guard isCompleteVideoFrame(sampleBuffer) else { return }
      guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        if !loggedMissingImageBuffer {
          AppLog.debug(.capture, "ScreenCaptureService: missing image buffer for video sample; dropping.")
          loggedMissingImageBuffer = true
        }
        return
      }
      // log actual captured frame dimensions once to verify
      if !loggedFirstFrame {
        let actualWidth = CVPixelBufferGetWidth(imageBuffer)
        let actualHeight = CVPixelBufferGetHeight(imageBuffer)
        AppLog.debug(.capture, "ScreenCaptureService: actual frame pixels:", actualWidth, "x", actualHeight)
        loggedFirstFrame = true
      }
      let videoCallback = onVideoSampleBuffer
      videoCallback?(sampleBuffer)
    case .audio:
      let audioCallback = onAudioSampleBuffer
      audioCallback?(sampleBuffer)
    case .microphone:
      return
    @unknown default:
      return
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    let stoppedCallback = onCaptureStopped
    stoppedCallback?(error)
  }

  private func isCompleteVideoFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
          let first = attachments.first,
          let statusValue = first[.status] else {
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
    if let status, status != .complete {
      if !loggedNonCompleteFrame {
        AppLog.debug(.capture, "ScreenCaptureService: dropping non-complete frame status:", status.rawValue)
        loggedNonCompleteFrame = true
      }
      return false
    }
    return true
  }
}

extension SCShareableContent: @retroactive @unchecked Sendable {}
