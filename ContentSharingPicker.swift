import ScreenCaptureKit

/// Presents the macOS system content picker (`SCContentSharingPicker`, macOS 14+)
/// so the user can choose a display, window, or application to capture, then
/// resolves with the selected content filter.
///
/// The picker is presented without an existing stream, so the returned filter is
/// used to build a fresh capture stream — i.e. "pick what to record before
/// recording starts". The filter is handed back already boxed in
/// `UncheckedSendable` so it can cross into the capture actor.
@available(macOS 14.0, *)
final class ContentSharingPicker: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
	/// Thrown when the user dismisses the picker without choosing anything.
	struct Cancelled: Error {}
	/// Thrown when the picker itself fails to start.
	struct Failed: Error { let message: String }

	private let lock = NSLock()
	private var continuation: CheckedContinuation<UncheckedSendable<SCContentFilter>, Error>?

	/// Present the picker and await the user's selection. Must run on the main
	/// actor because it drives AppKit UI.
	@MainActor
	func pick(
		modes: SCContentSharingPickerMode = [.singleDisplay, .singleWindow, .singleApplication]
	) async throws -> UncheckedSendable<SCContentFilter> {
		let picker = SCContentSharingPicker.shared
		var configuration = SCContentSharingPickerConfiguration()
		configuration.allowedPickerModes = modes
		picker.configuration = configuration
		picker.add(self)
		picker.isActive = true
		defer {
			picker.remove(self)
			picker.isActive = false
		}
		return try await withCheckedThrowingContinuation { continuation in
			lock.withLock { self.continuation = continuation }
			picker.present()
		}
	}

	/// Dismisses an in-flight picker and releases its continuation. This lets the
	/// Stop hotkey and sleep/termination paths cancel a pending recording start.
	@MainActor
	func cancel() {
		let picker = SCContentSharingPicker.shared
		picker.remove(self)
		picker.isActive = false
		takeContinuation()?.resume(throwing: Cancelled())
	}

	/// Atomically claim the pending continuation so it is resumed exactly once;
	/// callbacks that arrive afterwards become no-ops.
	private func takeContinuation() -> CheckedContinuation<UncheckedSendable<SCContentFilter>, Error>? {
		lock.withLock {
			let continuation = self.continuation
			self.continuation = nil
			return continuation
		}
	}

	// MARK: SCContentSharingPickerObserver

	func contentSharingPicker(
		_: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for _: SCStream?
	) {
		takeContinuation()?.resume(returning: UncheckedSendable(filter))
	}

	func contentSharingPicker(_: SCContentSharingPicker, didCancelFor _: SCStream?) {
		takeContinuation()?.resume(throwing: Cancelled())
	}

	func contentSharingPickerStartDidFailWithError(_ error: Error) {
		takeContinuation()?.resume(throwing: Failed(message: String(describing: error)))
	}
}
