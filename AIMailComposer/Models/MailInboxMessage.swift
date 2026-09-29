import Foundation

/// A deliberately small snapshot of a message read from Apple Mail.
/// The library id is only used locally to create a reply draft later.
struct MailInboxMessage: Identifiable, Equatable, Sendable {
    let id: Int
    let messageID: String
    let sender: String
    let subject: String
    let dateReceived: String
    let body: String
    let isRead: Bool
    let wasRepliedTo: Bool

    var displaySubject: String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(No subject)" : trimmed
    }

    var isLikelyAutomated: Bool {
        let value = sender.lowercased()
        return value.contains("no-reply")
            || value.contains("noreply")
            || value.contains("do-not-reply")
            || value.contains("donotreply")
    }

    func formatted(maxBodyLength: Int = 3_500) -> String {
        let clippedBody = String(body.prefix(maxBodyLength))
        return """
        From: \(sender)
        Subject: \(displaySubject)
        Received: \(dateReceived)
        Read: \(isRead ? "yes" : "no")
        Already replied: \(wasRepliedTo ? "yes" : "no")

        \(clippedBody)
        """
    }
}

struct PreparedMailDraft: Identifiable, Equatable, Sendable {
    let message: MailInboxMessage
    var body: String
    var isSelected: Bool = true

    var id: Int { message.id }
}
