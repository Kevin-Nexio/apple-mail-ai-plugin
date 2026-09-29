import XCTest
@testable import AIMailComposer

final class AccessibilityReaderTests: XCTestCase {
    func testDetectsLocalizedQuotedThreadBoundaries() {
        XCTAssertTrue(AccessibilityReader.isQuotedThreadBoundary("Le 4 mars 2026 à 14:42, Dylan a écrit :"))
        XCTAssertTrue(AccessibilityReader.isQuotedThreadBoundary("On Sep 29, 2026, Dylan wrote:"))
        XCTAssertTrue(AccessibilityReader.isQuotedThreadBoundary("Am 29.09.2026 schrieb Dylan:"))
        XCTAssertTrue(AccessibilityReader.isQuotedThreadBoundary("El 29 sept 2026, Dylan escribió:"))
    }

    func testDoesNotTreatDraftTextAsQuotedHistory() {
        XCTAssertFalse(AccessibilityReader.isQuotedThreadBoundary("Bonjour Dylan,"))
        XCTAssertFalse(AccessibilityReader.isQuotedThreadBoundary("Peux-tu me recommander un peintre plâtrier ?"))
    }
}
