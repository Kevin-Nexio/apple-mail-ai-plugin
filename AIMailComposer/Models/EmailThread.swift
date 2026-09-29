import Foundation

struct EmailThread {
    let subject: String
    let messages: [EmailMessage]

    /// Format recent messages for an AI prompt without recursively repeating
    /// the quoted history embedded in every Mail message body.
    func formatted(maxMessages: Int = 12, maxTotalCharacters: Int = 24_000) -> String {
        guard maxMessages > 0, maxTotalCharacters > 0 else { return "" }

        var blocksNewestFirst: [String] = []
        var remaining = maxTotalCharacters

        for message in messages.suffix(maxMessages).reversed() {
            let separatorCost = blocksNewestFirst.isEmpty ? 0 : 5
            guard remaining > separatorCost else { break }
            remaining -= separatorCost
            let body = Self.authoredBody(from: message.body)
            let block = """
            From: \(message.sender)
            Date: \(message.formattedDate)

            \(body)
            """
            let clipped = String(block.prefix(remaining))
            guard !clipped.isEmpty else { break }
            blocksNewestFirst.append(clipped)
            remaining -= clipped.count
            if remaining == 0 { break }
        }

        return blocksNewestFirst.reversed().joined(separator: "\n---\n")
    }

    private static func authoredBody(from body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        let boundary = lines.indices.first { index in
            guard index > 0 else { return false }
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            if lower.hasPrefix("le ") && lower.contains("a écrit") { return true }
            if lower.hasPrefix("on ") && lower.hasSuffix("wrote:") { return true }
            if lower.hasPrefix("am ") && lower.contains("schrieb") { return true }
            if lower.hasPrefix("el ") && lower.hasSuffix("escribió:") { return true }
            if lower == "begin forwarded message:" || lower == "début du message réexpédié :" { return true }
            if lower.hasPrefix("-----original message-----") { return true }
            if index > 2 && ["from:", "de :", "de:", "von:"].contains(where: lower.hasPrefix) { return true }
            return false
        }

        let authoredLines = boundary.map { Array(lines[..<$0]) } ?? lines
        let authored = authoredLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return authored.isEmpty ? String(body.prefix(4_000)) : String(authored.prefix(4_000))
    }
}
