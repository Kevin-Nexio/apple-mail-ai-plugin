import Foundation

enum MailChatIntent: Equatable {
    case askAboutToday
    case prepareTodayDrafts
    case search(String)
    case unsupported
}

enum MailChatIntentParser {
    static func parse(_ input: String) -> MailChatIntent {
        let normalized = input
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let asksForDrafts = normalized.contains("brouillon")
            || normalized.contains("prepare des reponse")
            || normalized.contains("prepare les reponse")
            || normalized.contains("draft repl")
        if asksForDrafts {
            return .prepareTodayDrafts
        }

        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for verb in ["recherche", "cherche", "retrouve", "trouve", "search", "find"] {
            guard let range = original.range(of: verb, options: matchingOptions) else { continue }
            var query = String(original[range.upperBound...])
            for filler in [
                "les echanges avec", "les emails de", "les e-mails de", "les mails de",
                "les messages de", "un mail de", "un email de", "dans mes mails", "pour"
            ] {
                while let fillerRange = query.range(of: filler, options: matchingOptions) {
                    query.replaceSubrange(fillerRange, with: " ")
                }
            }
            query = query.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !query.isEmpty { return .search(query) }
            return .unsupported
        }

        let mailTerms = ["mail", "email", "aujourd", "resume", "synthese", "urgent", "priorit"]
        return mailTerms.contains(where: normalized.contains) ? .askAboutToday : .unsupported
    }
}
