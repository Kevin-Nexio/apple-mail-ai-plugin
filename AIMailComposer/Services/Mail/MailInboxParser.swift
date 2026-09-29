import Foundation

enum MailInboxParser {
    static let fieldSeparator = "\u{001F}"
    static let recordSeparator = "\u{001E}"

    /// Parses the compact delimiter format emitted by MailScripts. The
    /// AppleScript sanitizes both separators out of message data first, so
    /// arbitrary newlines in a body are safe here.
    static func parse(_ raw: String) -> [MailInboxMessage] {
        raw.components(separatedBy: recordSeparator).compactMap { record in
            guard !record.isEmpty else { return nil }
            let fields = record.components(separatedBy: fieldSeparator)
            guard fields.count == 8,
                  let id = Int(fields[0]),
                  let isRead = parseBoolean(fields[6]),
                  let wasRepliedTo = parseBoolean(fields[7])
            else { return nil }

            return MailInboxMessage(
                id: id,
                messageID: fields[1],
                sender: fields[2],
                subject: fields[3],
                dateReceived: fields[4],
                body: fields[5],
                isRead: isRead,
                wasRepliedTo: wasRepliedTo
            )
        }
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }
}
