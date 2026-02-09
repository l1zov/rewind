@preconcurrency import AVFoundation
import Foundation

actor CaptureManager {
  private enum Constants {
    static let rotationFrameDelayNanos: UInt64 = 50_000_000
    static let fileReadyAttempts = 10
    static let fileReadyDelayNanos: UInt64 = 50_000_000
    static let nanosPerSecond: Double = 1_000_000_000
  }

  private let screenCapture: ScreenCaptureService
  private let captureQueue: DispatchQueue
  private let writerQueue: DispatchQueue
  /// active writer receiving samples (accessed via nonisolated helper for callbacks)
  private var activeWriter: ReplayWriter
  /// standby writer pre-configured for instant switchover
  private var standbyWriter: ReplayWriter?
  private let replayBuffer = ReplayBuffer()
  private var isRunning = false
  private var isSaving = false
  private var isStopping = false
  private var rotationTask: Task<Void, Never>?
  private let segmentDuration: TimeInterval = 10
  private let maxBufferDuration: TimeInterval = 120
  private var currentResolution: CaptureResolution?
  private var currentQuality: QualityPreset = .default
  private var currentFrameRate: Int = CaptureFrameRate.default.framesPerSecond
  private var onCaptureInterrupted: (@MainActor (Error) -> Void)?

  /// thread-safe reference to current writer for use in callbacks
  /// sses lock-based synchronization so it can be safely accessed from nonisolated contexts
  private let currentWriterLock = NSLock()
  private nonisolated(unsafe) var _currentWriter: ReplayWriter?
  private nonisolated var currentWriter: ReplayWriter? {
    get {
      currentWriterLock.withLock { _currentWriter }
    }
    set {
      currentWriterLock.withLock { _currentWriter = newValue }
    }
  }

  init() {
    // sse userInteractive QoS for real-time capture processing
    let queue = DispatchQueue(label: "rewind.capture.samples", qos: .userInteractive)
    captureQueue = queue
    let audioQueue = DispatchQueue(label: "rewind.capture.audio", qos: .userInteractive)
    // dedicated writer queue keeps encoding work off the capture callback queue.
    writerQueue = DispatchQueue(label: "rewind.capture.writer", qos: .userInitiated)
    screenCapture = ScreenCaptureService(sampleQueue: queue, audioQueue: audioQueue)
    activeWriter = ReplayWriter(queue: writerQueue)
    screenCapture.onCaptureStopped = { [weak self] error in
      guard let self, let error else { return }
      Task {
        await self.handleCaptureFailure(error, label: "Capture stream stopped")
      }
    }
  }

  func setOnCaptureInterruptedHandler(_ handler: (@MainActor (Error) -> Void)?) {
    onCaptureInterrupted = handler
  }

  func start(
    resolution: CaptureResolution? = nil,
    quality: QualityPreset = .default,
    frameRate: Int = CaptureFrameRate.default.framesPerSecond
  ) async throws {
    guard !isRunning else { return }
    currentResolution = resolution
    currentQuality = quality
    currentFrameRate = frameRate
    do {
      try await screenCapture.startCapture(
        resolution: resolution,
        quality: quality,
        frameRate: frameRate
      )
      try configureActiveWriter()
      currentWriter = activeWriter
      screenCapture.onVideoSampleBuffer = { [weak self] sampleBuffer in
        self?.currentWriter?.appendVideo(sampleBuffer)
      }
      screenCapture.onAudioSampleBuffer = { [weak self] sampleBuffer in
        self?.currentWriter?.appendAudio(sampleBuffer)
      }
      isRunning = true
      prepareStandbyWriter()
      startRotationLoop()
    } catch {
      await resetCaptureState()
      throw error
    }
  }

  func stop() async {
    guard isRunning else { return }
    await stopCapturePipeline()
  }

  func saveReplay(seconds: TimeInterval, container: CaptureContainer = .default) async throws -> URL {
    guard isRunning else { throw CaptureError.noFramesCaptured }
    guard !isSaving else { throw CaptureError.saveInProgress }
    isSaving = true
    defer { isSaving = false }

    print("Save replay start. seconds:", seconds)
    var sourceURL: URL?
    var sourceURLAddedToBuffer = false
    do {
      sourceURL = try await rotateWriterSeamlessly()
    } catch {
      Self.logError("Replay rotation failed", error)
      throw error
    }

    var segmentsToUnlock: [ReplaySegment] = []
    do {
      guard let sourceURL else { throw CaptureError.writerUnavailable }
      print("Replay source ready:", sourceURL.lastPathComponent)
      try await waitForFileReady(at: sourceURL)
      let duration = try await loadDuration(of: sourceURL)
      let removed = await replayBuffer.appendSegment(url: sourceURL, duration: duration, maxDuration: maxBufferDuration)
      sourceURLAddedToBuffer = true
      removeFiles(removed)
      let segments = await replayBuffer.latestSegments(totalDuration: seconds)
      segmentsToUnlock = segments
      let exportURL = try await exportFromSegments(segments, seconds: seconds, container: container)
      await replayBuffer.unlockSegments(segmentsToUnlock)
      print("Save replay success:", exportURL.lastPathComponent)
      return exportURL
    } catch {
      // Always unlock segments on failure
      if !segmentsToUnlock.isEmpty {
        await replayBuffer.unlockSegments(segmentsToUnlock)
      }
      if let sourceURL, !sourceURLAddedToBuffer {
        removeFiles([sourceURL])
      }
      Self.logError("Export failed", error)
      throw error
    }
  }

  /// configures the active writer with a new output file
  private func configureActiveWriter() throws {
    guard let size = screenCapture.displaySize else {
      throw CaptureError.noDisplay
    }
    let outputURL = makeSegmentURL()
    try activeWriter.configure(
      outputURL: outputURL,
      videoSize: size,
      includeAudio: true,
      audioSettings: captureAudioSettings,
      quality: currentQuality,
      frameRate: currentFrameRate
    )
  }

  /// pre-configures the standby writer for instant switchover
  private func prepareStandbyWriter() {
    guard let size = screenCapture.displaySize else { return }
    let writer = ReplayWriter(queue: writerQueue)
    let outputURL = makeSegmentURL()
    do {
      try writer.configure(
        outputURL: outputURL,
        videoSize: size,
        includeAudio: true,
        audioSettings: captureAudioSettings,
        quality: currentQuality,
        frameRate: currentFrameRate
      )
      standbyWriter = writer
    } catch {
      Self.logError("Failed to prepare standby writer", error)
      standbyWriter = nil
    }
  }

  /// seamlessly rotates to the standby writer and returns the finished segment URL.
  private func rotateWriterSeamlessly() async throws -> URL {
    // ensure standby is ready, or prepare it now
    if standbyWriter == nil {
      prepareStandbyWriter()
    }
    guard let newWriter = standbyWriter else {
      throw CaptureError.writerUnavailable
    }

    // atomically switch the writer reference (callbacks will pick up new writer)
    let oldWriter = activeWriter
    activeWriter = newWriter
    standbyWriter = nil
    
    // update currentWriter atomically; this is what callbacks use
    currentWriter = newWriter
    
    // small delay to ensure the new writer receives at least one frame
    // before we finish the old writer (prevents black frame at segment boundary)
    try? await Task.sleep(nanoseconds: Constants.rotationFrameDelayNanos)  // 50ms = ~3 frames at 60fps

    // finish the old writer and prepare next standby in background
    let sourceURL = try await oldWriter.finishWriting()
    prepareStandbyWriter()
    return sourceURL
  }

  private func makeSegmentURL() -> URL {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("Rewind", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("Rewind_live_\(UUID().uuidString).mov")
  }

  private var captureAudioSettings: [String: Any] {
    [
      // use PCM for segments
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 48_000,
      AVNumberOfChannelsKey: 2,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      "AVLinearPCMIsNonInterleaved": false
    ]
  }

  private func exportFromSegments(
    _ segments: [ReplaySegment],
    seconds: TimeInterval,
    container: CaptureContainer
  ) async throws -> URL {
    guard !segments.isEmpty else { throw CaptureError.noFramesCaptured }

    let composition = AVMutableComposition()
    let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

    var cursor = CMTime.zero
    var appliedTransform = false
    for segment in segments {
      let asset = AVURLAsset(url: segment.url)
      _ = try await asset.load(.tracks)
      let assetDuration = try await asset.load(.duration)
      var videoDuration = assetDuration
      var audioDuration = assetDuration

      if let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
         let videoTrack {
        videoDuration = try await sourceVideo.load(.timeRange).duration
        if !appliedTransform {
          let transform = try await sourceVideo.load(.preferredTransform)
          videoTrack.preferredTransform = transform
          appliedTransform = true
        }
      }
      if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
        audioDuration = try await sourceAudio.load(.timeRange).duration
      }
      let minDuration = CMTimeMinimum(videoDuration, audioDuration)
      let segmentDuration = minDuration.isValid && minDuration > .zero ? minDuration : assetDuration
      let timeRange = CMTimeRange(start: .zero, duration: segmentDuration)
      if let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
         let videoTrack {
        try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: cursor)
      }
      if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
         let audioTrack {
        try audioTrack.insertTimeRange(timeRange, of: sourceAudio, at: cursor)
      }
      if assetDuration.isValid, segmentDuration.isValid {
        let delta = CMTimeSubtract(assetDuration, segmentDuration)
        let mismatchThreshold = CMTime(seconds: 0.02, preferredTimescale: 1_000)
        if delta > mismatchThreshold {
          print("Export: segment duration mismatch. asset:", assetDuration.seconds, "video:", videoDuration.seconds, "audio:", audioDuration.seconds)
        }
      }
      cursor = cursor + segmentDuration
    }

    let totalSeconds = cursor.seconds
    guard totalSeconds.isFinite, totalSeconds > 0 else {
      throw CaptureError.noFramesCaptured
    }
    let clipSeconds = max(0, min(seconds, totalSeconds))
    guard clipSeconds > 0 else {
      throw CaptureError.noFramesCaptured
    }
    let timescale = cursor.timescale == 0 ? CMTimeScale(600) : cursor.timescale
    let startTime = CMTime(seconds: max(totalSeconds - clipSeconds, 0), preferredTimescale: timescale)
    let timeRange = CMTimeRange(start: startTime, duration: CMTime(seconds: clipSeconds, preferredTimescale: timescale))

    let folder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("Rewind", isDirectory: true)
      ?? FileManager.default.temporaryDirectory.appendingPathComponent("Rewind", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let exportURL = folder.appendingPathComponent("Rewind_\(UUID().uuidString).\(container.fileExtension)")
    try? FileManager.default.removeItem(at: exportURL)

    do {
      return try await exportWithPassthrough(
        asset: composition,
        timeRange: timeRange,
        outputURL: exportURL,
        container: container
      )
    } catch {
      removeFiles([exportURL])
      throw error
    }
  }

  private func exportWithPassthrough(
    asset: AVAsset,
    timeRange: CMTimeRange,
    outputURL: URL,
    container: CaptureContainer
  ) async throws -> URL {
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
      throw CaptureError.exportFailed
    }

    guard exportSession.supportedFileTypes.contains(container.avFileType) else {
      throw CaptureError.exportFailed
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = container.avFileType
    exportSession.timeRange = timeRange
    exportSession.shouldOptimizeForNetworkUse = false

    let session = UncheckedSendable(exportSession)
    return try await withCheckedThrowingContinuation { continuation in
      session.value.exportAsynchronously {
        switch session.value.status {
        case .completed:
          continuation.resume(returning: outputURL)
        case .failed, .cancelled:
          try? FileManager.default.removeItem(at: outputURL)
          continuation.resume(throwing: session.value.error ?? CaptureError.exportFailed)
        default:
          try? FileManager.default.removeItem(at: outputURL)
          continuation.resume(throwing: CaptureError.exportFailed)
        }
      }
    }
  }

  private func waitForFileReady(at url: URL) async throws {
    let fm = FileManager.default
    for _ in 0..<Constants.fileReadyAttempts {
      if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber, size.intValue > 0 {
        return
      }
      try await Task.sleep(nanoseconds: Constants.fileReadyDelayNanos)
    }
    throw CaptureError.noFramesCaptured
  }

  private func loadDuration(of url: URL) async throws -> TimeInterval {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    let seconds = CMTimeGetSeconds(duration)
    guard seconds.isFinite, seconds > 0 else {
      throw CaptureError.invalidDuration
    }
    return seconds
  }


  private static func logError(_ label: String, _ error: Error) {
    let nsError = error as NSError
    print(label, "domain:", nsError.domain, "code:", nsError.code, "userInfo:", nsError.userInfo)
  }

  private func startRotationLoop() {
    rotationTask?.cancel()
    rotationTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(segmentDuration * Constants.nanosPerSecond))
        if Task.isCancelled { break }
        await self.rotateSegment()
      }
    }
  }

  private func rotateSegment() async {
    guard isRunning else { return }

    let sourceURL: URL
    do {
      sourceURL = try await rotateWriterSeamlessly()
    } catch {
      await handleCaptureFailure(error, label: "Rotation failed")
      return
    }

    do {
      try await waitForFileReady(at: sourceURL)
      let duration = try await loadDuration(of: sourceURL)
      let removed = await replayBuffer.appendSegment(url: sourceURL, duration: duration, maxDuration: maxBufferDuration)
      removeFiles(removed)
    } catch {
      removeFiles([sourceURL])
      await handleCaptureFailure(error, label: "Rotation post-processing failed")
    }
  }

  private func handleCaptureFailure(_ error: Error, label: String) async {
    guard isRunning else { return }
    Self.logError(label, error)
    await stopCapturePipeline()
    if let onCaptureInterrupted {
      await onCaptureInterrupted(error)
    }
  }

  private func stopCapturePipeline() async {
    if isStopping { return }
    isStopping = true
    defer { isStopping = false }
    await resetCaptureState()
  }

  private func resetCaptureState() async {
    rotationTask?.cancel()
    rotationTask = nil
    screenCapture.onVideoSampleBuffer = nil
    screenCapture.onAudioSampleBuffer = nil
    currentWriter = nil
    await screenCapture.stopCapture()
    if let url = try? await activeWriter.finishWriting() {
      removeFiles([url])
    }
    standbyWriter = nil
    let urls = await replayBuffer.clear()
    removeFiles(urls)
    cleanupTemporaryLiveSegments()
    isSaving = false
    isRunning = false
  }

  private func removeFiles(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    let fm = FileManager.default
    for url in urls {
      try? fm.removeItem(at: url)
    }
  }

  private func cleanupTemporaryLiveSegments() {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("Rewind", isDirectory: true)
    let fm = FileManager.default
    guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
      return
    }
    for url in urls where url.lastPathComponent.hasPrefix("Rewind_live_") {
      try? fm.removeItem(at: url)
    }
  }
}
