import Foundation

/// Reads the browser relay token from its local, user-only configuration.
///
/// This token only authenticates requests to a loopback-only service on this
/// Mac. Real provider API keys continue to use macOS Keychain.
struct LoopbackRelayTokenStore {
    static let environmentKey = "CHATGPT_WEB_API_KEYS"

    let fileURL: URL

    init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/chatgpt-web-provider/env")) {
        self.fileURL = fileURL
    }

    func get() -> String? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        return value(in: contents)
    }

    func set(_ token: String) throws {
        var lines = ((try? String(contentsOf: fileURL, encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let prefix = Self.environmentKey + "="
        lines.removeAll { $0.hasPrefix(prefix) }

        if !token.isEmpty {
            lines.insert(prefix + token, at: 0)
        }
        while lines.last == "" {
            lines.removeLast()
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func delete() {
        try? set("")
    }

    private func value(in contents: String) -> String? {
        let prefix = Self.environmentKey + "="
        guard let line = contents.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let token = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
