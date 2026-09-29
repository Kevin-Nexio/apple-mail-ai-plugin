import XCTest
@testable import AIMailComposer

final class ReplyOptionsTests: XCTestCase {
    private let context = ComposerContext(
        recipients: ["Dylan <dylan@example.com>"],
        subject: "Re: Travaux",
        currentDraft: "",
        thread: EmailThread(subject: "Travaux", messages: [
            EmailMessage(
                sender: "Dylan <dylan@example.com>",
                recipients: ["Kevin <kevin@example.com>"],
                subject: "Travaux",
                dateSent: nil,
                body: "Salut Kevin, tu peux me confirmer la date ?"
            ),
        ]),
        composeWindowFrame: nil
    )

    func testDefaultChoicesStayAutomatic() {
        let prompt = SystemPrompt.compose(
            context: context,
            userThoughts: "Réponds brièvement."
        )

        XCTAssertTrue(prompt.system.contains(ReplyLanguage.automatic.promptInstruction))
        XCTAssertTrue(prompt.system.contains(ReplyAddressStyle.automatic.promptInstruction))
    }

    func testFrenchVousChoiceProducesExplicitInstructions() {
        let prompt = SystemPrompt.compose(
            context: context,
            userThoughts: "Demande une recommandation.",
            addressStyle: .formal,
            replyLanguage: .french
        )

        XCTAssertTrue(prompt.system.contains("Write the entire reply in French"))
        XCTAssertTrue(prompt.system.contains("Use the formal, polite second person throughout: vous in French"))
        XCTAssertTrue(prompt.system.contains("Never switch to the informal form"))
    }

    func testExplicitChoicesComeAfterConflictingCustomInstructions() throws {
        let prompt = SystemPrompt.compose(
            context: context,
            userThoughts: "Réponds.",
            customInstructions: "Always use tu and answer in German.",
            addressStyle: .formal,
            replyLanguage: .french
        )

        let customRange = try XCTUnwrap(prompt.system.range(of: "Always use tu and answer in German."))
        let choicesRange = try XCTUnwrap(prompt.system.range(of: "## Explicit reply choices"))
        XCTAssertLessThan(customRange.lowerBound, choicesRange.lowerBound)
        XCTAssertTrue(prompt.system.contains("These choices have priority over the thread, draft, and additional writing instructions."))
    }

    func testEveryExplicitLanguageHasAFullReplyInstruction() {
        let cases: [(ReplyLanguage, String)] = [
            (.french, "entire reply in French"),
            (.english, "entire reply in English"),
            (.german, "entire reply in German"),
            (.italian, "entire reply in Italian"),
        ]

        for (language, expectedText) in cases {
            XCTAssertTrue(language.promptInstruction.contains(expectedText))
        }
    }

    func testCompactLabelsAreUnambiguous() {
        XCTAssertEqual(ReplyLanguage.french.shortLabel, "FR")
        XCTAssertEqual(ReplyAddressStyle.informal.shortLabel, "Tu")
        XCTAssertEqual(ReplyAddressStyle.formal.shortLabel, "Vous")
    }
}
