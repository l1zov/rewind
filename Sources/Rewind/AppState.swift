@preconcurrency import AVFoundation
import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
  private enum StorageWarning {
    static let thresholdBytes: Int64 = 5 * 1024 * 1024 * 1024
  }

  static let shared = AppState()

  @Published private(set) var isCapturing = false
  @Published var replayDuration: TimeInterval = 30 {
    didSet {
      guard !isRestoringSettings else { return }
      let clamped = min(
        max(replayDuration, AppSettings.replayDurationRange.lowerBound),
        AppSettings.replayDurationRange.upperBound
      )
      if clamped != replayDuration {
        replayDuration = clamped
        return
      }
      persistSettings()
    }
  }
  @Published private(set) var lastClip: Clip?
  @Published private(set) var permissionState = PermissionState()
  @Published private(set) var availableResolutions: [CaptureResolution] = []
  @Published private(set) var isLoadingResolutions = false
  @Published private(set) var resolutionLoadingMessage: String?
  @Published var selectedResolution: CaptureResolution? {
    didSet {
      guard !isRestoringSettings else { return }
      guard selectedResolution != oldValue else { return }
      preferredResolutionID = selectedResolution?.id
      persistSettings()
    }
  }
  @Published var selectedQuality: QualityPreset = .default {
    didSet {
      guard !isRestoringSettings else { return }
      guard selectedQuality != oldValue else { return }
      persistSettings()
    }
  }
  @Published var selectedFrameRate: CaptureFrameRate = .default {
    didSet {
      guard !isRestoringSettings else { return }
      guard selectedFrameRate != oldValue else { return }
      persistSettings()
    }
  }
  @Published var selectedContainer: CaptureContainer = .default {
    didSet {
      guard !isRestoringSettings else { return }
      guard selectedContainer != oldValue else { return }
      persistSettings()
    }
  }
  @Published var selectedAudioCodec: CaptureAudioCodec = .default {
    didSet {
      guard !isRestoringSettings else { return }
      guard selectedAudioCodec != oldValue else { return }
      persistSettings()
    }
  }
  @Published var hotkey: Hotkey = .default {
    didSet {
      guard !isRestoringSettings else { return }
      guard hotkey != oldValue else { return }
      persistSettings()
      updateGlobalHotkeys()
    }
  }
  @Published var startRecordingHotkey: Hotkey = .startRecordingDefault {
    didSet {
      guard !isRestoringSettings else { return }
      guard startRecordingHotkey != oldValue else { return }
      persistSettings()
      updateGlobalHotkeys()
    }
  }
  @Published var saveFeedbackEnabled = AppSettings.default.saveFeedbackEnabled {
    didSet {
      guard !isRestoringSettings else { return }
      guard saveFeedbackEnabled != oldValue else { return }
      persistSettings()
    }
  }
  @Published var saveFeedbackVolume = AppSettings.default.saveFeedbackVolume {
    didSet {
      guard !isRestoringSettings else { return }
      guard saveFeedbackVolume != oldValue else { return }
      let clamped = min(
        max(saveFeedbackVolume, AppSettings.saveFeedbackVolumeRange.lowerBound),
        AppSettings.saveFeedbackVolumeRange.upperBound
      )
      if clamped != saveFeedbackVolume {
        saveFeedbackVolume = clamped
        return
      }
      persistSettings()
    }
  }
  @Published var saveFeedbackSound: SaveFeedbackSound = .default {
    didSet {
      guard !isRestoringSettings else { return }
      guard saveFeedbackSound != oldValue else { return }
      replaySavedSound = nil
      replaySavedBoostSound = nil
      persistSettings()
    }
  }
  @Published var discordRPCEnabled = AppSettings.default.discordRPCEnabled {
    didSet {
      guard !isRestoringSettings else { return }
      guard discordRPCEnabled != oldValue else { return }
      persistSettings()
      Task {
        await discordRPCClient.setEnabled(discordRPCEnabled)
        if discordRPCEnabled {
          self.publishDiscordPresenceWithRetry(for: self.discordActivityState)
        } else {
          discordPresenceRetryTask?.cancel()
          discordPresenceRetryTask = nil
        }
      }
    }
  }
  @Published private(set) var lowStorageWarningMessage: String?

  private let captureManager = CaptureManager()
  private let clipLibrary = ClipLibrary()
  private let discordRPCClient = DiscordRPCClient()
  private var replaySavedSound: NSSound?
  private var replaySavedBoostSound: NSSound?
  private var discordActivityState: DiscordActivityState = .idle
  private var discordPresenceRetryTask: Task<Void, Never>?
  private var preferredResolutionID: String?
  private var isRestoringSettings = false

  private init() {
    permissionState = PermissionManager.currentState()
    let settings = AppSettingsStorage.load()
    isRestoringSettings = true
    replayDuration = settings.replayDuration
    selectedQuality = settings.qualityPreset
    selectedFrameRate = settings.frameRateOption
    selectedContainer = settings.container
    selectedAudioCodec = settings.audioCodec
    preferredResolutionID = settings.resolutionID
    hotkey = settings.hotkey
    startRecordingHotkey = settings.startRecordingHotkey
    saveFeedbackEnabled = settings.saveFeedbackEnabled
    saveFeedbackVolume = settings.saveFeedbackVolume
    saveFeedbackSound = settings.saveFeedbackSound
    discordRPCEnabled = settings.discordRPCEnabled
    isRestoringSettings = false
    Task { [weak self] in
        await self?.captureManager.setOnCaptureInterruptedHandler { error in
          self?.isCapturing = false
          AppLog.error(.app, "Capture interrupted:", error)
        }
      }
    Task { await loadAvailableResolutions() }
    refreshStorageWarning()
    Task {
      await discordRPCClient.setEnabled(discordRPCEnabled)
      self.publishDiscordPresenceWithRetry(for: self.discordActivityState)
    }
  }

  func startCapture() {
    Task { await startCaptureAsync() }
  }

  func stopCapture() {
    Task { await stopCaptureAsync() }
  }

  func saveReplay() {
    Task { await saveReplayAsync() }
  }

  func toggleCapture() {
    if isCapturing {
      stopCapture()
    } else {
      startCapture()
    }
  }

  func refreshPermissions() {
    Task { await refreshPermissionsAsync() }
  }

  func refreshResolutions() {
    Task { await loadAvailableResolutions() }
  }

  private func loadAvailableResolutions() async {
    guard !isLoadingResolutions else { return }

    isLoadingResolutions = true
    resolutionLoadingMessage = nil
    defer { isLoadingResolutions = false }

    let resolutions = await CaptureResolutionProvider.availableResolutions()
    if !resolutions.isEmpty {
      availableResolutions = resolutions

      if let selectedResolutionID = selectedResolution?.id,
         let currentSelection = resolutions.first(where: { $0.id == selectedResolutionID }) {
        if selectedResolution != currentSelection {
          selectedResolution = currentSelection
        }
        preferredResolutionID = currentSelection.id
        return
      }

      if let preferredResolutionID,
         let preferredResolution = resolutions.first(where: { $0.id == preferredResolutionID }) {
        selectedResolution = preferredResolution
        return
      }

      if let native = resolutions.first(where: { $0.isNative }) {
        selectedResolution = native
      } else {
        selectedResolution = resolutions.first
      }
      return
    }

    permissionState = PermissionManager.currentState()
    if !permissionState.screenRecording {
      availableResolutions = []
      resolutionLoadingMessage = "Screen recording permission required"
      return
    }

    availableResolutions = []
    resolutionLoadingMessage = "Loaded not resolutions"
    AppLog.error(.app, "Resolutions didnt load after multiple tries")
  }

  private func startCaptureAsync() async {
    do {
      try await PermissionManager.ensureScreenAccess()
      permissionState = PermissionManager.currentState()
      try await captureManager.start(
        resolution: selectedResolution,
        quality: selectedQuality,
        frameRate: selectedFrameRate.framesPerSecond,
        audioCodec: selectedAudioCodec
      )
      isCapturing = true
      updateDiscordActivity(.recording)
    } catch {
      isCapturing = false
      updateDiscordActivity(.idle)
    }
  }

  private func stopCaptureAsync() async {
    await captureManager.stop()
    isCapturing = false
    updateDiscordActivity(.idle)
  }

  private func saveReplayAsync() async {
    do {
      let url = try await captureManager.saveReplay(seconds: replayDuration, container: selectedContainer)
      let clipDuration = try await resolvedClipDuration(for: url)
      let clip = try await clipLibrary.addClip(url: url, duration: clipDuration)
      lastClip = clip
      playReplaySavedFeedback()
    } catch {
      print("Save replay failed:", error)
    }
  }

  private func updateDiscordActivity(_ state: DiscordActivityState) {
    guard discordActivityState != state else { return }
    discordActivityState = state
    publishDiscordPresenceWithRetry(for: state)
  }

  private func publishDiscordPresenceWithRetry(for state: DiscordActivityState) {
    guard discordRPCEnabled else { return }

    discordPresenceRetryTask?.cancel()
    discordPresenceRetryTask = Task { @MainActor [weak self] in
      guard let self else { return }

      while !Task.isCancelled {
        guard self.discordRPCEnabled, self.discordActivityState == state else { return }
        let published = await self.discordRPCClient.publish(state: state)
        if published { return }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
      }
    }
  }

  private func playReplaySavedFeedback() {
    guard saveFeedbackEnabled else { return }
    guard let replaySavedSound = replaySavedSoundForCurrentSelection() else { return }

    let normalizedVolume = saveFeedbackVolume / 100
    let primaryVolume = Float(min(1, normalizedVolume * 1.25))
    let boostMix = max(0, normalizedVolume - 0.55) / 0.45
    let boostVolume = Float(min(1, boostMix * 0.9))

    replaySavedSound.stop()
    replaySavedSound.volume = primaryVolume
    replaySavedSound.play()

    if boostVolume > 0,
       let replaySavedBoostSound = replaySavedBoostSoundForCurrentSelection() {
      replaySavedBoostSound.stop()
      replaySavedBoostSound.volume = boostVolume
      replaySavedBoostSound.play()
    }
  }

  private func replaySavedSoundForCurrentSelection() -> NSSound? {
    if replaySavedSound == nil {
      replaySavedSound = NSSound(named: NSSound.Name(saveFeedbackSound.systemSoundName))
    }
    return replaySavedSound
  }

  private func replaySavedBoostSoundForCurrentSelection() -> NSSound? {
    if replaySavedBoostSound == nil {
      replaySavedBoostSound = NSSound(named: NSSound.Name(saveFeedbackSound.systemSoundName))
    }
    return replaySavedBoostSound
  }

  private func resolvedClipDuration(for url: URL) async throws -> TimeInterval {
    let asset = AVURLAsset(url: url)
    do {
      let duration = try await asset.load(.duration)
      let seconds = CMTimeGetSeconds(duration)
      if seconds.isFinite, seconds > 0 {
        return seconds
      }
    } catch {
      AppLog.info(.app, "Couldnt read export clip duration", error)
      throw error
    }
    throw CaptureError.invalidDuration
  }

  private func refreshPermissionsAsync() async {
    permissionState = PermissionManager.currentState()
  }

  private func updateGlobalHotkeys() {
    GlobalHotkeyManager.shared.updateHotkeys(
      saveReplay: hotkey,
      recordToggle: startRecordingHotkey
    )
  }

  private func persistSettings() {
    AppSettingsStorage.save(
      AppSettings(
        replayDuration: replayDuration,
        resolutionID: preferredResolutionID,
        qualityID: selectedQuality.id,
        frameRate: selectedFrameRate.framesPerSecond,
        containerID: selectedContainer.id,
        audioCodecID: selectedAudioCodec.id,
        hotkey: hotkey,
        startRecordingHotkey: startRecordingHotkey,
        saveFeedbackEnabled: saveFeedbackEnabled,
        saveFeedbackVolume: saveFeedbackVolume,
        saveFeedbackSoundID: saveFeedbackSound.id,
        discordRPCEnabled: discordRPCEnabled
      )
    )
  }

  private func refreshStorageWarning() {
    guard let freeBytes = availableStorageBytes() else {
      lowStorageWarningMessage = nil
      return
    }

    if freeBytes < StorageWarning.thresholdBytes {
      lowStorageWarningMessage = "Low disk space: \(formattedStorage(freeBytes)) left."
    } else {
      lowStorageWarningMessage = nil
    }
  }

  private func availableStorageBytes() -> Int64? {
    let fileManager = FileManager.default
    let targetURL = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser

    if let resourceValues = try? targetURL.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey,
      .volumeAvailableCapacityKey
    ]) {
      if let availableForImportantUsage = resourceValues.volumeAvailableCapacityForImportantUsage {
        return availableForImportantUsage
      }
      if let availableCapacity = resourceValues.volumeAvailableCapacity {
        return Int64(availableCapacity)
      }
    }

    if let attributes = try? fileManager.attributesOfFileSystem(forPath: targetURL.path),
       let freeSize = attributes[.systemFreeSize] as? NSNumber {
      return freeSize.int64Value
    }

    return nil
  }

  private func formattedStorage(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
