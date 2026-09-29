import Foundation
import AppKit

/// Writes the generated reply into the Mail compose window via the
/// Accessibility (AX) API.
///
/// Counterpart to `AccessibilityReader`: recent macOS versions broke Mail's
/// `outgoing messages` AppleScript collection, so `set content of outgoing
/// message 1` silently does nothing even with a compose window open. This
/// writer locates the compose window's "message body" web area, focuses it,
/// and places the caret at the start. `MailBridge` then pastes the reply and
/// verifies the complete text before reporting success.
enum AccessibilityWriter {

    enum WriteResult {
        /// The compose body is focused with its caret at the start.
        case pasteReady
        /// No compose body was found, or AX permission is missing.
        case failed
    }

    /// Cap AX calls at this many seconds so a busy Mail doesn't stall the
    /// insert action. Mirrors `AccessibilityReader.messagingTimeout`.
    private static let messagingTimeout: Float = 1.5

    /// Focus the first compose window's message body and put its caret at the
    /// start. Mail's WebKit editor currently reports successful AXSelectedText
    /// writes while occasionally dropping the final character, so the actual
    /// insertion is deliberately left to the verified paste path.
    static func insertIntoComposeBody(_: String) -> WriteResult {
        guard AXIsProcessTrusted() else { return .failed }

        guard let mailApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first else {
            return .failed
        }
        // The timeout must be set on the system-wide element: set on any
        // other element it only caps messages to that element.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)

        let app = AXUIElementCreateApplication(mailApp.processIdentifier)

        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement] else { return .failed }

        for window in windows {
            // Skip the main viewer window by identifier — its tree contains
            // the message table and can be enormous.
            if let id = axIdentifier(window), id == "Mail.messageViewer.window" {
                continue
            }
            guard let body = findMessageBody(in: window) else { continue }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return prepareForPaste(body)
        }
        return .failed
    }

    /// Post a ⌘V key-down/key-up pair to Mail after the compose body has been
    /// focused. The caller is responsible for putting the reply on the
    /// clipboard and verifying the resulting draft.
    static func pasteCommandV(pid: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
    }

    /// Verify that the complete reply is now present in the open compose body.
    /// Checking only the first line hid truncated pastes such as "Kevin"
    /// becoming "Kevi".
    static func composeBodyContains(_ text: String) -> Bool {
        let probe = normalizedText(text)
        guard !probe.isEmpty,
              AXIsProcessTrusted(),
              let mailApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first else {
            return false
        }

        let app = AXUIElementCreateApplication(mailApp.processIdentifier)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement] else { return false }

        for window in windows {
            if let id = axIdentifier(window), id == "Mail.messageViewer.window" { continue }
            guard let body = findMessageBody(in: window) else { continue }
            if let value = axValue(body), normalizedText(value).contains(probe) {
                return true
            }
            let descendantText = descendantValues(in: body).joined(separator: "\n")
            if normalizedText(descendantText).contains(probe) {
                return true
            }
        }
        return false
    }

    // MARK: - Body lookup

    /// The compose body is an `AXWebArea` described as "message body".
    /// Prefer its inner `AXTextArea` (the editable element); fall back to
    /// the web area itself.
    private static func findMessageBody(in window: AXUIElement) -> AXUIElement? {
        let webArea = findDescendant(of: window) { el in
            axRole(el) == "AXWebArea" && axDescription(el) == "message body"
        }
        guard let webArea else { return nil }

        if let textArea = findDescendant(of: webArea, where: { axRole($0) == "AXTextArea" }) {
            return textArea
        }
        return webArea
    }

    private static func findDescendant(
        of element: AXUIElement,
        where predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        if predicate(element) { return element }
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let match = findDescendant(of: child, where: predicate) {
                return match
            }
        }
        return nil
    }

    private static func descendantValues(in element: AXUIElement) -> [String] {
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard let children = childrenRef as? [AXUIElement], !children.isEmpty else {
            return axValue(element).map { [$0] } ?? []
        }
        return children.flatMap(descendantValues(in:))
    }

    static func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    // MARK: - Write

    /// Focus the body and collapse the selection to the very start so the
    /// subsequent paste is inserted above the quoted thread.
    private static func prepareForPaste(_ body: AXUIElement) -> WriteResult {
        let focusError = AXUIElementSetAttributeValue(
            body,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        guard focusError == .success else { return .failed }

        var start = CFRange(location: 0, length: 0)
        guard let rangeValue = AXValueCreate(.cfRange, &start) else { return .failed }
        let rangeError = AXUIElementSetAttributeValue(
            body,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )
        return rangeError == .success ? .pasteReady : .failed
    }

    // MARK: - AX helpers

    private static func axRole(_ el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &ref)
        return ref as? String
    }

    private static func axDescription(_ el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &ref)
        return ref as? String
    }

    private static func axValue(_ el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &ref)
        return ref as? String
    }

    private static func axIdentifier(_ el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXIdentifierAttribute as CFString, &ref)
        return ref as? String
    }
}
