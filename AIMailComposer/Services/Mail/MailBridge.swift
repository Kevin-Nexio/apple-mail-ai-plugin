import Foundation
import AppKit

enum MailBridgeError: LocalizedError {
    case scriptFailed(String)
    case noComposer
    case mailNotRunning
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let msg):
            return "AppleScript error: \(msg)"
        case .noComposer:
            return "Open a compose window in Mail first, then try again."
        case .mailNotRunning:
            return "Mail is not running. Open Mail and try again."
        case .parseError(let msg):
            return "Failed to parse Mail context: \(msg)"
        }
    }
}

final class MailBridge {
    enum InsertResult: Equatable {
        case inserted
        case copiedOnly(String)
    }

    static func executeAppleScript(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: MailBridgeError.scriptFailed("Failed to create script"))
                    return
                }
                let result = script.executeAndReturnError(&error)
                if let error = error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: MailBridgeError.scriptFailed(message))
                } else {
                    continuation.resume(returning: result.stringValue ?? "")
                }
            }
        }
    }

    static func isMailRunning() async -> Bool {
        do {
            let result = try await executeAppleScript(MailScripts.checkMailRunning)
            return result.lowercased() == "true"
        } catch {
            return false
        }
    }

    /// Pull context from the currently open Mail compose window, falling
    /// back to the Accessibility reader when Mail's `outgoing messages`
    /// AppleScript collection is empty (recent macOS versions). Never
    /// blocks on Accessibility permission: if AX isn't granted, the
    /// AppleScript context is returned as-is so the UI can offer a
    /// dismissible banner instead of a permission wall.
    ///
    /// Never reads from the message list — the compose window is the source
    /// of truth.
    static func fetchComposerContext() async throws -> ComposerContext {
        guard await isMailRunning() else {
            throw MailBridgeError.mailNotRunning
        }

        let raw = try await executeAppleScript(MailScripts.fetchComposerContext)

        if raw.hasPrefix("ERROR:NO_COMPOSER") {
            throw MailBridgeError.noComposer
        }

        let context = try MailThreadParser.parseComposerContext(raw)

        // If Pass 1 (outgoing messages) found nothing but Pass 2 identified
        // a compose window by name, the AppleScript path is broken (recent
        // macOS versions). Fall back to the Accessibility reader when
        // permission is granted; otherwise return the context as-is.
        if context.recipients.isEmpty && context.currentDraft.isEmpty {
            return await enrichViaAccessibility(context: context)
        }

        return context
    }

    static func fetchTodayInboxMessages(limit: Int = 25) async throws -> [MailInboxMessage] {
        guard await isMailRunning() else {
            throw MailBridgeError.mailNotRunning
        }
        let raw = try await executeAppleScript(MailScripts.fetchTodayInboxMessages(limit: limit))
        return MailInboxParser.parse(raw)
    }

    static func searchInboxMessages(query: String, limit: Int = 25) async throws -> [MailInboxMessage] {
        guard await isMailRunning() else {
            throw MailBridgeError.mailNotRunning
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let raw = try await executeAppleScript(MailScripts.searchInboxMessages(query: trimmed, limit: limit))
        return MailInboxParser.parse(raw)
    }

    /// Saves one reply as a draft in Mail. The corresponding script contains
    /// no send command and returns only after Mail confirms the save.
    static func createReplyDraft(for message: MailInboxMessage, body: String) async throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MailBridgeError.scriptFailed("The generated draft is empty")
        }
        let result = try await executeAppleScript(
            MailScripts.createReplyDraft(messageID: message.id, body: trimmed)
        )
        guard result == "DRAFT_CREATED" else {
            let detail = result.hasPrefix("ERROR:") ? String(result.dropFirst("ERROR:".count)) : result
            throw MailBridgeError.scriptFailed(detail)
        }
    }

    static func fetchMessageViewerFrame() async -> CGRect? {
        guard let raw = try? await executeAppleScript(MailScripts.fetchMessageViewerFrame) else { return nil }
        let values = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4 else { return nil }
        return CGRect(
            x: values[0],
            y: values[1],
            width: values[2] - values[0],
            height: values[3] - values[1]
        )
    }

    /// Opportunistically enrich the context via the AX reader. If AX isn't
    /// trusted or no compose window is found, the original context is
    /// returned unchanged — never throws.
    private static func enrichViaAccessibility(context: ComposerContext) async -> ComposerContext {
        guard AXPermissionChecker.isGranted() else {
            return context
        }

        let ax = await Task.detached(priority: .userInitiated) {
            AccessibilityReader.readComposeWindow()
        }.value

        guard let ax else {
            // AX is granted but no compose window was found — return the
            // original (possibly empty) context rather than failing.
            return context
        }

        let thread = context.thread
        let subject = ax.subject.isEmpty ? context.subject : ax.subject

        return ComposerContext(
            recipients: ax.recipients,
            subject: subject,
            currentDraft: ax.draftContent,
            thread: thread,
            composeWindowFrame: context.composeWindowFrame
        )
    }

    /// Write the reply directly into the current Mail compose window.
    ///
    /// Three passes, mirroring the read path's AppleScript → AX fallback:
    ///   1. Mail scripting API (`content of outgoing message 1`) — works on
    ///      older macOS versions.
    ///   2. AX locates the compose body, focuses it, and puts the caret at
    ///      the start. This handles recent macOS versions where pass 1
    ///      silently no-ops.
    ///   3. Synthetic ⌘V inserts through Mail's own editor, followed by a
    ///      complete read-back check.
    /// The clipboard is populated first so a manual paste works no matter
    /// which pass ran.
    @MainActor
    static func insertReply(_ text: String) async -> InsertResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Pass 1: Mail scripting API.
        let scriptResult = (try? await executeAppleScript(MailScripts.insertReply(text))) ?? ""
        if scriptResult.hasPrefix("INSERTED") {
            activateMail()
            return .inserted
        }

        // Pass 2: AX writer. Activate Mail first so focusing the compose
        // body sticks. The walk is IPC-heavy — keep it off the main thread.
        activateMail()
        let result = await Task.detached(priority: .userInitiated) {
            AccessibilityWriter.insertIntoComposeBody(text)
        }.value

        switch result {
        case .failed:
            if !AXPermissionChecker.isGranted() {
                return .copiedOnly(
                    "Mail did not accept the reply because Accessibility is not active for this installed build. "
                        + "The text is on your clipboard. Re-enable Apple Mail AI Plugin in System Settings, then try again."
                )
            }
            return .copiedOnly(
                "Mail's compose body could not be reached. The text is on your clipboard; keep this window open and try again."
            )
        case .pasteReady:
            // Pass 3: the body is focused with its caret at the start. Paste
            // through Mail's editor because direct AX text writes can report
            // success while truncating the final character.
            guard let mail = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first else {
                return .copiedOnly("Mail is no longer running. The text is on your clipboard.")
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            AccessibilityWriter.pasteCommandV(pid: mail.processIdentifier)
            try? await Task.sleep(nanoseconds: 350_000_000)
            if AccessibilityWriter.composeBodyContains(text) {
                return .inserted
            }
            return .copiedOnly(
                "Mail focused the draft but did not accept the paste. The text is on your clipboard; press ⌘V in the message body."
            )
        }
    }

    @MainActor
    private static func activateMail() {
        if let mailApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first {
            mailApp.activate()
        }
    }
}
