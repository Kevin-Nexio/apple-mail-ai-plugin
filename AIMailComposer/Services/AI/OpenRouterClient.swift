import Foundation

/// OpenRouter exposes the OpenAI chat-completions contract, so this client is
/// a thin variant of `OpenAIClient` with a different base URL and a pair of
/// optional attribution headers.
final class OpenRouterClient: AIClient {
    static let privacySettingsURL = URL(string: "https://openrouter.ai/settings/privacy")!

    let provider = AIProvider.openrouter
    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func stream(systemPrompt: String, userMessage: String, attachments: [AIAttachment]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue("https://github.com/aimail", forHTTPHeaderField: "HTTP-Referer")
                    request.setValue("Apple Mail AI Plugin", forHTTPHeaderField: "X-Title")

                    // OpenRouter applies the account's routing/privacy settings.
                    // No additional app-level guardrail restrictions are sent.
                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": OpenAICompatibleStream.userContent(text: userMessage, attachments: attachments)],
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw AIClientError.requestFailed("No HTTP response")
                    }
                    guard http.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in bytes.lines { errorBody += line + "\n" }
                        throw Self.responseError(statusCode: http.statusCode, body: errorBody)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        // OpenRouter sends occasional ": OPENROUTER PROCESSING"
                        // keepalive comments — parse() returns nil for those.
                        switch OpenAICompatibleStream.parse(line: line) {
                        case .delta(let text): continuation.yield(text)
                        case .done: continuation.finish(); return
                        case .none: continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func responseError(statusCode: Int, body: String) -> AIClientError {
        let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let metadata = error?["metadata"] as? [String: Any]
        let reasons = metadata?["ineligibility_reasons"] as? [[String: Any]] ?? []

        if statusCode == 404 {
            // Match the account policy reason, not the generic "guardrails"
            // wording, which can also describe unrelated routing restrictions.
            for reason in reasons {
                switch reason["reason"] as? String {
                case "paid-model-training-violation-by-account":
                    return .openRouterTrainingRestricted(modelType: "paid")
                case "free-model-training-violation-by-account":
                    return .openRouterTrainingRestricted(modelType: "free")
                default:
                    continue
                }
            }
        }

        let message = (error?["message"] as? String ?? body)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .requestFailed("OpenRouter HTTP \(statusCode)\(message.isEmpty ? "" : ": \(message)")")
    }
}
