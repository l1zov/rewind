import AVFoundation
import CoreGraphics
import AppKit

struct PermissionState: Equatable {
  var screenRecording: Bool = false
  var microphone: Bool = false
}

enum PermissionError: Error {
  case screenRecordingDenied
  case microphoneDenied
}

enum PermissionManager {
  private static let screenCaptureSettingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
  )

  static func currentState() -> PermissionState {
    PermissionState(
      screenRecording: CGPreflightScreenCaptureAccess(),
      microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    )
  }

  static func ensureScreenAccess() async throws {
    if CGPreflightScreenCaptureAccess() {
      return
    }

    let granted = CGRequestScreenCaptureAccess()
    if !granted {
      throw PermissionError.screenRecordingDenied
    }
  }

  static func ensureScreenAndMicAccess() async throws {
    try await ensureMicrophoneAccess()
    try await ensureScreenAccess()
  }

  private static func ensureMicrophoneAccess() async throws {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    switch status {
    case .authorized:
      return
    case .notDetermined:
      let granted = await requestMicrophone()
      if !granted { throw PermissionError.microphoneDenied }
    default:
      throw PermissionError.microphoneDenied
    }
  }

  private static func requestMicrophone() async -> Bool {
    await withCheckedContinuation { continuation in
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        continuation.resume(returning: granted)
      }
    }
  }

  static func openSystemSettings() {
    guard let url = screenCaptureSettingsURL else { return }
    NSWorkspace.shared.open(url)
  }
}
