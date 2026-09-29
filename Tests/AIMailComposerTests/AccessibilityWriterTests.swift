import XCTest
@testable import AIMailComposer

final class AccessibilityWriterTests: XCTestCase {
    func testNormalizedTextPreservesTheFinalCharacter() {
        let reply = "Bonjour Dylan,\nMerci pour ton retour.\nKevin"

        XCTAssertEqual(
            AccessibilityWriter.normalizedText(reply),
            "Bonjour Dylan, Merci pour ton retour. Kevin"
        )
        XCTAssertFalse(
            AccessibilityWriter.normalizedText("Bonjour Dylan,\nMerci pour ton retour.\nKevi")
                .contains(AccessibilityWriter.normalizedText(reply))
        )
    }

    func testNormalizedTextAcceptsMailParagraphWhitespace() {
        let reply = "Bonjour Dylan,\n\nMerci d’avance.\nKevin"
        let mailText = "Bonjour Dylan,\u{00A0}\nMerci d’avance.\nKevin\nQuoted message"

        XCTAssertTrue(
            AccessibilityWriter.normalizedText(mailText)
                .contains(AccessibilityWriter.normalizedText(reply))
        )
    }
}
