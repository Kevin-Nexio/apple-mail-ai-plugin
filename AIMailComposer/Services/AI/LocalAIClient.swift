import Foundation

/// Client for local or remote OpenAI-compatible servers, including LM Studio,
/// Ollama, and vLLM. The base URL is configurable and the API key is optional.
final class LocalAIClient: AIClient {
    let provider: AIProvider
    private let baseURL: String
    private let model: String
    private let apiKey: String?

    init(
        baseURL: String,
        model: String,
        apiKey: String? = nil,
        provider: AIProvider = .local
    ) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.model = model
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.provider = provider
    }

    func stream(systemPrompt: String, userMessage: String, attachments: [AIAttachment]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if self.provider == .chatgptWeb, !attachments.isEmpty {
                        throw AIClientError.requestFailed(
                            "ChatGPT Web does not support screenshots yet. Choose another provider for screenshot-based chats."
                        )
                    }
                    let requestBaseURL: String
                    if self.provider == .chatgptWeb {
                        requestBaseURL = try ChatGPTWebService.validatedBaseURL(self.baseURL).absoluteString
                    } else {
                        requestBaseURL = self.baseURL
                    }
                    guard let url = URL(string: "\(requestBaseURL)/v1/chat/completions") else {
                        throw AIClientError.requestFailed("Invalid Local AI base URL: \(self.baseURL)")
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    if let apiKey = self.apiKey, !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }

                    var body: [String: Any] = [
                        "model": self.model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": OpenAICompatibleStream.userContent(text: userMessage, attachments: attachments)],
                        ],
                    ]
                    // Browser-backed ChatGPT relays otherwise continue the
                    // previous web conversation. Each Mail generation must
                    // start clean so unrelated email content cannot leak
                    // between replies.
                    if self.provider == .chatgptWeb {
                        body["new_session"] = true
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let session = self.provider == .chatgptWeb
                        ? ChatGPTWebURLSession.shared
                        : URLSession.shared
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw AIClientError.requestFailed("No HTTP response")
                    }
                    guard http.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line + "\n"
                            if errorBody.count > 1024 {
                                errorBody += "...[truncated]"
                                break
                            }
                        }
                        throw AIClientError.requestFailed("HTTP \(http.statusCode): \(errorBody)")
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
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
}
