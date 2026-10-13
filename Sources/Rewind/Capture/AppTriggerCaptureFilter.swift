import ScreenCaptureKit

/// Builds the capture filter for "record while an app is open": the display the
/// watched apps' windows are on, limited to those apps' windows.
enum AppTriggerCaptureFilter {
	/// - Returns: nil when the target has no visible window to capture yet.
	static func make(target: WatchedTarget) async throws -> UncheckedSendable<SCContentFilter>? {
		guard !target.processIDs.isEmpty, let displayID = target.displayID else { return nil }

		let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
		let apps = content.applications.filter { target.processIDs.contains($0.processID) }
		guard !apps.isEmpty,
		      let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
		else { return nil }

		return UncheckedSendable(SCContentFilter(display: display, including: apps, exceptingWindows: []))
	}
}
