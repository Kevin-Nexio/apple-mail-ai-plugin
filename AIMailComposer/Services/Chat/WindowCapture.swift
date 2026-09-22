import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum WindowCaptureError: LocalizedError {
    case windowGone
    case captureFailed(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .windowGone:
            return "The chat window disappeared before it could be captured."
        case .captureFailed(let msg):
            return "Couldn't capture the window: \(msg)"
        case .encodingFailed:
            return "Couldn't encode the screenshot."
        }
    }
}

/// Screenshots a single app window with ScreenCaptureKit.
///
/// `desktopIndependentWindow` filters render only that window's own pixels,
/// so the composer panel floating over the chat never ends up in the shot.
/// The result is scaled so the longest edge is at most `maxDimension` pixels
/// and encoded as PNG, keeping chat text crisp while staying well inside
/// every provider's per-image size limit.
enum WindowCapture {

    struct WindowInfo: Equatable {
        let id: CGWindowID
        /// Window title. Empty without Screen Recording permission.
        let title: String
        /// Screen frame in points, top-left origin (window server coordinates).
        let frame: CGRect
    }

    /// Longest edge of the encoded screenshot, in pixels.
    static let maxDimension: CGFloat = 1568
    /// PNGs above this many bytes are re-encoded as JPEG.
    static let pngByteLimit = 3_000_000
    /// Anything smaller is a tooltip, popover, or menu, not a chat window.
    static let minimumWindowSize = CGSize(width: 200, height: 150)

    /// On-screen, normal-layer windows owned by `pid`, front to back, which
    /// is the order `CGWindowListCopyWindowInfo` documents.
    static func windows(ownedBy pid: pid_t) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            guard bounds.width >= minimumWindowSize.width, bounds.height >= minimumWindowSize.height else {
                return nil
            }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha == 0 {
                return nil
            }
            let title = info[kCGWindowName as String] as? String ?? ""
            return WindowInfo(id: CGWindowID(number), title: title, frame: bounds)
        }
    }

    /// Output pixel size for a window: its native backing resolution, shrunk
    /// so the longer edge is at most `maxDimension`, aspect ratio preserved.
    static func outputSize(for frame: CGSize, scale: CGFloat, maxDimension: CGFloat = maxDimension) -> (width: Int, height: Int) {
        var width = frame.width * scale
        var height = frame.height * scale
        let longest = max(width, height)
        if longest > maxDimension, longest > 0 {
            let factor = maxDimension / longest
            width *= factor
            height *= factor
        }
        return (max(1, Int(width.rounded())), max(1, Int(height.rounded())))
    }

    /// Screenshot `window`. Requires Screen Recording permission; without it
    /// the shareable-content lookup throws.
    static func capture(window: WindowInfo) async throws -> CapturedImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw WindowCaptureError.captureFailed(error.localizedDescription)
        }
        guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else {
            throw WindowCaptureError.windowGone
        }

        let scale = await MainActor.run { backingScale(for: window.frame) }
        let size = outputSize(for: scWindow.frame.size, scale: scale)

        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = true

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw WindowCaptureError.captureFailed(error.localizedDescription)
        }
        return try encode(image)
    }

    /// PNG for crisp text; JPEG when the PNG would bloat the request.
    static func encode(_ image: CGImage) throws -> CapturedImage {
        if let png = encode(image, type: .png, quality: nil), png.count <= pngByteLimit {
            return CapturedImage(cgImage: image, data: png, mediaType: "image/png")
        }
        if let jpeg = encode(image, type: .jpeg, quality: 0.85) {
            return CapturedImage(cgImage: image, data: jpeg, mediaType: "image/jpeg")
        }
        throw WindowCaptureError.encodingFailed
    }

    private static func encode(_ image: CGImage, type: UTType, quality: Double?) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Backing scale of the screen showing the window's centre. `frame` uses
    /// the window server's top-left origin, so flip it into Cocoa
    /// coordinates before matching against `NSScreen` frames.
    @MainActor
    private static func backingScale(for frame: CGRect) -> CGFloat {
        let screens = NSScreen.screens
        guard let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first else {
            return 2
        }
        let cocoaY = primary.frame.height - frame.origin.y - frame.height
        let center = CGPoint(x: frame.midX, y: cocoaY + frame.height / 2)
        let screen = screens.first(where: { $0.frame.contains(center) }) ?? primary
        return screen.backingScaleFactor
    }
}
