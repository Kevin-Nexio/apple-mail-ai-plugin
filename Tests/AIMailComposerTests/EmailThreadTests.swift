import XCTest
@testable import AIMailComposer

final class EmailThreadTests: XCTestCase {
    func testFormattedThreadRemovesNestedFrenchQuote() {
        let thread = EmailThread(subject: "Re: Travaux", messages: [
            EmailMessage(
                sender: "Dylan",
                recipients: ["Kevin"],
                subject: "Re: Travaux",
                dateSent: nil,
                body: "Bonjour,\nMerci du retour.\n\nLe 3 mars 2026 à 21:52, Kevin a écrit :\nAncien message"
            ),
        ])

        let formatted = thread.formatted()

        XCTAssertTrue(formatted.contains("Merci du retour."))
        XCTAssertFalse(formatted.contains("Ancien message"))
    }

    func testFormattedThreadKeepsNewestMessagesWithinTotalBudget() {
        let messages = (1...20).map { index in
            EmailMessage(
                sender: "Sender \(index)",
                recipients: [],
                subject: "Subject",
                dateSent: Date(timeIntervalSince1970: TimeInterval(index)),
                body: String(repeating: "x", count: 1_000)
            )
        }
        let thread = EmailThread(subject: "Subject", messages: messages)

        let formatted = thread.formatted(maxMessages: 5, maxTotalCharacters: 2_500)

        XCTAssertLessThanOrEqual(formatted.count, 2_500)
        XCTAssertTrue(formatted.contains("Sender 20"))
        XCTAssertFalse(formatted.contains("Sender 1\n"))
    }
}
