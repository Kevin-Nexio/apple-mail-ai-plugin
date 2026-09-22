import AppKit

enum ChatBridgeError: LocalizedError {
    case appNotRunning(ComposerTarget)
    case noWindow(ComposerTarget)

    var errorDescription: String? {
        switch self {
        case .appNotRunning(let target):
            return "\(target.displayName) is not running. Open it and try again."
        case .noWindow(let target):
            return "No \(target.displayName) window found. Open a chat and try again."
        }
    }
}

/// Reads context from, and writes messages into, Discord and WhatsApp.
/// Chat-app counterpart of `MailBridge`.
enum ChatBridge {

    enum InsertOutcome {
        /// Written straight into the message box via Accessibility.
        case inserted
        /// The message box was focused and the text pasted into it.
        case pasted
        /// The text is on the clipboard only; the user pastes it themselves.
        case copiedOnly
    }

    /// Locate the target app's front window and screenshot it. A missing
    /// Screen Recording permission or a capture failure yields a context
    /// without a screenshot rather than an error, so the panel can show a
    /// banner instead of a permission wall, matching the Mail flow.
    @MainActor
    static func fetchContext(for target: ComposerTarget) async throws -> ChatContext {
        guard let app = target.runningApplication else {
            throw ChatBridgeError.appNotRunning(target)
        }
        guard let window = WindowCapture.windows(ownedBy: app.processIdentifier).first else {
            throw ChatBridgeError.noWindow(target)
        }

        var screenshot: CapturedImage?
        var captureError: String?
        if ScreenCapturePermission.isGranted() {
            do {
                screenshot = try await WindowCapture.capture(window: window)
            } catch {
                captureError = error.localizedDescription
            }
        }

        return ChatContext(
            target: target,
            windowTitle: window.title,
            screenshot: screenshot,
            captureError: captureError,
            windowFrame: window.frame
        )
    }

    /// Put `text` into the chat app's message box without sending it.
    ///
    /// The clipboard is populated first so a manual paste works whatever
    /// happens next. Then, with Accessibility granted, the app is activated
    /// and the message box located; the text is written via AX, or pasted
    /// with a synthetic ⌘V when the box rejects the AX write. Without a
    /// located box nothing is pasted blindly: that could land in a search
    /// field.
    @MainActor
    static func insertMessage(_ text: String, into target: ComposerTarget) async -> InsertOutcome {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let app = target.runningApplication else { return .copiedOnly }
        app.activate()
        guard AXPermissionChecker.isGranted() else { return .copiedOnly }

        // Let the app finish activating so the focus change sticks.
        try? await Task.sleep(nanoseconds: 250_000_000)

        let pid = app.processIdentifier
        let result = await Task.detached(priority: .userInitiated) {
            ChatInputWriter.insert(text, intoAppWithPID: pid)
        }.value

        switch result {
        case .inserted:
            return .inserted
        case .inputFocused:
            try? await Task.sleep(nanoseconds: 150_000_000)
            AccessibilityWriter.pasteCommandV(pid: pid)
            return .pasted
        case .failed:
            return .copiedOnly
        }
    }
}
