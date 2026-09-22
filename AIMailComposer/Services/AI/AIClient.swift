import Foundation

/// An image sent alongside the user message, such as a screenshot of a chat
/// window.
struct AIAttachment: Equatable {
    let data: Data
    /// MIME type, e.g. `image/png`.
    let mediaType: String

    var base64: String { data.base64EncodedString() }

    /// RFC 2397 data URL, the form OpenAI-compatible endpoints accept.
    var dataURL: String { "data:\(mediaType);base64,\(base64)" }
}

protocol AIClient {
    var provider: AIProvider { get }

    /// Streams the assistant's reply as incremental text deltas. Each yielded
    /// chunk is new text to append to whatever has already been received.
    /// `attachments` are images that accompany the user message; text-only
    /// requests pass an empty array.
    func stream(systemPrompt: String, userMessage: String, attachments: [AIAttachment]) -> AsyncThrowingStream<String, Error>
}

extension AIClient {
    func stream(systemPrompt: String, userMessage: String) -> AsyncThrowingStream<String, Error> {
        stream(systemPrompt: systemPrompt, userMessage: userMessage, attachments: [])
    }

    /// Fallback for callers that want the full reply as one string.
    func complete(systemPrompt: String, userMessage: String, attachments: [AIAttachment] = []) async throws -> String {
        var result = ""
        for try await chunk in stream(systemPrompt: systemPrompt, userMessage: userMessage, attachments: attachments) {
            result += chunk
        }
        return result
    }
}

enum AIClientError: LocalizedError {
    case missingAPIKey(AIProvider)
    case requestFailed(String)
    case invalidResponse(String)
    case openRouterTrainingRestricted(modelType: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "No API key configured for \(provider.displayName). Add one in Settings."
        case .requestFailed(let msg):
            return "API request failed: \(msg)"
        case .invalidResponse(let msg):
            return "Invalid API response: \(msg)"
        case .openRouterTrainingRestricted(let modelType):
            return "OpenRouter blocked this model because your account disallows \(modelType) model providers that may train on your data. Choose another model, or allow those providers in OpenRouter privacy settings."
        }
    }

    var recoveryURL: URL? {
        switch self {
        case .openRouterTrainingRestricted:
            return OpenRouterClient.privacySettingsURL
        default:
            return nil
        }
    }
}

/// Shared parser for OpenAI-compatible SSE chunks ("data: {...}" lines, with
/// `[DONE]` sentinel). Emits deltas extracted from `choices[0].delta.content`.
enum OpenAICompatibleStream {
    static func parse(line: String) -> OpenAIStreamEvent? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst("data: ".count))
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let choices = json["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any],
           let content = delta["content"] as? String,
           !content.isEmpty {
            return .delta(content)
        }
        return nil
    }

    /// The `content` of a chat-completions user message. Text-only requests
    /// keep the plain-string form, so servers without vision support and the
    /// existing request shape are unaffected. Images switch to the
    /// content-part array with the images ahead of the text.
    static func userContent(text: String, attachments: [AIAttachment]) -> Any {
        guard !attachments.isEmpty else { return text }
        var parts: [[String: Any]] = attachments.map { attachment in
            ["type": "image_url", "image_url": ["url": attachment.dataURL]]
        }
        parts.append(["type": "text", "text": text])
        return parts
    }
}

enum OpenAIStreamEvent {
    case delta(String)
    case done
}
