import Foundation

/// Removes this app's entry for a privacy permission with `tccutil`, so turning a
/// feature off in Rewind also clears the macOS permission instead of leaving it
/// granted (and carried across updates).
enum TCCReset {
	enum Service: String {
		case microphone = "Microphone"
	}

	/// Runs `tccutil` with the given arguments and returns its exit status.
	typealias Runner = @Sendable ([String]) throws -> Int32

	static func arguments(service: Service, bundleID: String) -> [String] {
		["reset", service.rawValue, bundleID]
	}

	/// - Returns: `true` if `tccutil` ran and succeeded. Never resets anything
	///   without a bundle identifier (a bare `tccutil reset <service>` would hit
	///   every app).
	@discardableResult
	static func resetMicrophone(
		bundleID: String? = Bundle.main.bundleIdentifier,
		run: Runner = systemRunner
	) -> Bool {
		guard let bundleID, !bundleID.isEmpty else { return false }
		do {
			let status = try run(arguments(service: .microphone, bundleID: bundleID))
			if status != 0 {
				AppLog.error(.app, "tccutil reset Microphone exited with status \(status)")
			}
			return status == 0
		} catch {
			AppLog.error(.app, "Could not reset the Microphone permission", error: error)
			return false
		}
	}

	static let systemRunner: Runner = { arguments in
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
		process.arguments = arguments
		try process.run()
		process.waitUntilExit()
		return process.terminationStatus
	}
}
