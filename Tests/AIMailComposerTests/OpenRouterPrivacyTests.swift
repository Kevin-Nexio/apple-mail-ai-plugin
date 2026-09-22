import Foundation
import XCTest
@testable import AIMailComposer

final class OpenRouterPrivacyTests: XCTestCase {
    func testAccountTrainingRestrictionHasActionableMessageAndRecoveryLink() {
        let error = OpenRouterClient.responseError(statusCode: 404, body: accountPrivacyError)

        XCTAssertTrue(error.localizedDescription.contains("account disallows paid model providers"))
        XCTAssertTrue(error.localizedDescription.contains("may train on your data"))
        XCTAssertTrue(error.localizedDescription.contains("Choose another model"))
        XCTAssertEqual(error.recoveryURL?.absoluteString, "https://openrouter.ai/settings/privacy")
        XCTAssertFalse(error.localizedDescription.contains("ineligibility_reasons"))
    }

    func testFreeModelRestrictionIdentifiesTheCorrectAccountSetting() {
        let body = accountPrivacyError.replacingOccurrences(of: "paid-model", with: "free-model")
        let error = OpenRouterClient.responseError(statusCode: 404, body: body)

        XCTAssertTrue(error.localizedDescription.contains("account disallows free model providers"))
        XCTAssertNotNil(error.recoveryURL)
    }

    func testOtherRoutingFailuresAreNotMisdiagnosedAsTrainingRestrictions() {
        let body = #"{"error":{"message":"No endpoints match your guardrail restrictions.","metadata":{"ineligibility_reasons":[{"reason":"provider-not-allowed"}]}}}"#
        let error = OpenRouterClient.responseError(statusCode: 404, body: body)

        XCTAssertEqual(error.localizedDescription,
                       "API request failed: OpenRouter HTTP 404: No endpoints match your guardrail restrictions.")
        XCTAssertNil(error.recoveryURL)
    }

    func testNonRoutingErrorsKeepTheirStatusAndReadableMessage() {
        let error = OpenRouterClient.responseError(
            statusCode: 401,
            body: #"{"error":{"code":401,"message":"Invalid API key"}}"#
        )
        XCTAssertEqual(error.localizedDescription, "API request failed: OpenRouter HTTP 401: Invalid API key")
        XCTAssertNil(error.recoveryURL)

        let malformed = OpenRouterClient.responseError(statusCode: 502, body: "Bad gateway\n")
        XCTAssertEqual(malformed.localizedDescription, "API request failed: OpenRouter HTTP 502: Bad gateway")
        XCTAssertNil(malformed.recoveryURL)

        let empty = OpenRouterClient.responseError(statusCode: 503, body: "")
        XCTAssertEqual(empty.localizedDescription, "API request failed: OpenRouter HTTP 503")
    }

    func testOpenRouterStreamsWithoutAppGuardrailRestrictions() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }

        // The stub validates the provider, unchanged model ID, and request body,
        // and rejects any added routing or privacy restrictions.
        let client = OpenRouterClient(apiKey: "test-key", model: "vendor/test-model", session: session)
        let reply = try await client.complete(systemPrompt: "Test", userMessage: "Hello")
        XCTAssertEqual(reply, "Hello there")
    }

    func testStreamingSurfacesAccountPrivacyRecovery() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }

        let client = OpenRouterClient(apiKey: "test-key", model: "vendor/blocked-model", session: session)
        do {
            _ = try await client.complete(systemPrompt: "Test", userMessage: "Hello")
            XCTFail("The account policy error should be surfaced")
        } catch let error as AIClientError {
            XCTAssertTrue(error.localizedDescription.contains("account disallows paid model providers"))
            XCTAssertEqual(error.recoveryURL?.absoluteString, "https://openrouter.ai/settings/privacy")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenRouterServerStub.self]
        return URLSession(configuration: configuration)
    }
}

// Captures the structure and reason reported in the user's HTTP 404 response.
private let accountPrivacyError = #"""
{
  "error": {
    "message": "0 endpoints out of 1 requested are available matching your guardrail restrictions and data policy.\nPaid model training violation (account settings): 1 endpoint excluded",
    "code": 404,
    "metadata": {
      "input_endpoint_count": 1,
      "ineligibility_reasons": [{
        "reason": "paid-model-training-violation-by-account",
        "endpoint_count": 1,
        "configure_url": "https://openrouter.ai/settings/privacy"
      }],
      "failed_routing_step": "Filter by Guardrails"
    }
  }
}
"""#

/// An isolated session intercepts every request, so tests never contact OpenRouter.
private final class OpenRouterServerStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let data = try requestBody()
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(Set(body.keys), Set(["model", "stream", "messages"]))
            XCTAssertEqual(body["stream"] as? Bool, true)
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages, [
                ["role": "system", "content": "Test"],
                ["role": "user", "content": "Hello"],
            ])

            let model = try XCTUnwrap(body["model"] as? String)
            let blocked = model == "vendor/blocked-model"
            if !blocked { XCTAssertEqual(model, "vendor/test-model") }
            let responseBody = blocked ? accountPrivacyError : """
            : OPENROUTER PROCESSING

            data: {"choices":[{"delta":{"content":"Hello "}}]}

            data: {"choices":[{"delta":{"content":"there"}}]}

            data: [DONE]


            """
            let response = try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(request.url), statusCode: blocked ? 404 : 200,
                httpVersion: nil,
                headerFields: ["Content-Type": blocked ? "application/json" : "text/event-stream"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func requestBody() throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    override func stopLoading() {}
}
