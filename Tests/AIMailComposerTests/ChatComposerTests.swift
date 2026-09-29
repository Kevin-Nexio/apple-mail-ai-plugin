import CoreGraphics
import Foundation
import XCTest
@testable import AIMailComposer

final class ChatComposerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(ChatStubServer.self)
        ChatStubServer.lastBody = nil
    }

    override func tearDown() {
        URLProtocol.unregisterClass(ChatStubServer.self)
        super.tearDown()
    }

    // MARK: - Screenshot app opt-in

    func testScreenshotAppsAreOffByDefault() {
        let list = ScreenshotAppList(data: Data())
        XCTAssertTrue(list.isEmpty)
        XCTAssertFalse(list.isEnabled(.discord))
        XCTAssertFalse(list.isEnabled(.whatsapp))
        XCTAssertNil(list.target(forBundleIdentifier: "com.hnc.Discord"),
                     "nothing enabled means the shortcut stays with the Mail flow")
    }

    func testEnablingAPresetResolvesAllOfItsBundleIdentifiers() {
        var list = ScreenshotAppList.empty
        list.setEnabled(true, preset: .discord)
        XCTAssertTrue(list.isEnabled(.discord))
        XCTAssertFalse(list.isEnabled(.whatsapp))
        XCTAssertEqual(list.target(forBundleIdentifier: "com.hnc.Discord"), .discord)
        XCTAssertEqual(list.target(forBundleIdentifier: "com.hnc.DiscordCanary"), .discord)
        XCTAssertNil(list.target(forBundleIdentifier: "net.whatsapp.WhatsApp"))
        XCTAssertTrue(list.customApps.isEmpty, "presets are not listed as custom rows")

        list.setEnabled(false, preset: .discord)
        XCTAssertTrue(list.isEmpty)
    }

    func testCustomAppsResolveToAGenericScreenshotTarget() throws {
        var list = ScreenshotAppList.empty
        list.add(ScreenshotApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack"))
        list.add(ScreenshotApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack again"))
        XCTAssertEqual(list.customApps.map(\.name), ["Slack"], "adding twice keeps one entry")

        let target = try XCTUnwrap(list.target(forBundleIdentifier: "com.tinyspeck.slackmacgap"))
        XCTAssertTrue(target.usesScreenshot)
        XCTAssertEqual(target.displayName, "Slack")
        XCTAssertNil(target.screenshotHint)
        XCTAssertNil(list.target(forBundleIdentifier: "com.apple.Safari"))

        list.remove(bundleIdentifier: "com.tinyspeck.slackmacgap")
        XCTAssertTrue(list.isEmpty)
    }

    func testAddingAPresetBundleIdentifierSwitchesThePresetOn() {
        var list = ScreenshotAppList.empty
        list.add(ScreenshotApp(bundleIdentifier: "com.hnc.DiscordPTB", name: "Discord PTB"))
        XCTAssertTrue(list.isEnabled(.discord))
        XCTAssertTrue(list.customApps.isEmpty)
        XCTAssertEqual(list.target(forBundleIdentifier: "com.hnc.DiscordPTB"), .discord)
    }

    func testMailAndThisAppCannotBeAddedAsScreenshotApps() {
        var list = ScreenshotAppList.empty
        list.add(ScreenshotApp(bundleIdentifier: "com.apple.mail", name: "Mail"))
        if let own = Bundle.main.bundleIdentifier {
            list.add(ScreenshotApp(bundleIdentifier: own, name: "Me"))
        }
        XCTAssertTrue(list.isEmpty)
    }

    func testScreenshotAppListRoundTripsThroughStoredData() {
        var list = ScreenshotAppList.empty
        list.setEnabled(true, preset: .whatsapp)
        list.add(ScreenshotApp(bundleIdentifier: "ru.keepcoder.Telegram", name: "Telegram"))

        let restored = ScreenshotAppList(data: list.encoded())
        XCTAssertEqual(restored, list)
        XCTAssertTrue(restored.isEnabled(.whatsapp))
        XCTAssertEqual(restored.customApps.map(\.bundleIdentifier), ["ru.keepcoder.Telegram"])

        XCTAssertEqual(ScreenshotAppList(data: Data("garbage".utf8)), .empty,
                       "unreadable stored data falls back to nothing enabled")
    }

    func testPresetsAreDiscordAndWhatsAppAndMailNeverUsesAScreenshot() {
        XCTAssertEqual(ComposerTarget.presets, [.discord, .whatsapp])
        XCTAssertFalse(ComposerTarget.mail.usesScreenshot)
        XCTAssertEqual(ComposerTarget.custom(ComposerTarget.discord.asScreenshotApp), .discord,
                       "a custom entry for a preset's bundle id keeps the preset's layout hint")
    }

    // MARK: - Request bodies

    /// PNG magic bytes; base64 "iVBORw==".
    private let screenshot = AIAttachment(data: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: "image/png")

    func testAttachmentEncodesAsDataURL() {
        XCTAssertEqual(screenshot.base64, "iVBORw==")
        XCTAssertEqual(screenshot.dataURL, "data:image/png;base64,iVBORw==")
    }

    func testOpenAICompatibleContentStaysAPlainStringWithoutImages() {
        XCTAssertEqual(OpenAICompatibleStream.userContent(text: "Hello", attachments: []) as? String, "Hello")
    }

    func testOpenAICompatibleContentPutsImagesBeforeTextAsDataURLs() throws {
        let parts = try XCTUnwrap(OpenAICompatibleStream.userContent(text: "Hello", attachments: [screenshot]) as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"] as? String, "image_url")
        XCTAssertEqual(parts[0]["image_url"] as? [String: String], ["url": "data:image/png;base64,iVBORw=="])
        XCTAssertEqual(parts[1] as? [String: String], ["type": "text", "text": "Hello"])
    }

    func testAnthropicContentUsesBase64ImageBlocks() throws {
        XCTAssertEqual(AnthropicClient.userContent(text: "Hello", attachments: []) as? String, "Hello")
        let blocks = try XCTUnwrap(AnthropicClient.userContent(text: "Hello", attachments: [screenshot]) as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "image")
        XCTAssertEqual(blocks[0]["source"] as? [String: String],
                       ["type": "base64", "media_type": "image/png", "data": "iVBORw=="])
        XCTAssertEqual(blocks[1] as? [String: String], ["type": "text", "text": "Hello"])
    }

    func testGeminiPartsUseInlineData() throws {
        XCTAssertEqual(GeminiClient.userParts(text: "Hello", attachments: []) as? [[String: String]], [["text": "Hello"]])
        let parts = GeminiClient.userParts(text: "Hello", attachments: [screenshot])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["inline_data"] as? [String: String], ["mime_type": "image/png", "data": "iVBORw=="])
        XCTAssertEqual(parts[1] as? [String: String], ["text": "Hello"])
    }

    func testOpenAICompatibleClientSendsScreenshotInRequestBody() async throws {
        let client = LocalAIClient(baseURL: "https://vision.chat-stub.invalid", model: "vision-model")
        let reply = try await client.complete(systemPrompt: "System", userMessage: "Hello", attachments: [screenshot])
        XCTAssertEqual(reply, "Sure thing")

        let body = try XCTUnwrap(ChatStubServer.lastBody)
        XCTAssertEqual(body["model"] as? String, "vision-model")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0] as? [String: String], ["role": "system", "content": "System"])
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "image_url")
        XCTAssertEqual(content[0]["image_url"] as? [String: String], ["url": screenshot.dataURL])
        XCTAssertEqual(content[1] as? [String: String], ["type": "text", "text": "Hello"])
    }

    func testTextOnlyRequestsKeepStringContent() async throws {
        let client = LocalAIClient(baseURL: "https://vision.chat-stub.invalid", model: "vision-model")
        _ = try await client.complete(systemPrompt: "System", userMessage: "Hello")
        let messages = try XCTUnwrap(ChatStubServer.lastBody?["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [
            ["role": "system", "content": "System"],
            ["role": "user", "content": "Hello"],
        ])
    }

    // MARK: - Prompts

    func testChatPromptDescribesAppWindowAndScreenshot() {
        let context = makeChatContext(target: .discord, withScreenshot: true)
        let prompts = SystemPrompt.composeChat(
            context: context,
            userThoughts: "say yes to thursday",
            customInstructions: "Keep it short"
        )
        XCTAssertTrue(prompts.system.contains("Discord"))
        XCTAssertTrue(prompts.system.contains("bottom-left"), "Discord-specific hint for spotting the user's own messages")
        XCTAssertTrue(prompts.system.hasSuffix("## Additional instructions from the user\nKeep it short"))
        XCTAssertFalse(prompts.system.contains("Best wishes"), "chat messages carry no email sign-off")
        XCTAssertTrue(prompts.user.contains("App: Discord"))
        XCTAssertTrue(prompts.user.contains("Window: @Lars - Discord"))
        XCTAssertTrue(prompts.user.contains("Screenshot: attached"))
        XCTAssertTrue(prompts.user.hasSuffix("## My thoughts for what to write\nsay yes to thursday"))
    }

    func testChatPromptWithoutScreenshotSaysSo() {
        let context = makeChatContext(target: .whatsapp, withScreenshot: false)
        let prompts = SystemPrompt.composeChat(context: context, userThoughts: "ask about dinner")
        XCTAssertTrue(prompts.system.contains("right-aligned"), "WhatsApp-specific hint for spotting the user's own messages")
        XCTAssertTrue(prompts.user.contains("Screenshot: not available"))
        XCTAssertFalse(prompts.system.contains("## Additional instructions"))
    }

    func testGenericAppPromptGetsGenericLayoutHint() {
        let slack = ComposerTarget.custom(ScreenshotApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack"))
        let context = ChatContext(target: slack, windowTitle: "general - Slack", screenshot: makeCapturedImage(), captureError: nil, windowFrame: nil)
        let prompts = SystemPrompt.composeChat(context: context, userThoughts: "ok")
        XCTAssertTrue(prompts.system.contains("The user is in Slack"))
        XCTAssertTrue(prompts.system.contains("right-aligned or marked with the user's name"))
        XCTAssertFalse(prompts.system.contains("bottom-left"))
        XCTAssertTrue(prompts.user.contains("Window: general - Slack"))
    }

    func testChatSummaryPromptTargetsTheScreenshot() {
        let context = makeChatContext(target: .discord, withScreenshot: true)
        let prompts = SystemPrompt.summarizeChat(context: context)
        XCTAssertTrue(prompts.system.contains("screenshot of a Discord window"))
        XCTAssertTrue(prompts.user.contains("App: Discord"))
        XCTAssertTrue(prompts.user.contains("Screenshot: attached"))
    }

    // MARK: - Screenshot sizing and encoding

    func testOutputSizeCapsTheLongestEdgeAndKeepsAspectRatio() {
        let size = WindowCapture.outputSize(for: CGSize(width: 1400, height: 900), scale: 2, maxDimension: 1568)
        XCTAssertEqual(size.width, 1568)
        XCTAssertEqual(size.height, 1008)
    }

    func testOutputSizeKeepsSmallWindowsAtNativeResolution() {
        let size = WindowCapture.outputSize(for: CGSize(width: 600, height: 400), scale: 2, maxDimension: 1568)
        XCTAssertEqual(size.width, 1200)
        XCTAssertEqual(size.height, 800)
    }

    func testEncodeProducesPNGWithMatchingMediaType() throws {
        let image = try XCTUnwrap(makeCGImage(width: 24, height: 16))
        let captured = try WindowCapture.encode(image)
        XCTAssertEqual(captured.mediaType, "image/png")
        XCTAssertEqual(Array(captured.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(captured.attachment.mediaType, "image/png")
        XCTAssertTrue(captured.attachment.dataURL.hasPrefix("data:image/png;base64,"))
    }

    func testChatContextFallsBackToAppNameWithoutWindowTitle() {
        let context = ChatContext(target: .whatsapp, windowTitle: "  ", screenshot: nil, captureError: nil, windowFrame: nil)
        XCTAssertEqual(context.displayTitle, "WhatsApp")
        XCTAssertFalse(context.hasScreenshot)
    }

    func testImageRejectionHeuristicFlagsVisionErrorsOnly() {
        XCTAssertTrue(ComposerViewModel.looksLikeImageRejection("API request failed: HTTP 400: model does not support image input"))
        XCTAssertTrue(ComposerViewModel.looksLikeImageRejection("Invalid content type: image_url"))
        XCTAssertFalse(ComposerViewModel.looksLikeImageRejection("API request failed: HTTP 401: Invalid API key"))
    }

    func testChatGPTWebLocatorTimeoutGetsAReadableMessage() {
        let raw = "API request failed: HTTP 500: Locator.fill: Timeout 30000ms exceeded while waiting for #prompt-textarea"
        XCTAssertEqual(
            ComposerViewModel.userFacingError(raw),
            "ChatGPT Web did not accept the prompt in time. Check that the relay browser is still connected, then try again."
        )
    }

    func testVeryLongProviderErrorsAreTruncated() {
        let raw = String(repeating: "x", count: 900)
        let result = ComposerViewModel.userFacingError(raw)
        XCTAssertEqual(result.count, 701)
        XCTAssertTrue(result.hasSuffix("…"))
    }

    // MARK: - Helpers

    private func makeChatContext(target: ComposerTarget, withScreenshot: Bool) -> ChatContext {
        ChatContext(
            target: target,
            windowTitle: "@Lars - Discord",
            screenshot: withScreenshot ? makeCapturedImage() : nil,
            captureError: nil,
            windowFrame: nil
        )
    }

    private func makeCapturedImage() -> CapturedImage {
        CapturedImage(cgImage: makeCGImage(width: 8, height: 8)!, data: Data([1, 2, 3]), mediaType: "image/png")
    }

    private func makeCGImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// Intercepts only the stub host; records the last request body and streams
/// a two-chunk reply. No real server is contacted.
private final class ChatStubServer: URLProtocol {
    static var lastBody: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "vision.chat-stub.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if let data = Self.body(of: request) {
            Self.lastBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"Sure \"}}]}\n\n"
            + "data: {\"choices\":[{\"delta\":{\"content\":\"thing\"}}]}\n\n"
            + "data: [DONE]\n\n"
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(sse.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
