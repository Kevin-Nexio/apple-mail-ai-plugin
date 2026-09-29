import AppKit
import Foundation
import SwiftUI

@MainActor
final class ComposerViewModel: ObservableObject {
    enum State: Equatable {
        case loadingContext
        case ready
        case generating   // request sent, no chunks received yet
        case complete     // have content (may still be streaming — see isStreaming)
        case error(String, recoveryURL: URL? = nil)
    }

    /// Which kind of generation produced (or is producing) the current output.
    /// Drives result-screen labels and what regenerate/primary action do.
    enum Mode: Equatable {
        case reply
        case summarize
    }

    /// The app this panel composes for: Mail, or one of the screenshot apps
    /// enabled in Settings. Fixed when the panel opens; the controller opens
    /// a fresh panel when the shortcut fires in another app.
    let target: ComposerTarget

    @Published var state: State = .loadingContext
    @Published var userThoughts: String = ""
    @Published var generatedReply: String = ""
    /// True while bytes are still arriving from the model. Used by the view
    /// to show a caret animation and to gate the "Copy message" action.
    @Published var isStreaming: Bool = false
    @Published private(set) var mode: Mode = .reply
    /// Mail compose-window snapshot. `nil` for chat targets.
    @Published private(set) var context: ComposerContext?
    /// Chat window snapshot. `nil` for the Mail target.
    @Published private(set) var chatContext: ChatContext?
    /// Mail: the AppleScript path came back empty for a reply (the API is
    /// lying — a reply always has recipients) and Accessibility isn't
    /// granted. Chat: Accessibility isn't granted, so the message can only
    /// be copied, not written into the chat box. Shown as a dismissible
    /// banner, never as a blocking wall.
    @Published var showsAccessibilityBanner = false
    /// Chat targets only: Screen Recording isn't granted, so the context has
    /// no screenshot and the model works from the user's notes alone.
    @Published var showsScreenRecordingBanner = false
    /// Shown under the result when the message could not be written into
    /// the chat box and was left on the clipboard instead.
    @Published var insertionNotice: String?

    var hasContext: Bool { context != nil || chatContext != nil }

    /// Screen frame (top-left origin) of the window the panel should sit
    /// next to.
    var anchorFrame: CGRect? { context?.composeWindowFrame ?? chatContext?.windowFrame }

    var canSummarize: Bool {
        if let chatContext { return chatContext.hasScreenshot }
        guard let thread = context?.thread else { return false }
        return !thread.messages.isEmpty
    }

    var loadingLabel: String {
        target.usesScreenshot ? "Capturing \(target.displayName) window…" : "Reading your compose window…"
    }

    var insertActionLabel: String {
        target.usesScreenshot ? "Insert into \(target.displayName)" : "Copy message"
    }

    private let settingsStore: SettingsStore
    private let onDismiss: () -> Void
    private var streamTask: Task<Void, Never>?
    /// Whether the in-flight request carries a screenshot, so a provider
    /// rejection can be explained as a model without vision support.
    private var lastRequestHadAttachments = false

    init(target: ComposerTarget = .mail, settingsStore: SettingsStore, onDismiss: @escaping () -> Void) {
        self.target = target
        self.settingsStore = settingsStore
        self.onDismiss = onDismiss
    }

    var canSend: Bool {
        guard hasContext else { return false }
        guard settingsStore.selectedModel != nil else { return false }
        return !userThoughts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isBusy: Bool {
        switch state {
        case .loadingContext, .generating: return true
        default: return isStreaming
        }
    }

    func activate() async {
        state = .loadingContext
        showsAccessibilityBanner = false
        showsScreenRecordingBanner = false
        insertionNotice = nil
        switch target.flow {
        case .mail:
            await activateMail()
        case .screenshot:
            await activateChat()
        }
    }

    private func activateMail() async {
        do {
            let context = try await MailBridge.fetchComposerContext()
            self.context = context
            // Sharp "AppleScript is actually broken" signal: a reply always
            // has recipients, so a non-empty thread with no recipients means
            // the API is lying. A blank new-message compose (thread == nil)
            // is legitimately empty and must not trigger the banner.
            showsAccessibilityBanner =
                !AXPermissionChecker.isGranted()
                && context.thread != nil
                && context.recipients.isEmpty
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func activateChat() async {
        do {
            let context = try await ChatBridge.fetchContext(for: target)
            chatContext = context
            showsScreenRecordingBanner = !ScreenCapturePermission.isGranted()
            showsAccessibilityBanner = !AXPermissionChecker.isGranted()
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Permissions

    /// Dismiss the accessibility banner without granting permission. The
    /// banner reappears on the next activation if the condition still holds.
    func dismissAccessibilityBanner() {
        showsAccessibilityBanner = false
    }

    /// Re-fetch context after the user grants a permission in System
    /// Settings and taps "Retry" in a banner.
    func retryAfterAXPermission() async {
        await activate()
    }

    /// Open System Settings → Privacy & Security → Accessibility.
    func openAccessibilitySettings() {
        AXPermissionChecker.openSettings()
    }

    /// Trigger the system's one-time AX permission prompt.
    func requestAXPermission() {
        _ = AXPermissionChecker.request()
    }

    func dismissScreenRecordingBanner() {
        showsScreenRecordingBanner = false
    }

    /// Trigger the system's one-time Screen Recording prompt.
    func requestScreenRecordingPermission() {
        _ = ScreenCapturePermission.request()
    }

    /// Open System Settings → Privacy & Security → Screen Recording.
    func openScreenRecordingSettings() {
        ScreenCapturePermission.openSettings()
    }

    /// macOS applies a Screen Recording grant only after a relaunch.
    func relaunchForScreenRecording() {
        ScreenCapturePermission.relaunch()
    }

    // MARK: - Generation

    func generate() async {
        guard hasContext else {
            state = .error(missingContextMessage)
            return
        }
        let trimmed = userThoughts.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        streamTask?.cancel()
        generatedReply = ""
        insertionNotice = nil
        mode = .reply
        state = .generating
        isStreaming = true

        let client: AIClient
        do {
            client = try settingsStore.makeAIClient()
        } catch {
            isStreaming = false
            state = .error(error.localizedDescription)
            return
        }

        let request = composeRequest(thoughts: trimmed)
        lastRequestHadAttachments = !request.attachments.isEmpty

        streamTask = Task { [weak self] in
            await self?.consumeStream(client.stream(
                systemPrompt: request.system,
                userMessage: request.user,
                attachments: request.attachments
            ))
        }
        await streamTask?.value
    }

    func summarize() async {
        guard hasContext else {
            state = .error(missingContextMessage)
            return
        }
        guard canSummarize else {
            state = .error(target.usesScreenshot ? "No screenshot to summarize yet." : "No thread to summarize yet.")
            return
        }

        streamTask?.cancel()
        generatedReply = ""
        insertionNotice = nil
        mode = .summarize
        state = .generating
        isStreaming = true

        let client: AIClient
        do {
            client = try settingsStore.makeAIClient()
        } catch {
            isStreaming = false
            state = .error(error.localizedDescription)
            return
        }

        let request = summarizeRequest()
        lastRequestHadAttachments = !request.attachments.isEmpty

        streamTask = Task { [weak self] in
            await self?.consumeStream(client.stream(
                systemPrompt: request.system,
                userMessage: request.user,
                attachments: request.attachments
            ))
        }
        await streamTask?.value
    }

    /// Re-runs whichever generation produced the current output. Lets the
    /// "Regenerate" chip in the result view stay mode-agnostic.
    func regenerate() async {
        switch mode {
        case .reply: await generate()
        case .summarize: await summarize()
        }
    }

    private struct Request {
        let system: String
        let user: String
        let attachments: [AIAttachment]
    }

    private func composeRequest(thoughts: String) -> Request {
        if let chatContext {
            let prompts = SystemPrompt.composeChat(
                context: chatContext,
                userThoughts: thoughts,
                customInstructions: settingsStore.customWritingInstructions
            )
            return Request(system: prompts.system, user: prompts.user, attachments: attachments(for: chatContext))
        }
        let prompts = SystemPrompt.compose(
            context: context!,
            userThoughts: thoughts,
            customInstructions: settingsStore.customWritingInstructions
        )
        return Request(system: prompts.system, user: prompts.user, attachments: [])
    }

    private func summarizeRequest() -> Request {
        if let chatContext {
            let prompts = SystemPrompt.summarizeChat(
                context: chatContext,
                customInstructions: settingsStore.customWritingInstructions
            )
            return Request(system: prompts.system, user: prompts.user, attachments: attachments(for: chatContext))
        }
        let prompts = SystemPrompt.summarize(
            context: context!,
            customInstructions: settingsStore.customWritingInstructions
        )
        return Request(system: prompts.system, user: prompts.user, attachments: [])
    }

    private func attachments(for chatContext: ChatContext) -> [AIAttachment] {
        chatContext.screenshot.map { [$0.attachment] } ?? []
    }

    private var missingContextMessage: String {
        target.usesScreenshot ? "No \(target.displayName) window detected." : "No compose window detected."
    }

    private func consumeStream(_ stream: AsyncThrowingStream<String, Error>) async {
        do {
            for try await chunk in stream {
                if Task.isCancelled { return }
                if state != .complete {
                    state = .complete
                }
                generatedReply += chunk
            }
            isStreaming = false
            if generatedReply.isEmpty {
                state = .error("No response from model.")
            }
        } catch is CancellationError {
            isStreaming = false
        } catch {
            isStreaming = false
            // Preserve any partial output — but only surface the error if we
            // got nothing back at all, otherwise the partial is still useful.
            if generatedReply.isEmpty {
                var message = error.localizedDescription
                message = Self.userFacingError(message)
                if lastRequestHadAttachments, Self.looksLikeImageRejection(message) {
                    message += " The selected model may not accept images. Pick a vision-capable model in Settings."
                }
                state = .error(
                    message,
                    recoveryURL: (error as? AIClientError)?.recoveryURL
                )
            }
        }
    }

    /// Providers answer a screenshot sent to a text-only model with a 400
    /// that mentions images or content types; surface that as a model hint.
    nonisolated static func looksLikeImageRejection(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("http 400")
            || lower.contains("image")
            || lower.contains("vision")
            || lower.contains("multimodal")
    }

    nonisolated static func userFacingError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("locator.fill") && lower.contains("timeout") {
            return "ChatGPT Web did not accept the prompt in time. Check that the relay browser is still connected, then try again."
        }
        guard message.count > 700 else { return message }
        return String(message.prefix(700)) + "…"
    }

    // MARK: - Output

    /// Put the result where it belongs: prepended into the Mail draft, or
    /// into the chat app's message box. Chat insertion that falls back to
    /// the clipboard keeps the panel open with a notice, so the user knows
    /// to paste.
    func insertIntoTarget() async {
        guard !generatedReply.isEmpty else { return }
        switch target.flow {
        case .mail:
            await MailBridge.insertReply(generatedReply)
            onDismiss()
        case .screenshot:
            let outcome = await ChatBridge.insertMessage(generatedReply, into: target)
            switch outcome {
            case .inserted, .pasted:
                onDismiss()
            case .copiedOnly:
                insertionNotice = "Couldn't reach the message box. The text is on your clipboard: click into \(target.displayName) and press ⌘V."
            }
        }
    }

    func copyToClipboard() {
        guard !generatedReply.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(generatedReply, forType: .string)
    }

    func backToEditing() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        insertionNotice = nil
        mode = .reply
        state = .ready
    }

    func retry() async {
        await activate()
    }

    func cancel() {
        streamTask?.cancel()
        onDismiss()
    }
}
