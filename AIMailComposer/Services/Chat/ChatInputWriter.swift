import ApplicationServices
import Foundation

/// Finds a chat app's message box through the Accessibility (AX) API and
/// writes text into it. Counterpart to `AccessibilityWriter`, which knows
/// Mail's compose window specifically.
///
/// Discord (Chromium) exposes its composer as an `AXTextArea` described
/// "Message @name" or "Message #channel". WhatsApp's Catalyst build exposes
/// a text area with a "Type a message" placeholder. In both apps the
/// composer sits at the bottom of the window, below any search box, so the
/// bottom-most editable text element is the composer and a "message"-like
/// label breaks ties. The app's focused element wins outright when it is
/// already a text input: that is where the user was typing.
enum ChatInputWriter {

    enum WriteResult {
        /// The text was written into the message box.
        case inserted
        /// The message box was found and focused but rejected the AX text
        /// write. A synthetic paste into it will land correctly.
        case inputFocused
        /// No message box was found, or AX permission is missing.
        case failed
    }

    /// Cap AX calls so a busy Electron app can't stall the insert action.
    private static let messagingTimeout: Float = 1.5
    /// Chromium trees can be huge; stop walking after this many elements.
    private static let maxVisitedNodes = 6000
    private static let maxDepth = 60
    private static let textRoles: Set<String> = ["AXTextArea", "AXTextField"]
    /// Lower-cased substrings that mark a composer label in the locales
    /// most users of this app run their chat clients in.
    private static let composerLabelHints = ["message", "nachricht"]

    static func insert(_ text: String, intoAppWithPID pid: pid_t) -> WriteResult {
        guard AXIsProcessTrusted() else { return .failed }
        // The timeout must be set on the system-wide element: set on any
        // other element it only caps messages to that element.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)

        let app = AXUIElementCreateApplication(pid)
        guard let input = findComposer(in: app) else { return .failed }
        if let window = element(input, kAXWindowAttribute) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        return write(text, into: input)
    }

    // MARK: - Lookup

    static func findComposer(in app: AXUIElement) -> AXUIElement? {
        if let focused = element(app, kAXFocusedUIElementAttribute),
           let role = string(focused, kAXRoleAttribute),
           textRoles.contains(role) {
            return focused
        }

        let window = element(app, kAXFocusedWindowAttribute)
            ?? (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first
        guard let window else { return nil }

        var candidates: [Candidate] = []
        var visited = 0
        collectTextInputs(in: window, depth: 0, visited: &visited, into: &candidates)

        return candidates.max { lhs, rhs in
            if lhs.isLabeledComposer != rhs.isLabeledComposer { return !lhs.isLabeledComposer }
            return lhs.bottom < rhs.bottom
        }?.element
    }

    private struct Candidate {
        let element: AXUIElement
        /// Bottom edge in window server coordinates (top-left origin), so a
        /// larger value means lower on screen.
        let bottom: CGFloat
        let isLabeledComposer: Bool
    }

    private static func collectTextInputs(
        in element: AXUIElement,
        depth: Int,
        visited: inout Int,
        into out: inout [Candidate]
    ) {
        visited += 1
        guard visited <= maxVisitedNodes, depth <= maxDepth else { return }

        if let role = string(element, kAXRoleAttribute), textRoles.contains(role) {
            let label = [
                string(element, kAXDescriptionAttribute),
                string(element, kAXPlaceholderValueAttribute),
                string(element, kAXTitleAttribute),
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            let labeled = composerLabelHints.contains { label.contains($0) }
            out.append(Candidate(element: element, bottom: frame(of: element).maxY, isLabeledComposer: labeled))
        }

        for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            collectTextInputs(in: child, depth: depth + 1, visited: &visited, into: &out)
        }
    }

    // MARK: - Write

    /// Focus the box, move the caret to the end of any existing draft, and
    /// replace that empty selection with `text`. WebKit and Chromium editors
    /// reject `AXValue` writes, so `AXSelectedText` is the portable edit
    /// primitive here as in `AccessibilityWriter`.
    private static func write(_ text: String, into input: AXUIElement) -> WriteResult {
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        let existing = string(input, kAXValueAttribute) ?? ""
        var end = CFRange(location: existing.utf16.count, length: 0)
        if let range = AXValueCreate(.cfRange, &end) {
            AXUIElementSetAttributeValue(input, kAXSelectedTextRangeAttribute as CFString, range)
        }

        let needsSeparator = !existing.isEmpty && !(existing.last?.isWhitespace ?? true)
        let payload = needsSeparator ? " " + text : text
        let err = AXUIElementSetAttributeValue(input, kAXSelectedTextAttribute as CFString, payload as CFString)
        guard err == .success else { return .inputFocused }

        // Editors can report success without applying the edit. Read back
        // and check the text actually landed; a nil value means the element
        // doesn't expose its text, trust the success code then.
        if let value = string(input, kAXValueAttribute) {
            let probe = text
                .components(separatedBy: .newlines)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if let probe, !value.contains(probe) {
                return .inputFocused
            }
        }
        return .inserted
    }

    // MARK: - AX helpers

    private static func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, name as CFString, &ref)
        return ref
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String? {
        attribute(el, name) as? String
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let ref = attribute(el, name), CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    private static func frame(of el: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let ref = attribute(el, kAXPositionAttribute), CFGetTypeID(ref) == AXValueGetTypeID() {
            AXValueGetValue(unsafeDowncast(ref, to: AXValue.self), .cgPoint, &origin)
        }
        if let ref = attribute(el, kAXSizeAttribute), CFGetTypeID(ref) == AXValueGetTypeID() {
            AXValueGetValue(unsafeDowncast(ref, to: AXValue.self), .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }
}
