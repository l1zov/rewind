import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// What the capture stream should keep on screen while it runs. A display-bound
/// filter only ever records one display, so for these targets the stream's filter
/// is swapped to whichever display currently shows the target's frontmost window.
enum DisplayFollowTarget: Equatable, Sendable {
	/// Record the whole display that holds the frontmost app's window.
	case frontmostApplication
	/// Record only this app's windows, on the display that holds its frontmost window.
	/// The bundle ID keeps following the app if it relaunches with a new PID.
	case application(bundleID: String?, pid: pid_t)

	/// Follow target for a filter returned by the content picker, or nil when the
	/// filter should stay fixed (a display or window choice). Before macOS 15.2 the
	/// picked app can't be read back from the filter, so app picks stay fixed too.
	init?(pickerFilter filter: SCContentFilter) {
		guard #available(macOS 15.2, *) else { return nil }
		guard filter.style == .application, filter.includedApplications.count == 1 else {
			return nil
		}
		let app = filter.includedApplications[0]
		self = .application(
			bundleID: app.bundleIdentifier.isEmpty ? nil : app.bundleIdentifier,
			pid: app.processID
		)
	}
}

/// Where the followed content currently is: the app process to record and the
/// display showing its frontmost window.
struct DisplayFollowLocation: Equatable, Sendable {
	let pid: pid_t
	let displayID: CGDirectDisplayID
}

/// Confirms a new location only after it is seen on consecutive polls, so a quick
/// app switch or a window dragged past a screen edge doesn't bounce the recording.
struct DisplaySwitchDebouncer {
	private(set) var current: DisplayFollowLocation
	private var pending: DisplayFollowLocation?
	private var pendingCount = 0
	private let requiredSamples: Int

	init(current: DisplayFollowLocation, requiredSamples: Int = 2) {
		self.current = current
		self.requiredSamples = max(1, requiredSamples)
	}

	/// Feeds one poll result; returns the location to switch to once confirmed.
	mutating func observe(_ candidate: DisplayFollowLocation?) -> DisplayFollowLocation? {
		guard let candidate, candidate != current else {
			pending = nil
			pendingCount = 0
			return nil
		}
		if candidate == pending {
			pendingCount += 1
		} else {
			pending = candidate
			pendingCount = 1
		}
		guard pendingCount >= requiredSamples else { return nil }
		pending = nil
		pendingCount = 0
		return candidate
	}

	/// Records that the stream now shows `location`.
	mutating func didSwitch(to location: DisplayFollowLocation) {
		current = location
	}
}

enum DisplayFollower {
	static let pollIntervalNanos: UInt64 = 250_000_000
	/// Windows smaller than this (tooltips, popovers, status items) never decide the display.
	private static let minimumWindowSide: CGFloat = 64

	/// Builds the filter that records `target` (running as `pid`) on `display`, or
	/// nil when that process is no longer running.
	static func makeFilter(
		for target: DisplayFollowTarget, pid: pid_t, on display: SCDisplay,
		content: SCShareableContent
	) -> SCContentFilter? {
		switch target {
		case .frontmostApplication:
			return SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
		case .application:
			guard let app = content.applications.first(where: { $0.processID == pid }) else {
				return nil
			}
			return SCContentFilter(display: display, including: [app], exceptingWindows: [])
		}
	}

	/// The display a picker filter is bound to, when the OS can report it.
	static func pickedDisplayID(of filter: SCContentFilter) -> CGDirectDisplayID? {
		guard #available(macOS 15.2, *) else { return nil }
		return filter.includedDisplays.first?.displayID
	}

	/// The process to record for `target` right now: the frontmost app (other than
	/// Rewind), or the followed app's current process.
	static func currentPID(for target: DisplayFollowTarget) async -> pid_t? {
		await MainActor.run {
			switch target {
			case .frontmostApplication:
				guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
				      pid != getpid()
				else {
					return nil
				}
				return pid
			case let .application(bundleID, pid):
				guard let bundleID else { return pid }
				let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
					.filter { !$0.isTerminated }
				// Prefer the process we were already following if it is still alive.
				if running.contains(where: { $0.processIdentifier == pid }) { return pid }
				return running.first?.processIdentifier
			}
		}
	}

	/// Where the target's frontmost window is, or nil when that can't be determined
	/// right now (no windows on screen, Rewind itself is frontmost, ...).
	static func currentLocation(for target: DisplayFollowTarget) async -> DisplayFollowLocation? {
		guard let pid = await currentPID(for: target),
		      let bounds = frontmostWindowBounds(ownedBy: pid),
		      let displayID = bestDisplay(for: bounds, among: activeDisplays())
		else {
			return nil
		}
		return DisplayFollowLocation(pid: pid, displayID: displayID)
	}

	/// The display that contains the largest part of `rect`. Both use global
	/// display coordinates (origin at the top-left of the main display).
	static func bestDisplay(
		for rect: CGRect, among displays: [(id: CGDirectDisplayID, bounds: CGRect)]
	) -> CGDirectDisplayID? {
		var best: (id: CGDirectDisplayID, area: CGFloat)?
		for display in displays {
			let overlap = rect.intersection(display.bounds)
			guard !overlap.isNull, !overlap.isEmpty else { continue }
			let area = overlap.width * overlap.height
			if area > (best?.area ?? 0) {
				best = (display.id, area)
			}
		}
		return best?.id
	}

	/// Native pixel size of `display`, or nil when ScreenCaptureKit and CoreGraphics
	/// both report degenerate values (e.g. mid display reconfiguration).
	static func nativePixelSize(of display: SCDisplay) -> (width: Int, height: Int)? {
		var width = 0
		var height = 0
		if #available(macOS 14.0, *) {
			let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
			let scale = CGFloat(filter.pointPixelScale)
			width = finitePixelDimension(filter.contentRect.width * scale) ?? 0
			height = finitePixelDimension(filter.contentRect.height * scale) ?? 0
		}
		if width <= 1 || height <= 1 {
			if let mode = CGDisplayCopyDisplayMode(display.displayID) {
				width = mode.pixelWidth
				height = mode.pixelHeight
			} else {
				width = display.width
				height = display.height
			}
		}
		guard width > 1, height > 1 else { return nil }
		return (width, height)
	}

	/// The display with the most pixels. Following capture is sized to it so a
	/// switch to the biggest screen never loses detail.
	static func largestDisplay(
		in content: SCShareableContent
	) -> (display: SCDisplay, width: Int, height: Int)? {
		var best: (display: SCDisplay, width: Int, height: Int)?
		for display in content.displays {
			guard let size = nativePixelSize(of: display) else { continue }
			if size.width * size.height > (best.map { $0.width * $0.height } ?? 0) {
				best = (display, size.width, size.height)
			}
		}
		return best
	}

	/// Bounds of the app's frontmost normal window. The window list is ordered
	/// front to back, so the first match is the one the user is looking at.
	private static func frontmostWindowBounds(ownedBy pid: pid_t) -> CGRect? {
		guard
			let windows = CGWindowListCopyWindowInfo(
				[.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
			) as? [[String: Any]]
		else {
			return nil
		}
		for window in windows {
			guard
				(window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
				(window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
				((window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
				let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
				let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
				bounds.width >= minimumWindowSide, bounds.height >= minimumWindowSide
			else {
				continue
			}
			return bounds
		}
		return nil
	}

	/// Active displays, leaving out mirrors (ScreenCaptureKit only lists the source).
	private static func activeDisplays() -> [(id: CGDirectDisplayID, bounds: CGRect)] {
		var count: UInt32 = 0
		guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
		var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
		guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
		return ids.prefix(Int(count))
			.filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
			.map { (id: $0, bounds: CGDisplayBounds($0)) }
	}
}

extension SCShareableContent {
	/// Current on-screen shareable content.
	static func loadOnScreen() async throws -> SCShareableContent {
		if #available(macOS 14.0, *) {
			return try await SCShareableContent.excludingDesktopWindows(
				false, onScreenWindowsOnly: true
			)
		}
		return try await SCShareableContent.current
	}
}
