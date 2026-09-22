import CoreGraphics
import Foundation

/// A screenshot ready to be sent to a model: the image for the panel's
/// thumbnail plus its encoded bytes for the request.
struct CapturedImage {
    let cgImage: CGImage
    let data: Data
    /// MIME type of `data`: `image/png` normally, `image/jpeg` when the PNG
    /// came out too large for a request.
    let mediaType: String

    var attachment: AIAttachment { AIAttachment(data: data, mediaType: mediaType) }
}

/// Snapshot of a chat app's front window at the moment the shortcut fired.
/// There is no structured thread like in Mail: the screenshot *is* the
/// conversation context and the model reads the messages from the image.
struct ChatContext {
    let target: ComposerTarget
    /// Window title from the window server, e.g. "@Lars - Discord". Empty
    /// without Screen Recording permission, because macOS hides titles then.
    let windowTitle: String
    /// `nil` when Screen Recording permission is missing or capture failed.
    let screenshot: CapturedImage?
    /// Why `screenshot` is nil when the cause is a capture failure rather
    /// than a missing permission.
    let captureError: String?
    /// The window's screen frame in points with a top-left origin (window
    /// server coordinates), used to anchor the panel next to the window.
    let windowFrame: CGRect?

    var hasScreenshot: Bool { screenshot != nil }

    var displayTitle: String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? target.displayName : trimmed
    }
}
