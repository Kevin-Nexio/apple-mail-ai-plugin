import Foundation
import XCTest
@testable import AIMailComposer

final class ChatGPTWebProviderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ChatGPTWebRelayStub.backend = "browser"
        ChatGPTWebRelayStub.loggedIn = true
        ChatGPTWebRelayStub.healthy = true
        ChatGPTWebRelayStub.healthError = nil
        ChatGPTWebRelayStub.redirectChatToExternal = false
        ChatGPTWebRelayStub.requests = []
        ChatGPTWebRelayStub.lastJSONBody = nil
        ChatGPTWebURLSession.protocolClassesForTesting = [ChatGPTWebRelayStub.self]
        URLProtocol.registerClass(ChatGPTWebRelayStub.self)
    }

    override func tearDown() {
        ChatGPTWebURLSession.protocolClassesForTesting = nil
        URLProtocol.unregisterClass(ChatGPTWebRelayStub.self)
        super.tearDown()
    }

    func testHealthyBrowserRelayLoadsSeparateProviderModels() async {
        let inspection = await ChatGPTWebService.inspect(
            baseURL: "http://127.0.0.1:8791/",
            apiKey: "  local-secret  "
        )

        XCTAssertEqual(inspection.status, .connected)
        XCTAssertEqual(inspection.models.map(\.id), ["chatgpt-web-test"])
        XCTAssertEqual(inspection.models.first?.provider, .chatgptWeb)
        XCTAssertEqual(ChatGPTWebRelayStub.requests.count, 2)
        XCTAssertTrue(ChatGPTWebRelayStub.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer local-secret"
        })
    }

    func testBrowserRelayGenerationAlwaysStartsFreshConversation() async throws {
        let client = LocalAIClient(
            baseURL: "http://127.0.0.1:8791",
            model: "chatgpt-web-test",
            apiKey: "local-secret",
            provider: .chatgptWeb
        )

        let reply = try await client.complete(systemPrompt: "Write an email", userMessage: "Say hello")

        XCTAssertEqual(reply, "Hello from ChatGPT Web")
        XCTAssertEqual(client.provider, .chatgptWeb)
        XCTAssertEqual(ChatGPTWebRelayStub.lastJSONBody?["new_session"] as? Bool, true)
    }

    func testMockAndSignedOutBackendsDoNotExposeModels() async {
        ChatGPTWebRelayStub.backend = "mock"
        var inspection = await ChatGPTWebService.inspect(
            baseURL: "http://localhost:8791",
            apiKey: "local-secret"
        )
        XCTAssertEqual(inspection.status, .mockBackend)
        XCTAssertTrue(inspection.models.isEmpty)

        ChatGPTWebRelayStub.backend = "browser"
        ChatGPTWebRelayStub.loggedIn = false
        inspection = await ChatGPTWebService.inspect(
            baseURL: "http://[::1]:8791",
            apiKey: "local-secret"
        )
        XCTAssertEqual(inspection.status, .loginRequired)
        XCTAssertTrue(inspection.models.isEmpty)
    }

    func testUnhealthyBrowserDoesNotTurnConnectionLightGreen() async {
        ChatGPTWebRelayStub.healthy = false
        ChatGPTWebRelayStub.healthError = "Playwright is not installed"

        let inspection = await ChatGPTWebService.inspect(
            baseURL: "http://127.0.0.1:8791",
            apiKey: "local-secret"
        )

        guard case .unavailable(let message) = inspection.status else {
            return XCTFail("An unhealthy browser must be unavailable")
        }
        XCTAssertTrue(message.contains("Playwright is not installed"))
        XCTAssertTrue(inspection.models.isEmpty)
        XCTAssertEqual(ChatGPTWebRelayStub.requests.count, 1)
    }

    func testRelayURLMustStayOnLoopback() {
        XCTAssertNoThrow(try ChatGPTWebService.validatedBaseURL("http://localhost:8791"))
        XCTAssertNoThrow(try ChatGPTWebService.validatedBaseURL("https://127.0.0.1:8791/prefix"))
        XCTAssertThrowsError(try ChatGPTWebService.validatedBaseURL("https://relay.example.com"))
        XCTAssertThrowsError(try ChatGPTWebService.validatedBaseURL("http://user:pass@localhost:8791"))
        XCTAssertThrowsError(try ChatGPTWebService.validatedBaseURL("file:///tmp/relay"))
    }

    func testGenerationAlsoRejectsANonLoopbackRelay() async {
        let client = LocalAIClient(
            baseURL: "https://relay.example.com",
            model: "chatgpt-web-test",
            apiKey: "must-not-leak",
            provider: .chatgptWeb
        )

        do {
            _ = try await client.complete(systemPrompt: "Test", userMessage: "Hello")
            XCTFail("A ChatGPT Web token must never be sent outside loopback")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("loopback URL"))
        }
    }

    func testGenerationRefusesRedirectsOutsideLoopback() async {
        ChatGPTWebRelayStub.redirectChatToExternal = true
        let client = LocalAIClient(
            baseURL: "http://127.0.0.1:8791",
            model: "chatgpt-web-test",
            apiKey: "must-stay-local",
            provider: .chatgptWeb
        )

        do {
            _ = try await client.complete(systemPrompt: "Test", userMessage: "Hello")
            XCTFail("The redirect response must not be followed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("HTTP 307"))
        }
        XCTAssertFalse(ChatGPTWebRelayStub.requests.contains {
            $0.url?.host == "relay.example.com"
        })
    }

    func testScreenshotIsRejectedBeforeCallingUnsupportedBrowserRelay() async {
        let client = LocalAIClient(
            baseURL: "http://127.0.0.1:8791",
            model: "chatgpt-web-test",
            apiKey: "local-secret",
            provider: .chatgptWeb
        )

        do {
            _ = try await client.complete(
                systemPrompt: "Test",
                userMessage: "Read this screenshot",
                attachments: [AIAttachment(data: Data([0x01]), mediaType: "image/png")]
            )
            XCTFail("The relay must not receive unsupported screenshot data")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("does not support screenshots"))
        }
        XCTAssertTrue(ChatGPTWebRelayStub.requests.isEmpty)
    }
}

private final class ChatGPTWebRelayStub: URLProtocol {
    static var backend = "browser"
    static var loggedIn = true
    static var healthy = true
    static var healthError: String?
    static var redirectChatToExternal = false
    static var requests: [URLRequest] = []
    static var lastJSONBody: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool {
        let host = request.url?.host ?? ""
        return (host == "relay.example.com")
            || (["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
                && request.url?.port == 8791)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        if let data = Self.body(of: request) {
            Self.lastJSONBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        guard let url = request.url else { return }

        if url.host == "relay.example.com" {
            send(status: 500, body: "Redirect followed", contentType: "text/plain", url: url)
            return
        }

        let body: String
        let contentType: String
        switch url.path {
        case "/health":
            let errorField = Self.healthError.map { ",\"error\":\"\($0)\"" } ?? ""
            body = """
            {"ok":\(Self.healthy),"backend":"\(Self.backend)","title":"ChatGPT","logged_in_hint":\(Self.loggedIn)\(errorField)}
            """
            contentType = "application/json"
        case "/v1/models":
            body = #"{"data":[{"id":"chatgpt-web-test","name":"ChatGPT Web Test"}]}"#
            contentType = "application/json"
        case "/v1/chat/completions":
            if Self.redirectChatToExternal {
                send(
                    status: 307,
                    body: "Redirect",
                    contentType: "text/plain",
                    url: url,
                    headers: ["Location": "https://relay.example.com/v1/chat/completions"]
                )
                return
            }
            body = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello from ChatGPT Web\"}}]}\n\n"
                + "data: [DONE]\n\n"
            contentType = "text/event-stream"
        default:
            send(status: 404, body: "Not found", contentType: "text/plain", url: url)
            return
        }
        send(status: 200, body: body, contentType: contentType, url: url)
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

    private func send(
        status: Int,
        body: String,
        contentType: String,
        url: URL,
        headers: [String: String] = [:]
    ) {
        var responseHeaders = headers
        responseHeaders["Content-Type"] = contentType
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
