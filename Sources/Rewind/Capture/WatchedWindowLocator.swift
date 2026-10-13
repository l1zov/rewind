import AppKit
import CoreGraphics

/// One on-screen window of a watched app.
struct WatchedWindow: Equatable {
	let processID: pid_t
	let frame: CGRect
}

/// Where the watched apps are right now: the processes that own a visible window,
/// and the display that should be recorded for them.
struct WatchedTarget: Equatable {
	var processIDs: Set<pid_t>
	/// nil when none of the watched apps has a visible window.
	var displayID: CGDirectDisplayID?
	/// The chosen display's size in pixels, nil when it can't be read.
	var displayPixelSize: CGSize?
}

enum WatchedWindowLocator {
	/// Windows narrower or shorter than this are treated as helpers, not content.
	static let minimumSide: CGFloat = 40

	/// Pure parsing of `CGWindowListCopyWindowInfo` output, kept separate so it can
	/// be tested with plain dictionaries.
	///
	/// Keeps visible, normal-layer windows owned by `processIDs`, in the order
	/// given (front to back for `CGWindowListOption.optionOnScreenOnly`).
	static func windows(in windowInfo: [[String: Any]], ownedBy processIDs: Set<pid_t>) -> [WatchedWindow] {
		windowInfo.compactMap { entry in
			guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
			      processIDs.contains(pid),
			      (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
			else { return nil }

			if let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0 { return nil }
			if let onScreen = (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue, !onScreen { return nil }

			guard let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
			      let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
			      frame.width >= minimumSide, frame.height >= minimumSide
			else { return nil }
			return WatchedWindow(processID: pid, frame: frame)
		}
	}

	/// The watched apps' current target, read from the window server. Needs no
	/// Screen Recording permission (only window titles are withheld without it).
	@MainActor
	static func target(forBundleIDs bundleIDs: Set<String>) -> WatchedTarget {
		let processIDs = Set(
			NSWorkspace.shared.runningApplications
				.filter { app in app.bundleIdentifier.map(bundleIDs.contains) ?? false }
				.map(\.processIdentifier)
		)
		guard !processIDs.isEmpty else { return WatchedTarget(processIDs: [], displayID: nil) }

		let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
			as? [[String: Any]] ?? []
		let windows = windows(in: info, ownedBy: processIDs)
		let displays = activeDisplays()
		let displayID = DisplaySelection.displayID(forWindows: windows.map(\.frame), displays: displays)
		return WatchedTarget(
			processIDs: Set(windows.map(\.processID)),
			displayID: displayID,
			displayPixelSize: displays.first { $0.id == displayID }?.pixelSize
		)
	}

	/// The active displays, main display first.
	static func activeDisplays() -> [DisplayGeometry] {
		var count: UInt32 = 0
		guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
		var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
		guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

		let active = Array(ids.prefix(Int(count)))
		let main = CGMainDisplayID()
		return (active.filter { $0 == main } + active.filter { $0 != main }).map { id in
			let frame = CGDisplayBounds(id)
			let mode = CGDisplayCopyDisplayMode(id)
			let pixelSize = mode.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) } ?? frame.size
			return DisplayGeometry(id: id, frame: frame, pixelSize: pixelSize)
		}
	}
}
