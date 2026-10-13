import CoreGraphics

/// A display's id and its frame in the global display coordinate space (the
/// origin is the upper-left corner of the main display).
struct DisplayGeometry: Equatable {
	let id: CGDirectDisplayID
	let frame: CGRect
	/// The display's current mode in pixels, so a resolution change on the same
	/// display (or another monitor on the same port) is noticed.
	var pixelSize: CGSize = .zero
}

/// Chooses which display to record for the windows of the watched apps, so the
/// recording follows the app and the user's focus instead of always using the
/// main display.
enum DisplaySelection {
	/// A window smaller than this fraction of the largest window is ignored, so a
	/// small overlay or launcher popup in front doesn't decide the display.
	static let minimumRelativeArea: CGFloat = 0.25

	/// - Parameters:
	///   - windows: frames of the watched apps' windows in the global display
	///     space, front to back (the order `CGWindowListCopyWindowInfo` uses), so
	///     the first substantial window is the one the user is focused on.
	///   - displays: the active displays. When a window is split exactly between
	///     two displays, the earlier one wins, so list the main display first.
	/// - Returns: the display holding most of the frontmost substantial window,
	///   or nil when no window is on any display.
	static func displayID(forWindows windows: [CGRect], displays: [DisplayGeometry]) -> CGDirectDisplayID? {
		let sized = windows.filter { area(of: $0) > 0 }
		guard let largest = sized.map(area(of:)).max() else { return nil }

		let threshold = largest * minimumRelativeArea
		for window in sized where area(of: window) >= threshold {
			if let id = display(mostCovering: window, in: displays) { return id }
		}
		return nil
	}

	private static func area(of rect: CGRect) -> CGFloat {
		rect.isNull ? 0 : rect.width * rect.height
	}

	private static func display(mostCovering window: CGRect, in displays: [DisplayGeometry]) -> CGDirectDisplayID? {
		var best: (id: CGDirectDisplayID, area: CGFloat)?
		for display in displays {
			let covered = area(of: window.intersection(display.frame))
			if covered > (best?.area ?? 0) { best = (display.id, covered) }
		}
		return best?.id
	}
}
