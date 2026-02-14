@preconcurrency import AVFoundation
import Accelerate
import CoreGraphics

final class ReplayWriter: @unchecked Sendable {
  enum VideoMode {
    case pixelBufferEncode
    case passthrough
  }

  private enum Constants {
    static let maxPendingAudioSamples = 240
    static let maxPendingVideoSamples = 120
    static let audioJitterTolerance = CMTime(seconds: 0.005, preferredTimescale: 1_000)
    static let maxAudioPTSAdjustment = CMTime(seconds: 0.15, preferredTimescale: 600)
    static let audioBufferingWindow = CMTime(seconds: 0.20, preferredTimescale: 600)
    static let audioSyncTolerance = CMTime(seconds: 0.02, preferredTimescale: 48_000)
    static let videoSyncTolerance = CMTime(seconds: 0.02, preferredTimescale: 600)
    static let audioGapThreshold = CMTime(seconds: 0.04, preferredTimescale: 1_000)
    static let maxGapSeconds: Double = 0.5
    static let silenceChunkSeconds: Double = 0.1
    static let backpressureLogInterval = 30
    static let pendingVideoDropLogInterval = 60
    static let pendingAudioDropLogInterval = 50
    static let pendingVideoDropLogFirst = 1
    static let pendingAudioDropLogFirst = 1
    static let missingAdaptorLogLimit = 1
    static let finishWritingTimeout: TimeInterval = 10.0
    static let defaultFrameRate = 60
  }

  private enum Log {
    static func info(_ items: Any..., separator: String = " ", terminator: String = "\n") {
      AppLog.debug(.writer, items: items, separator: separator)
    }
  }

  // - State ---

  private let queue: DispatchQueue
  private let queueKey = DispatchSpecificKey<Void>()
  private var writer: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var videoAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var audioInput: AVAssetWriterInput?
  private var outputURL: URL?
  private var configuredVideoSize: CGSize?
  private var configuredAudioSettings: [String: Any]?
  private var configuredVideoMode: VideoMode = .pixelBufferEncode
  private var configuredQuality: QualityPreset = .default
  private var configuredFrameRate = Constants.defaultFrameRate
  private var includeAudio = false
  private var requiresAudioForSession = false
  private var sessionStarted = false
  private var sessionStartPTS = CMTime.invalid
  private var audioPTSOffset = CMTime.zero
  private var audioPTSOffsetValid = false
  private var audioBufferingEndPTS = CMTime.invalid
  private var acceptsMediaData = false
  private var lastVideoPTS = CMTime.invalid
  private var lastAudioEndPTS = CMTime.invalid
  private var loggedFirstVideoBuffer = false
  private var loggedFirstAudioBuffer = false
  private var loggedNoPixelBufferFormat = false
  private var missingAdaptorDrops = 0
  private var missingAudioInputLogged = false
  private var audioSampleRate: Double?
  private var audioFormatDescription: CMAudioFormatDescription?
  private var audioASBD: AudioStreamBasicDescription?
  private var videoBackpressureDrops = 0
  private var loggedFirstScaledFrame = false
  private var scaleFailureDrops = 0
  private var reconfigureCount = 0

  /// queue to buffer audio samples before video session starts
  private var pendingAudioSamples: ArraySlice<CMSampleBuffer> = []
  private var pendingAudioDrops = 0
  private var audioRequestStarted = false
  private var pendingVideoSamples: ArraySlice<CMSampleBuffer> = []
  private var pendingVideoDrops = 0

  /// track the first audio sample PTS to detect audio-video timestamp offset
  private var firstAudioPTS = CMTime.invalid
  private var firstVideoPTS = CMTime.invalid

  // - Init ---

  init(queue: DispatchQueue) {
    self.queue = queue
    self.queue.setSpecific(key: queueKey, value: ())
  }

  // - Configuration ---

  func configure(
    outputURL: URL,
    videoSize: CGSize,
    includeAudio: Bool,
    audioSettings: [String: Any]?,
    videoMode: VideoMode = .pixelBufferEncode,
    quality: QualityPreset = .default,
    frameRate: Int = Constants.defaultFrameRate
  ) throws {
    var configureError: Error?
    syncOnQueue {
      do {
        try configureOnQueue(
          outputURL: outputURL,
          videoSize: videoSize,
          includeAudio: includeAudio,
          audioSettings: audioSettings,
          videoMode: videoMode,
          quality: quality,
          frameRate: frameRate
        )
      } catch {
        configureError = error
      }
    }

    if let configureError { throw configureError }
  }

  private func configureOnQueue(
    outputURL: URL,
    videoSize: CGSize,
    includeAudio: Bool,
    audioSettings: [String: Any]?,
    videoMode: VideoMode,
    quality: QualityPreset,
    frameRate: Int
  ) throws {
    guard outputURL.isFileURL else {
      throw CaptureError.exportFailed
    }
    let folder = outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: outputURL)

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    let videoInput: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor?
    var configuredSize: CGSize?
    if videoMode == .pixelBufferEncode {
      let width = Int(videoSize.width.rounded())
      let height = Int(videoSize.height.rounded())
      Log.info("ReplayWriter.configure video size:", width, "x", height)
      configuredSize = CGSize(width: width, height: height)

      let sourcePixelFormat = sourcePixelFormat(for: quality)
      let estimatedBitrate = targetBitrateMbps(for: quality, videoSize: CGSize(width: width, height: height), frameRate: frameRate)
      Log.info(
        "ReplayWriter.configure codec: HEVC, preset:",
        quality.label,
        "target bitrate:",
        String(format: "%.1f", estimatedBitrate),
        "Mbps"
      )

      var videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
      ]
      videoSettings[AVVideoCompressionPropertiesKey] = videoCompressionProperties(
        for: quality,
        videoSize: CGSize(width: width, height: height),
        frameRate: frameRate
      )
      videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)

      let adaptorAttrs: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(sourcePixelFormat),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
      ]
      adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: videoInput,
        sourcePixelBufferAttributes: adaptorAttrs
      )
    } else {
      Log.info("ReplayWriter.configure video mode: passthrough")
      videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
      adaptor = nil
      configuredSize = nil
    }
    videoInput.expectsMediaDataInRealTime = true
    guard writer.canAdd(videoInput) else {
      throw CaptureError.exportFailed
    }
    writer.add(videoInput)

    var audioInput: AVAssetWriterInput?
    if includeAudio {
      let primaryAudio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
      primaryAudio.expectsMediaDataInRealTime = true
      if writer.canAdd(primaryAudio) {
        writer.add(primaryAudio)
        audioInput = primaryAudio
      } else {
        Log.info("ReplayWriter.configure: cannot add audio input with settings:", audioSettings ?? [:])
      }
    }

    self.writer = writer
    self.videoInput = videoInput
    self.videoAdaptor = adaptor
    self.audioInput = audioInput
    self.outputURL = outputURL
    self.configuredVideoSize = configuredSize
    self.configuredAudioSettings = audioSettings
    self.configuredVideoMode = videoMode
    self.configuredQuality = quality
    self.configuredFrameRate = frameRate
    self.includeAudio = includeAudio
    self.requiresAudioForSession = includeAudio && audioInput != nil

    resetRuntimeState(resetReconfigureCount: true)
    acceptsMediaData = true
  }

  private func sourcePixelFormat(for quality: QualityPreset) -> OSType {
    _ = quality
    // keep writer input buffers in BGRA so we can apply high-quality software scaling
    // before the frame reaches the encoder.
    return kCVPixelFormatType_32BGRA
  }

  private func videoCompressionProperties(
    for quality: QualityPreset,
    videoSize: CGSize,
    frameRate: Int
  ) -> [String: Any] {
    let normalizedFrameRate = max(30, min(frameRate, 60))
    let averageBitrateMbps = targetBitrateMbps(for: quality, videoSize: videoSize, frameRate: normalizedFrameRate)
    let averageBitrate = Int((averageBitrateMbps * 1_000_000).rounded())
    let keyframeInterval = max(normalizedFrameRate, Int((Double(normalizedFrameRate) * 1.5).rounded()))

    return [
      AVVideoAverageBitRateKey: averageBitrate,
      AVVideoExpectedSourceFrameRateKey: normalizedFrameRate,
      AVVideoMaxKeyFrameIntervalKey: keyframeInterval,
      AVVideoMaxKeyFrameIntervalDurationKey: 1.5,
      AVVideoAllowFrameReorderingKey: true
    ]
  }

  private func targetBitrateMbps(for quality: QualityPreset, videoSize: CGSize, frameRate: Int) -> Double {
    let width = max(1, Int(videoSize.width.rounded()))
    let height = max(1, Int(videoSize.height.rounded()))
    let fps = max(30, min(frameRate, 60))

    let pixelsPerFrame = Double(width * height)
    let bitsPerSecond = quality.bitsPerPixel * pixelsPerFrame * Double(fps)
    let bitrateMbps = bitsPerSecond / 1_000_000
    return min(max(bitrateMbps, quality.minBitrateMbps), quality.maxBitrateMbps)
  }

  private func resetRuntimeState(resetReconfigureCount: Bool) {
    acceptsMediaData = false
    sessionStarted = false
    sessionStartPTS = CMTime.invalid
    audioPTSOffset = .zero
    audioPTSOffsetValid = false
    audioBufferingEndPTS = CMTime.invalid
    lastVideoPTS = CMTime.invalid
    lastAudioEndPTS = CMTime.invalid
    loggedFirstVideoBuffer = false
    loggedFirstAudioBuffer = false
    loggedNoPixelBufferFormat = false
    missingAdaptorDrops = 0
    missingAudioInputLogged = false
    audioSampleRate = nil
    audioFormatDescription = nil
    audioASBD = nil
    videoBackpressureDrops = 0
    loggedFirstScaledFrame = false
    scaleFailureDrops = 0
    pendingAudioSamples.removeAll()
    pendingVideoSamples.removeAll()
    pendingVideoDrops = 0
    pendingAudioDrops = 0
    audioRequestStarted = false
    firstAudioPTS = CMTime.invalid
    firstVideoPTS = CMTime.invalid
    if resetReconfigureCount {
      reconfigureCount = 0
    }
  }

  private func resetState() {
    writer = nil
    videoInput = nil
    videoAdaptor = nil
    audioInput = nil
    outputURL = nil
    configuredVideoSize = nil
    configuredAudioSettings = nil
    configuredVideoMode = .pixelBufferEncode
    configuredQuality = .default
    configuredFrameRate = Constants.defaultFrameRate
    includeAudio = false
    requiresAudioForSession = false
    resetRuntimeState(resetReconfigureCount: false)
  }

  // - Append Video ---

  func appendVideo(_ sampleBuffer: CMSampleBuffer) {
    let buffer = UncheckedSendable(sampleBuffer)
    onQueue { [weak self] in
      self?.appendVideoOnQueue(buffer.value)
    }
  }

  private func appendVideoOnQueue(_ sampleBuffer: CMSampleBuffer) {
    guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
    guard acceptsMediaData else { return }
    guard let writer = writer, let videoInput = videoInput else { return }

    if CMSampleBufferGetImageBuffer(sampleBuffer) == nil, !loggedNoPixelBufferFormat {
      if let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
        let mediaSubType = CMFormatDescriptionGetMediaSubType(format)
        Log.info("ReplayWriter.appendVideo no CVPixelBuffer. mediaSubType:", String(format: "0x%08X", mediaSubType))
      }
      loggedNoPixelBufferFormat = true
    }

    let pixelBufferForMode = CMSampleBufferGetImageBuffer(sampleBuffer)
    let desiredMode: VideoMode = (pixelBufferForMode != nil) ? .pixelBufferEncode : .passthrough
    if reconfigureForVideoModeIfNeeded(desiredMode: desiredMode, pixelBuffer: pixelBufferForMode) {
      return
    }

    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if !firstVideoPTS.isValid {
      firstVideoPTS = pts
    }

    if !sessionStarted {
      enqueuePendingVideoSample(sampleBuffer)
      startSessionIfNeeded()
      return
    }

    if !pendingVideoSamples.isEmpty {
      enqueuePendingVideoSample(sampleBuffer)
      drainPendingVideoIfReady(writer: writer, videoInput: videoInput)
      return
    }

    if writer.status == .failed {
      logAppendFailure(
        label: "ReplayWriter.appendVideo writer failed",
        writer: writer,
        videoInput: videoInput,
        sampleBuffer: sampleBuffer
      )
      acceptsMediaData = false
      return
    }

    guard writer.status == .writing else { return }
    appendVideoSample(sampleBuffer, writer: writer, videoInput: videoInput)
    if let audioInput = audioInput {
      startAudioRequestIfNeeded(audioInput: audioInput, writer: writer)
    }
  }

  private func reconfigureForVideoModeIfNeeded(
    desiredMode: VideoMode,
    pixelBuffer: CVPixelBuffer?
  ) -> Bool {
    guard let writer = writer,
          writer.status == .unknown,
          configuredVideoMode != desiredMode else { return false }

    reconfigureCount += 1
    Log.info("⚠️ ReplayWriter.appendVideo reconfigure #\(reconfigureCount) for mode:", desiredMode)
    guard let outputURL = outputURL else { return true }

    let desiredSize: CGSize
    if let pixelBuffer {
      desiredSize = CGSize(
        width: CVPixelBufferGetWidth(pixelBuffer),
        height: CVPixelBufferGetHeight(pixelBuffer)
      )
    } else {
      desiredSize = configuredVideoSize ?? .zero
    }

    do {
      try configureOnQueue(
        outputURL: outputURL,
        videoSize: desiredSize,
        includeAudio: includeAudio,
        audioSettings: configuredAudioSettings,
        videoMode: desiredMode,
        quality: configuredQuality,
        frameRate: configuredFrameRate
      )
    } catch {
      logWriterError("ReplayWriter.appendVideo reconfigure failed", error)
      acceptsMediaData = false
    }
    return true
  }

  private func appendVideoSample(_ sampleBuffer: CMSampleBuffer, writer: AVAssetWriter, videoInput: AVAssetWriterInput) {
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if !loggedFirstVideoBuffer, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
      let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
      let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
      let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
      Log.info("ReplayWriter.appendVideo first buffer:", bufferWidth, "x", bufferHeight, "format:", String(format: "0x%08X", format))

      // verify whether source frames match encoder size.
      // non-native presets intentionally capture at native and scale in software.
      if let configuredSize = configuredVideoSize {
        let configuredWidth = Int(configuredSize.width)
        let configuredHeight = Int(configuredSize.height)
        if bufferWidth != configuredWidth || bufferHeight != configuredHeight {
          Log.info(
            "ReplayWriter: source/encode size mismatch; software scaling active. buffer:",
            bufferWidth,
            "x",
            bufferHeight,
            "configured:",
            configuredWidth,
            "x",
            configuredHeight
          )
        } else {
          Log.info("ReplayWriter: buffer size matches configured size ✓")
        }
      }

      loggedFirstVideoBuffer = true
    }
    if lastVideoPTS.isValid, pts < lastVideoPTS {
      Log.info("ReplayWriter.appendVideo non-monotonic PTS. last:", lastVideoPTS.seconds, "now:", pts.seconds)
    }
    lastVideoPTS = pts

    if videoInput.isReadyForMoreMediaData {
      if configuredVideoMode == .passthrough {
        if !videoInput.append(sampleBuffer) {
          logAppendFailure(
            label: "ReplayWriter.appendVideo passthrough append failed",
            writer: writer,
            videoInput: videoInput,
            sampleBuffer: sampleBuffer
          )
          acceptsMediaData = false
        }
      } else {
        guard let adaptor = videoAdaptor,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
          if missingAdaptorDrops < Constants.missingAdaptorLogLimit {
            let adaptorMissing = videoAdaptor == nil
            let pixelMissing = CMSampleBufferGetImageBuffer(sampleBuffer) == nil
            Log.info("ReplayWriter.appendVideo adaptor missing; dropping frame. adaptorNil:", adaptorMissing, "pixelBufferNil:", pixelMissing)
          }
          missingAdaptorDrops += 1
          return
        }

        let bufferToAppend: CVPixelBuffer
        if let preparedBuffer = pixelBufferForEncoding(pixelBuffer, adaptor: adaptor) {
          bufferToAppend = preparedBuffer
        } else if let configuredSize = configuredVideoSize,
                  (CVPixelBufferGetWidth(pixelBuffer) != Int(configuredSize.width)
                    || CVPixelBufferGetHeight(pixelBuffer) != Int(configuredSize.height)) {
          scaleFailureDrops += 1
          if scaleFailureDrops == 1 || scaleFailureDrops % Constants.pendingVideoDropLogInterval == 0 {
            Log.info("ReplayWriter.appendVideo scaling failed; dropping frame. drops:", scaleFailureDrops)
          }
          return
        } else {
          bufferToAppend = pixelBuffer
        }

        if !adaptor.append(bufferToAppend, withPresentationTime: pts) {
          logAppendFailure(
            label: "ReplayWriter.appendVideo adaptor append failed",
            writer: writer,
            videoInput: videoInput,
            sampleBuffer: sampleBuffer
          )
          acceptsMediaData = false
        }
      }
    } else {
      // track backpressure drops; this indicates the encoder cant keep up
      videoBackpressureDrops += 1
      if videoBackpressureDrops == 1 || videoBackpressureDrops % Constants.backpressureLogInterval == 0 {
        Log.info("ReplayWriter.appendVideo backpressure drop count:", videoBackpressureDrops)
      }
    }
  }

  private func pixelBufferForEncoding(
    _ pixelBuffer: CVPixelBuffer,
    adaptor: AVAssetWriterInputPixelBufferAdaptor
  ) -> CVPixelBuffer? {
    guard let configuredVideoSize else { return pixelBuffer }

    let targetWidth = Int(configuredVideoSize.width.rounded())
    let targetHeight = Int(configuredVideoSize.height.rounded())
    let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
    let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)

    guard sourceWidth != targetWidth || sourceHeight != targetHeight else {
      return pixelBuffer
    }

    guard let pool = adaptor.pixelBufferPool else {
      Log.info("ReplayWriter.appendVideo missing pixel buffer pool for scaling")
      return nil
    }

    var scaledPixelBuffer: CVPixelBuffer?
    let poolStatus = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &scaledPixelBuffer)
    guard poolStatus == kCVReturnSuccess, let scaledPixelBuffer else {
      Log.info("ReplayWriter.appendVideo unable to create scaled pixel buffer. status:", poolStatus)
      return nil
    }

    guard scaleBGRA(pixelBuffer, to: scaledPixelBuffer) else {
      return nil
    }

    if !loggedFirstScaledFrame {
      let scaledWidth = CVPixelBufferGetWidth(scaledPixelBuffer)
      let scaledHeight = CVPixelBufferGetHeight(scaledPixelBuffer)
      Log.info("ReplayWriter.appendVideo scaled frame:", sourceWidth, "x", sourceHeight, "->", scaledWidth, "x", scaledHeight)
      loggedFirstScaledFrame = true
    }

    return scaledPixelBuffer
  }

  private func scaleBGRA(_ source: CVPixelBuffer, to destination: CVPixelBuffer) -> Bool {
    let sourceFormat = CVPixelBufferGetPixelFormatType(source)
    let destinationFormat = CVPixelBufferGetPixelFormatType(destination)
    guard sourceFormat == kCVPixelFormatType_32BGRA,
          destinationFormat == kCVPixelFormatType_32BGRA else {
      Log.info(
        "ReplayWriter.appendVideo unsupported scaling format. source:",
        String(format: "0x%08X", sourceFormat),
        "destination:",
        String(format: "0x%08X", destinationFormat)
      )
      return false
    }

    CVPixelBufferLockBaseAddress(source, .readOnly)
    CVPixelBufferLockBaseAddress(destination, [])
    defer {
      CVPixelBufferUnlockBaseAddress(destination, [])
      CVPixelBufferUnlockBaseAddress(source, .readOnly)
    }

    guard let sourceBaseAddress = CVPixelBufferGetBaseAddress(source),
          let destinationBaseAddress = CVPixelBufferGetBaseAddress(destination) else {
      Log.info("ReplayWriter.appendVideo scaling base address unavailable")
      return false
    }

    var sourceBuffer = vImage_Buffer(
      data: sourceBaseAddress,
      height: vImagePixelCount(CVPixelBufferGetHeight(source)),
      width: vImagePixelCount(CVPixelBufferGetWidth(source)),
      rowBytes: CVPixelBufferGetBytesPerRow(source)
    )
    var destinationBuffer = vImage_Buffer(
      data: destinationBaseAddress,
      height: vImagePixelCount(CVPixelBufferGetHeight(destination)),
      width: vImagePixelCount(CVPixelBufferGetWidth(destination)),
      rowBytes: CVPixelBufferGetBytesPerRow(destination)
    )

    let status = vImageScale_ARGB8888(
      &sourceBuffer,
      &destinationBuffer,
      nil,
      vImage_Flags(kvImageHighQualityResampling)
    )
    if status != kvImageNoError {
      Log.info("ReplayWriter.appendVideo vImageScale_ARGB8888 failed. status:", status)
      return false
    }

    return true
  }

  // - Append Audio --- 

  func appendAudio(_ sampleBuffer: CMSampleBuffer) {
    let buffer = UncheckedSendable(sampleBuffer)
    onQueue { [weak self] in
      self?.appendAudioOnQueue(buffer.value)
    }
  }

  private func appendAudioOnQueue(_ sampleBuffer: CMSampleBuffer) {
    guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
    guard acceptsMediaData else { return }
    guard let writer = writer else { return }
    guard let audioInput = audioInput else {
      if includeAudio, !missingAudioInputLogged {
        Log.info("ReplayWriter.appendAudio missing audio input; dropping audio.")
        logAudioFormat(sampleBuffer)
        missingAudioInputLogged = true
      }
      return
    }

    if writer.status == .failed {
      logAudioAppendFailure(
        label: "ReplayWriter.appendAudio writer failed",
        writer: writer,
        audioInput: audioInput,
        sampleBuffer: sampleBuffer
      )
      acceptsMediaData = false
      return
    }

    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if !firstAudioPTS.isValid || pts < firstAudioPTS {
      firstAudioPTS = pts
    }

    // buffer audio samples until session starts to prevent audio loss
    guard sessionStarted, writer.status == .writing, sessionStartPTS.isValid else {
      enqueuePendingAudioSample(sampleBuffer)
      startSessionIfNeeded()
      return
    }

    // buffer a short window after session start to tighten alignment
    if audioBufferingEndPTS.isValid, pts < audioBufferingEndPTS {
      enqueuePendingAudioSample(sampleBuffer)
      return
    }
    if audioBufferingEndPTS.isValid {
      audioBufferingEndPTS = .invalid
      flushPendingAudioSamples(audioInput: audioInput, writer: writer)
    }

    if !loggedFirstAudioBuffer {
      logAudioFormat(sampleBuffer)
      loggedFirstAudioBuffer = true
    }

    if lastAudioEndPTS.isValid, pts > lastAudioEndPTS {
      let gap = CMTimeSubtract(pts, lastAudioEndPTS)
      if gap > Constants.audioGapThreshold {
        fillAudioGapIfNeeded(gap: gap, audioInput: audioInput, writer: writer, startPTS: lastAudioEndPTS)
      }
    }

    if !pendingAudioSamples.isEmpty {
      enqueuePendingAudioSample(sampleBuffer)
      drainPendingAudioWhileReady(audioInput: audioInput, writer: writer)
      if !pendingAudioSamples.isEmpty {
        startAudioRequestIfNeeded(audioInput: audioInput, writer: writer)
      }
      return
    }

    // tight tolerance; audio should not be significantly before our session start
    if pts < CMTimeSubtract(sessionStartPTS, Constants.audioSyncTolerance) {
      return
    }

    if audioInput.isReadyForMoreMediaData {
      _ = appendAdjustedAudioSample(sampleBuffer, to: audioInput, writer: writer)
      drainPendingAudioWhileReady(audioInput: audioInput, writer: writer)
    } else {
      enqueuePendingAudioSample(sampleBuffer)
      startAudioRequestIfNeeded(audioInput: audioInput, writer: writer)
    }
  }

  private func appendAdjustedAudioSample(_ sampleBuffer: CMSampleBuffer, to audioInput: AVAssetWriterInput, writer: AVAssetWriter) -> Bool {
    let adjusted = adjustAudioSampleIfNeeded(sampleBuffer)
    if !audioInput.append(adjusted) {
      logAudioAppendFailure(
        label: "ReplayWriter.appendAudio append failed",
        writer: writer,
        audioInput: audioInput,
        sampleBuffer: adjusted
      )
      acceptsMediaData = false
      return false
    }
    let pts = CMSampleBufferGetPresentationTimeStamp(adjusted)
    if let duration = audioDurationForSample(adjusted), duration.isValid, duration > .zero {
      lastAudioEndPTS = CMTimeAdd(pts, duration)
    } else {
      lastAudioEndPTS = pts
    }
    return true
  }

  private func adjustAudioSampleIfNeeded(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
    guard audioPTSOffsetValid else { return sampleBuffer }
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let baselinePTS = CMTimeSubtract(pts, audioPTSOffset)
    guard let sampleDuration = audioDurationForSample(sampleBuffer),
          sampleDuration.isValid,
          sampleDuration > .zero else { return sampleBuffer }

    var timingInfoCount = 0
    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingInfoCount)
    guard timingInfoCount > 0 else { return sampleBuffer }
    var timingInfo: [CMSampleTimingInfo] = Array(
      repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid),
      count: timingInfoCount
    )
    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: timingInfoCount, arrayToFill: &timingInfo, entriesNeededOut: &timingInfoCount)
    let basePTS = timingInfo[0].presentationTimeStamp
    let baseDTS = timingInfo[0].decodeTimeStamp
    let expectedPTS = lastAudioEndPTS.isValid ? lastAudioEndPTS : baselinePTS
    let delta = CMTimeSubtract(pts, expectedPTS)
    if delta.isValid, CMTimeAbsoluteValue(delta) <= Constants.audioJitterTolerance {
      return sampleBuffer
    }
    let correctedFirstPTS = expectedPTS
    for index in 0..<timingInfoCount {
      let originalPTS = timingInfo[index].presentationTimeStamp
      if originalPTS.isValid {
        let delta = basePTS.isValid ? CMTimeSubtract(originalPTS, basePTS) : .zero
        timingInfo[index].presentationTimeStamp = CMTimeAdd(correctedFirstPTS, delta)
      }
      let originalDTS = timingInfo[index].decodeTimeStamp
      if originalDTS.isValid {
        let delta = baseDTS.isValid ? CMTimeSubtract(originalDTS, baseDTS) : .zero
        timingInfo[index].decodeTimeStamp = CMTimeAdd(correctedFirstPTS, delta)
      }
    }
    var newSample: CMSampleBuffer?
    let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                       sampleBuffer: sampleBuffer,
                                                       sampleTimingEntryCount: timingInfoCount,
                                                       sampleTimingArray: &timingInfo,
                                                       sampleBufferOut: &newSample)
    guard status == noErr, let newSample else { return sampleBuffer }
    return newSample
  }

  private func fillAudioGapIfNeeded(
    gap: CMTime,
    audioInput: AVAssetWriterInput,
    writer: AVAssetWriter,
    startPTS: CMTime
  ) {
    guard let format = audioFormatDescription,
          let asbd = audioASBD,
          asbd.mFormatID == kAudioFormatLinearPCM,
          (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0,
          let audioSampleRate,
          audioSampleRate > 0 else {
      Log.info("ReplayWriter.appendAudio gap:", gap.seconds * 1000, "ms (silence padding unavailable)")
      return
    }

    let gapSeconds = min(gap.seconds, Constants.maxGapSeconds)
    let totalFrames = Int((gapSeconds * audioSampleRate).rounded())
    guard totalFrames > 0 else { return }

    let maxFramesPerBuffer = max(1, Int((Constants.silenceChunkSeconds * audioSampleRate).rounded()))
    var remainingFrames = totalFrames
    var cursorPTS = startPTS
    while remainingFrames > 0 {
      let frames = min(remainingFrames, maxFramesPerBuffer)
      if let silence = makeSilenceSampleBuffer(
        formatDescription: format,
        asbd: asbd,
        numFrames: frames,
        pts: cursorPTS
      ) {
        if audioInput.isReadyForMoreMediaData {
          _ = appendAdjustedAudioSample(silence, to: audioInput, writer: writer)
        } else {
          enqueuePendingAudioSample(silence)
        }
      }
      let duration = CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(audioSampleRate.rounded()))
      cursorPTS = CMTimeAdd(cursorPTS, duration)
      remainingFrames -= frames
    }
  }

  private func makeSilenceSampleBuffer(
    formatDescription: CMAudioFormatDescription,
    asbd: AudioStreamBasicDescription,
    numFrames: Int,
    pts: CMTime
  ) -> CMSampleBuffer? {
    guard numFrames > 0 else { return nil }
    let bytesPerFrame: UInt32
    if asbd.mBytesPerFrame > 0 {
      bytesPerFrame = asbd.mBytesPerFrame
    } else {
      let bytesPerSample = max(1, asbd.mBitsPerChannel / 8)
      bytesPerFrame = bytesPerSample * max(1, asbd.mChannelsPerFrame)
    }
    let dataLength = Int(bytesPerFrame) * numFrames
    guard dataLength > 0 else { return nil }

    var blockBuffer: CMBlockBuffer?
    let status = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: dataLength,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: dataLength,
      flags: 0,
      blockBufferOut: &blockBuffer
    )
    guard status == kCMBlockBufferNoErr, let blockBuffer else { return nil }
    CMBlockBufferAssureBlockMemory(blockBuffer)
    CMBlockBufferFillDataBytes(
      with: 0,
      blockBuffer: blockBuffer,
      offsetIntoDestination: 0,
      dataLength: dataLength
    )

    var sampleBuffer: CMSampleBuffer?
    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: CMTimeScale(asbd.mSampleRate.rounded())),
      presentationTimeStamp: pts,
      decodeTimeStamp: .invalid
    )
    var sampleSize = size_t(bytesPerFrame)
    let createStatus = CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuffer,
      formatDescription: formatDescription,
      sampleCount: numFrames,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timing,
      sampleSizeEntryCount: 1,
      sampleSizeArray: &sampleSize,
      sampleBufferOut: &sampleBuffer
    )
    guard createStatus == noErr, let sampleBuffer else { return nil }
    return sampleBuffer
  }

  private func audioDurationForSample(_ sampleBuffer: CMSampleBuffer) -> CMTime? {
    let duration = CMSampleBufferGetDuration(sampleBuffer)
    if duration.isValid, duration > .zero {
      return duration
    }
    let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
    if numSamples > 0, let audioSampleRate, audioSampleRate > 0 {
      return CMTime(value: CMTimeValue(numSamples), timescale: CMTimeScale(audioSampleRate.rounded()))
    }
    return nil
  }

  // - Pending Buffers ---

  private func enqueuePendingVideoSample(_ sampleBuffer: CMSampleBuffer) {
    if pendingVideoSamples.count < Constants.maxPendingVideoSamples {
      pendingVideoSamples.append(sampleBuffer)
    } else {
      pendingVideoDrops += 1
      if pendingVideoDrops == Constants.pendingVideoDropLogFirst
          || pendingVideoDrops % Constants.pendingVideoDropLogInterval == 0 {
        Log.info("ReplayWriter.appendVideo pending buffer full; drops:", pendingVideoDrops)
      }
      pendingVideoSamples.removeFirst()
      pendingVideoSamples.append(sampleBuffer)
    }
  }

  private func enqueuePendingAudioSample(_ sampleBuffer: CMSampleBuffer) {
    if pendingAudioSamples.count < Constants.maxPendingAudioSamples {
      pendingAudioSamples.append(sampleBuffer)
    } else {
      pendingAudioDrops += 1
      if pendingAudioDrops == Constants.pendingAudioDropLogFirst
          || pendingAudioDrops % Constants.pendingAudioDropLogInterval == 0 {
        Log.info("ReplayWriter.appendAudio pending buffer full; drops:", pendingAudioDrops)
      }
      pendingAudioSamples.removeFirst()
      pendingAudioSamples.append(sampleBuffer)
    }
  }

  private func drainPendingAudioWhileReady(audioInput: AVAssetWriterInput, writer: AVAssetWriter) {
    guard writer.status == .writing, !pendingAudioSamples.isEmpty else { return }

    var drained = 0
    while !pendingAudioSamples.isEmpty && audioInput.isReadyForMoreMediaData {
      let sample = pendingAudioSamples.removeFirst()
      if appendAdjustedAudioSample(sample, to: audioInput, writer: writer) {
        drained += 1
      } else {
        break
      }
    }
  }

  private func startAudioRequestIfNeeded(audioInput: AVAssetWriterInput, writer: AVAssetWriter) {
    guard !audioRequestStarted else { return }
    audioRequestStarted = true
    audioInput.requestMediaDataWhenReady(on: queue) { [weak self] in
      guard let self else { return }
      if !self.acceptsMediaData || writer.status != .writing {
        return
      }
      guard !self.pendingAudioSamples.isEmpty else {
        return
      }
      self.drainPendingAudioWhileReady(audioInput: audioInput, writer: writer)
    }
  }

  private func drainPendingVideoIfReady(writer: AVAssetWriter, videoInput: AVAssetWriterInput) {
    guard !pendingVideoSamples.isEmpty,
          writer.status == .writing,
          videoInput.isReadyForMoreMediaData else { return }

    var drained = 0
    while !pendingVideoSamples.isEmpty && videoInput.isReadyForMoreMediaData {
      let sample = pendingVideoSamples.removeFirst()
      appendVideoSample(sample, writer: writer, videoInput: videoInput)
      drained += 1
      if !acceptsMediaData {
        break
      }
    }
  }

  private func flushPendingAudioSamples(audioInput: AVAssetWriterInput, writer: AVAssetWriter) {
    guard !pendingAudioSamples.isEmpty else { return }

    if firstAudioPTS.isValid, firstVideoPTS.isValid, firstAudioPTS < firstVideoPTS {
      let audioVideoOffset = CMTimeSubtract(firstVideoPTS, firstAudioPTS)
      Log.info("ReplayWriter: audio-video offset:", audioVideoOffset.seconds * 1000, "ms (audio started earlier)")
    }

    let minValidPTS = sessionStartPTS

    var droppedCount = 0
    var remaining: [CMSampleBuffer] = []
    for sample in pendingAudioSamples {
      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      if pts < minValidPTS {
        droppedCount += 1
        continue
      }
      remaining.append(sample)
    }

    pendingAudioSamples = ArraySlice(remaining)
    if droppedCount > 0 {
      Log.info("ReplayWriter: flushed pending audio, dropped:", droppedCount)
    }
    startAudioRequestIfNeeded(audioInput: audioInput, writer: writer)
  }

  private func flushPendingVideoSamples(writer: AVAssetWriter, videoInput: AVAssetWriterInput) {
    guard !pendingVideoSamples.isEmpty else { return }
    let minValidPTS = CMTimeSubtract(sessionStartPTS, Constants.videoSyncTolerance)

    var appendedCount = 0
    var droppedCount = 0
    var remaining: [CMSampleBuffer] = []
    for sample in pendingVideoSamples {
      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      if pts < minValidPTS {
        droppedCount += 1
        continue
      }
      if videoInput.isReadyForMoreMediaData {
        appendVideoSample(sample, writer: writer, videoInput: videoInput)
        if acceptsMediaData {
          appendedCount += 1
        } else {
          remaining.append(sample)
          break
        }
      } else {
        remaining.append(sample)
      }
    }

    pendingVideoSamples = ArraySlice(remaining)
    if appendedCount > 0 || droppedCount > 0 {
      Log.info("ReplayWriter: flushed", appendedCount, "pending video samples, dropped:", droppedCount)
    }
  }

  // - Session Lifecycle ---

  private func startSessionIfNeeded() {
    guard !sessionStarted,
          let writer = writer,
          let videoInput = videoInput,
          writer.status == .unknown else { return }
    guard firstVideoPTS.isValid else { return }
    if requiresAudioForSession && !firstAudioPTS.isValid {
      return
    }

    if !writer.startWriting() {
      logWriterError("ReplayWriter.startWriting failed", writer.error)
      acceptsMediaData = false
      return
    }

    let referencePTS = firstVideoPTS

    sessionStartPTS = referencePTS
    writer.startSession(atSourceTime: referencePTS)
    sessionStarted = true
    audioBufferingEndPTS = CMTimeAdd(referencePTS, Constants.audioBufferingWindow)

    if firstAudioPTS.isValid, firstVideoPTS.isValid {
      let offset = CMTimeSubtract(firstAudioPTS, firstVideoPTS)
      let adjustedOffset = CMTimeMaximum(offset, .zero)
      if adjustedOffset <= Constants.maxAudioPTSAdjustment {
        audioPTSOffset = adjustedOffset
        audioPTSOffsetValid = true
      } else {
        audioPTSOffset = .zero
        audioPTSOffsetValid = true
      }
      Log.info("ReplayWriter: audio PTS offset (audio follows video):", audioPTSOffset.seconds * 1000, "ms")
    }

    flushPendingVideoSamples(writer: writer, videoInput: videoInput)
    if let audioInput = audioInput {
      flushPendingAudioSamples(audioInput: audioInput, writer: writer)
    }
  }

  func finishWriting() async throws -> URL {
    let result = try await withThrowingTaskGroup(of: URL.self) { group in
      group.addTask {
        try await self.finishWritingInternal()
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(Constants.finishWritingTimeout * 1_000_000_000))
        throw CaptureError.exportFailed
      }
      guard let result = try await group.next() else {
        throw CaptureError.writerUnavailable
      }
      group.cancelAll()
      return result
    }
    return result
  }

  private func finishWritingInternal() async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      self.onQueue {
        guard let writer = self.writer, let outputURL = self.outputURL else {
          Log.info("ReplayWriter.finishWriting: writer unavailable.")
          continuation.resume(throwing: CaptureError.writerUnavailable)
          return
        }

        guard self.sessionStarted else {
          Log.info("ReplayWriter.finishWriting: no session started.")
          self.resetState()
          continuation.resume(throwing: CaptureError.noFramesCaptured)
          return
        }

        Log.info("ReplayWriter.finishWriting: start. status:", writer.status.rawValue)
        self.acceptsMediaData = false
        self.videoInput?.markAsFinished()
        self.audioInput?.markAsFinished()
        let writerBox = UncheckedSendable(writer)
        writer.finishWriting { [weak self] in
          guard let self else {
            continuation.resume(throwing: CaptureError.writerUnavailable)
            return
          }
          // dispatch back to our queue to safely access state
          self.onQueue {
            let writer = writerBox.value
            let error = writer.error
            if let error {
              let nsError = error as NSError
              Log.info("ReplayWriter.finishWriting: failed. domain:", nsError.domain, "code:", nsError.code, "userInfo:", nsError.userInfo)
            } else {
              Log.info("ReplayWriter.finishWriting: success.")
            }
            self.resetState()

            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume(returning: outputURL)
            }
          }
        }
      }
    }
  }

  // - Logging ---

  private func logWriterError(_ label: String, _ error: Error?) {
    if let error {
      let nsError = error as NSError
      AppLog.error(.writer, label, "domain:", nsError.domain, "code:", nsError.code, "userInfo:", nsError.userInfo)
    } else {
      AppLog.error(.writer, label, "no error info.")
    }
  }

  private func logAppendFailure(
    label: String,
    writer: AVAssetWriter,
    videoInput: AVAssetWriterInput,
    sampleBuffer: CMSampleBuffer
  ) {
    Log.info(label, "status:", writer.status.rawValue, "ready:", videoInput.isReadyForMoreMediaData)
    if let error = writer.error {
      let nsError = error as NSError
      Log.info("ReplayWriter.appendVideo writer.error domain:", nsError.domain, "code:", nsError.code, "userInfo:", nsError.userInfo)
    } else {
      Log.info("ReplayWriter.appendVideo writer.error: nil")
    }
    Log.info("ReplayWriter.appendVideo videoInput.error: unavailable (no public API)")
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if lastVideoPTS.isValid {
      Log.info("ReplayWriter.appendVideo PTS last:", lastVideoPTS.seconds, "now:", pts.seconds)
    } else {
      Log.info("ReplayWriter.appendVideo PTS now:", pts.seconds)
    }
    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
      let width = CVPixelBufferGetWidth(pixelBuffer)
      let height = CVPixelBufferGetHeight(pixelBuffer)
      let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
      Log.info("ReplayWriter.appendVideo buffer:", width, "x", height, "format:", format)
    }
  }

  private func logAudioAppendFailure(
    label: String,
    writer: AVAssetWriter,
    audioInput: AVAssetWriterInput,
    sampleBuffer: CMSampleBuffer
  ) {
    Log.info(label, "status:", writer.status.rawValue, "ready:", audioInput.isReadyForMoreMediaData)
    if let error = writer.error {
      let nsError = error as NSError
      Log.info("ReplayWriter.appendAudio writer.error domain:", nsError.domain, "code:", nsError.code, "userInfo:", nsError.userInfo)
    } else {
      Log.info("ReplayWriter.appendAudio writer.error: nil")
    }
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    Log.info("ReplayWriter.appendAudio PTS:", pts.seconds)
  }

  private func logAudioFormat(_ sampleBuffer: CMSampleBuffer) {
    guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
      Log.info("ReplayWriter.appendAudio format: unavailable")
      return
    }
    audioSampleRate = asbd.mSampleRate
    audioFormatDescription = format
    audioASBD = asbd
    Log.info("ReplayWriter.appendAudio ASBD: sr:", asbd.mSampleRate,
             "ch:", asbd.mChannelsPerFrame,
             "fmt:", asbd.mFormatID,
             "flags:", asbd.mFormatFlags,
             "bytesPerFrame:", asbd.mBytesPerFrame)
  }

  // - Queue Helpers ---

  private func onQueue(_ block: @escaping @Sendable () -> Void) {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      block()
    } else {
      queue.async(execute: block)
    }
  }

  private func syncOnQueue(_ block: () -> Void) {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      block()
    } else {
      queue.sync(execute: block)
    }
  }
}
