import Foundation

enum ChatGPTWebConnectionStatus: Equatable {
    case disabled
    case checking
    case connected
    case loginRequired
    case mockBackend
    case unavailable(String)
}

struct ChatGPTWebInspection {
    let status: ChatGPTWebConnectionStatus
    let models: [AIModel]
}

/// Health and safety checks for the optional community browser relay.
///
/// The relay owns the ChatGPT browser session. This app only talks to its
/// loopback HTTP API and never reads ChatGPT cookies or access tokens.
enum ChatGPTWebService {
    static func inspect(baseURL: String, apiKey: String?) async -> ChatGPTWebInspection {
        let base: URL
        do {
            base = try validatedBaseURL(baseURL)
        } catch {
            return ChatGPTWebInspection(status: .unavailable(error.localizedDescription), models: [])
        }

        do {
            let healthURL = base.appending(path: "health")
            var request = URLRequest(url: healthURL)
            addAuthorization(apiKey, to: &request)
            let (data, response) = try await ChatGPTWebURLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return ChatGPTWebInspection(status: .unavailable("No response from the local relay"), models: [])
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return ChatGPTWebInspection(status: .unavailable("The local relay rejected its access token"), models: [])
            }
            guard http.statusCode == 200 else {
                return ChatGPTWebInspection(status: .unavailable("Local relay returned HTTP \(http.statusCode)"), models: [])
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ChatGPTWebInspection(status: .unavailable("Could not read the local relay health response"), models: [])
            }

            let backend = (json["backend"] as? String)?.lowercased()
            let title = (json["title"] as? String)?.lowercased() ?? ""
            let loggedIn = json["logged_in_hint"] as? Bool
            let isHealthy = json["ok"] as? Bool

            if backend == "mock" {
                return ChatGPTWebInspection(status: .mockBackend, models: [])
            }
            if let backend, backend != "browser" {
                return ChatGPTWebInspection(
                    status: .unavailable("The relay is not using its browser backend"),
                    models: []
                )
            }
            if loggedIn == false || title.contains("just a moment") || title.contains("cloudflare") {
                return ChatGPTWebInspection(status: .loginRequired, models: [])
            }
            if isHealthy != true {
                let relayError = (json["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let message: String
                if let relayError, !relayError.isEmpty {
                    message = "The local relay is not ready: \(relayError)"
                } else if isHealthy == nil {
                    message = "The local relay did not report a healthy browser"
                } else {
                    message = "The local relay reports that its browser is not ready"
                }
                return ChatGPTWebInspection(
                    status: .unavailable(message),
                    models: []
                )
            }

            let models = try await ModelFetcher.fetchLocalAIModels(
                baseURL: base.absoluteString,
                apiKey: apiKey,
                provider: .chatgptWeb,
                urlSession: ChatGPTWebURLSession.shared
            )
            guard !models.isEmpty else {
                return ChatGPTWebInspection(status: .unavailable("The local relay returned no models"), models: [])
            }
            return ChatGPTWebInspection(status: .connected, models: models)
        } catch {
            return ChatGPTWebInspection(
                status: .unavailable("Local relay not reachable: \(error.localizedDescription)"),
                models: []
            )
        }
    }

    static func validatedBaseURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw AIClientError.requestFailed(
                "ChatGPT Web must use a loopback URL such as http://127.0.0.1:8791"
            )
        }

        while components.path.hasSuffix("/") && components.path != "/" {
            components.path.removeLast()
        }
        if components.path == "/" {
            components.path = ""
        }
        guard let url = components.url else {
            throw AIClientError.requestFailed("Invalid ChatGPT Web relay URL")
        }
        return url
    }

    private static func addAuthorization(_ apiKey: String?, to request: inout URLRequest) {
        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }
}

/// A relay bound to loopback must not be able to redirect email content or
/// its local bearer token to another host.
enum ChatGPTWebURLSession {
    private static let requestTimeout: TimeInterval = 360

    /// Test targets may inject a URLProtocol without changing production
    /// networking. Nil in the shipped app.
    static var protocolClassesForTesting: [AnyClass]?

    static var shared: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        if let protocolClassesForTesting {
            configuration.protocolClasses = protocolClassesForTesting
        }
        return URLSession(
            configuration: configuration,
            delegate: NoRedirectDelegate.shared,
            delegateQueue: nil
        )
    }

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        static let shared = NoRedirectDelegate()

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
