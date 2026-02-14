import CoreGraphics
import ScreenCaptureKit

/// represents a capture resolution option
struct CaptureResolution: Hashable, Identifiable, Sendable {
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
    if isNative {
      return CGSize(width: width, height: height)
    }

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
    for attempt in 1...nativeDimensionAttempts {
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
          AppLog.info(.app, "No displays available from ScreenCaptureKit while loading resolutions. Attempt", attempt)
          if attempt < nativeDimensionAttempts {
            try? await Task.sleep(nanoseconds: nativeDimensionRetryNanos)
            continue
          }
          return nil
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let nativeWidth: Int
        let nativeHeight: Int

        if #available(macOS 14.0, *) {
          let scale = CGFloat(filter.pointPixelScale)
          let contentRect = filter.contentRect
          nativeWidth = Int(contentRect.width * scale)
          nativeHeight = Int(contentRect.height * scale)
        } else {
          let displayID = display.displayID
          guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            AppLog.info(.app, "Display mode unavailable while loading resolutions. Attempt", attempt)
            if attempt < nativeDimensionAttempts {
              try? await Task.sleep(nanoseconds: nativeDimensionRetryNanos)
              continue
            }
            return nil
          }
          nativeWidth = mode.pixelWidth
          nativeHeight = mode.pixelHeight
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
