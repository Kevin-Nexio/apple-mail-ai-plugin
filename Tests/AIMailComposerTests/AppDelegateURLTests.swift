import XCTest
@testable import AIMailComposer

final class AppDelegateURLTests: XCTestCase {
    @MainActor
    func testComposeURLRecognition() {
        XCTAssertTrue(AppDelegate.isComposeURL(URL(string: "aimailcomposer://compose")!))
        XCTAssertTrue(AppDelegate.isComposeURL(URL(string: "AIMAILCOMPOSER://COMPOSE")!))
        XCTAssertFalse(AppDelegate.isComposeURL(URL(string: "aimailcomposer://settings")!))
        XCTAssertFalse(AppDelegate.isComposeURL(URL(string: "https://compose")!))
    }
}
