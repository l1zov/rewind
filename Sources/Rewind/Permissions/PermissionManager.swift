import AppKit
import AVFoundation
import CoreGraphics

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
	
	private static let microphoneSettingsURL = URL(
		string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
	)

	static func currentState() -> PermissionState {
		PermissionState(
			screenRecording: CGPreflightScreenCaptureAccess(),
			microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
		)
	}

	/// - Parameter prompt: show the system permission prompt when access is
	///   missing. Pass `false` for automatic (non-user-initiated) starts so a
	///   revoked permission doesn't re-open the prompt on every retry.
	static func ensureScreenAccess(prompt: Bool = true) async throws {
		if CGPreflightScreenCaptureAccess() {
			return
		}

		guard prompt, CGRequestScreenCaptureAccess() else {
			throw PermissionError.screenRecordingDenied
		}
	}
	
	static func ensureMicrophoneAccess() async throws {
		if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
			return
		}

		let granted = await AVCaptureDevice.requestAccess(for: .audio)
		if !granted {
			throw PermissionError.microphoneDenied
		}
	}

	static func openSystemSettings() {
		guard let url = screenCaptureSettingsURL else { return }
		NSWorkspace.shared.open(url)
	}

	/// Relaunches the app. macOS won't apply a newly granted Screen Recording
	/// permission to an already-running process, so once the user flips the
	/// toggle we restart to pick it up (a helper waits for this process to exit,
	/// then reopens the bundle).
	@MainActor
	static func relaunch() {
		let bundlePath = Bundle.main.bundlePath
		let pid = ProcessInfo.processInfo.processIdentifier
		let helper = Process()
		helper.executableURL = URL(fileURLWithPath: "/bin/sh")
		helper.arguments = [
			"-c",
			"while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"\(bundlePath)\"",
		]
		try? helper.run()
		NSApp.terminate(nil)
	}
	
	static func openMicrophoneSettings() {
		guard let url = microphoneSettingsURL else { return }
		NSWorkspace.shared.open(url)
	}
}
