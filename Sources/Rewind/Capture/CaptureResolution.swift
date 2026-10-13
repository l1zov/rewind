import CoreGraphics
import ScreenCaptureKit

/// Safely converts a pixel dimension expressed as a floating-point value to an `Int`.
///
/// `Int(Double)` traps on non-finite or out-of-range values. ScreenCaptureKit can report
/// degenerate `contentRect`/`pointPixelScale` values (e.g. during display reconfiguration or
/// sleep/wake), so this guards against those to avoid a crash and lets callers fall back.
func finitePixelDimension(_ value: CGFloat) -> Int? {
	guard value.isFinite, value > 0, value < CGFloat(Int32.max) else { return nil }
	return Int(value)
}

/// represents a capture resolution option
struct CaptureResolution: Hashable, Identifiable {
	let id: String
	let label: String
	let width: Int
	let height: Int
	let isNative: Bool

	var size: CGSize {
		CGSize(width: width, height: height)
	}

	/// keeps native capture exact
	var alignedSize: CGSize {
		let alignedWidth = max(2, width - (width % 2))
		let alignedHeight = max(2, height - (height % 2))
		return CGSize(width: alignedWidth, height: alignedHeight)
	}

	static func native(width: Int, height: Int) -> CaptureResolution {
		CaptureResolution(
			id: "native",
			label: "Native (\(width)×\(height))",
			width: width,
			height: height,
			isNative: true
		)
	}

	static func scaled(label: String, width: Int, height: Int) -> CaptureResolution {
		CaptureResolution(
			id: "\(width)x\(height)",
			label: "\(label) (\(width)×\(height))",
			width: width,
			height: height,
			isNative: false
		)
	}

	/// This choice applied to what is actually being captured.
	///
	/// The resolution list is worked out from the main display, but the target can
	/// be another display or a window of a different size. "Native" then means the
	/// target's own pixels, and a scaled preset keeps its height while taking the
	/// target's aspect ratio, so the video isn't letterboxed or stretched into the
	/// main display's shape.
	func matching(nativeWidth: Int, nativeHeight: Int) -> CaptureResolution {
		let native = CaptureResolution.native(width: nativeWidth, height: nativeHeight)
		guard !isNative, nativeWidth > 0, nativeHeight > 0, height < nativeHeight else { return native }

		let scaledWidth = Int((CGFloat(height) * CGFloat(nativeWidth) / CGFloat(nativeHeight)).rounded())
		let alignedWidth = max(2, scaledWidth - (scaledWidth % 2))
		let alignedHeight = max(2, height - (height % 2))
		guard alignedWidth < nativeWidth else { return native }

		let name = label.prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces)
		return .scaled(label: name, width: alignedWidth, height: alignedHeight)
	}
}

/// provides available resolutions for screen capture
@MainActor
enum CaptureResolutionProvider {
	private static let nativeDimensionAttempts = 3
	private static let nativeDimensionRetryNanos: UInt64 = 200_000_000

	/// returns available resolutions for the main display
	static func availableResolutions() async -> [CaptureResolution] {
		guard let (nativeWidth, nativeHeight) = await getNativePixelDimensions() else {
			return []
		}

		var resolutions: [CaptureResolution] = []

		resolutions.append(.native(width: nativeWidth, height: nativeHeight))

		let aspectRatio = CGFloat(nativeWidth) / CGFloat(nativeHeight)

		let targetHeights = [2160, 1440, 1080, 720]

		for height in targetHeights {
			let width = Int((CGFloat(height) * aspectRatio).rounded())
			if width >= nativeWidth || height >= nativeHeight { continue }
			let alignedWidth = max(2, width - (width % 2))
			let alignedHeight = max(2, height - (height % 2))

			let label: String
			switch height {
			case 2160: label = "4K"
			case 1440: label = "QHD"
			case 1080: label = "1080p"
			case 720: label = "720p"
			default: label = "\(height)p"
			}

			resolutions.append(.scaled(label: label, width: alignedWidth, height: alignedHeight))
		}

		return resolutions
	}

	/// returns the native pixel resolution of the main display
	static func nativeResolution() async -> CaptureResolution? {
		guard let (width, height) = await getNativePixelDimensions() else { return nil }
		return .native(width: width, height: height)
	}

	private static func getNativePixelDimensions() async -> (width: Int, height: Int)? {
		for attempt in 1 ... nativeDimensionAttempts {
			do {
				let content: SCShareableContent
				if #available(macOS 14.0, *) {
					content = try await SCShareableContent.excludingDesktopWindows(
						false, onScreenWindowsOnly: true
					)
				} else {
					content = try await SCShareableContent.current
				}
				guard let display = content.displays.first else {
					AppLog.info(
						.app,
						"No displays available from ScreenCaptureKit while loading resolutions. Attempt",
						attempt
					)
					if attempt < nativeDimensionAttempts {
						try? await Task.sleep(nanoseconds: nativeDimensionRetryNanos)
						continue
					}
					return nil
				}

				let filter = SCContentFilter(
					display: display, excludingApplications: [], exceptingWindows: []
				)

				var nativeWidth = 0
				var nativeHeight = 0

				if #available(macOS 14.0, *) {
					let scale = CGFloat(filter.pointPixelScale)
					let contentRect = filter.contentRect
					nativeWidth = finitePixelDimension(contentRect.width * scale) ?? 0
					nativeHeight = finitePixelDimension(contentRect.height * scale) ?? 0
				}

				if nativeWidth <= 1 || nativeHeight <= 1 {
					let displayID = display.displayID
					if let mode = CGDisplayCopyDisplayMode(displayID) {
						nativeWidth = mode.pixelWidth
						nativeHeight = mode.pixelHeight
					} else {
						nativeWidth = display.width
						nativeHeight = display.height
					}
				}

				guard nativeWidth > 1, nativeHeight > 1 else {
					AppLog.info(
						.app, "Display mode unavailable while loading resolutions. Attempt", attempt
					)
					if attempt < nativeDimensionAttempts {
						try? await Task.sleep(nanoseconds: nativeDimensionRetryNanos)
						continue
					}
					return nil
				}

				return (nativeWidth, nativeHeight)
			} catch {
				AppLog.info(.app, "fetch shareable content Attempt", attempt, "error:", error)
				if attempt < nativeDimensionAttempts {
					try? await Task.sleep(nanoseconds: nativeDimensionRetryNanos)
					continue
				}
				return nil
			}
		}
		return nil
	}
}
