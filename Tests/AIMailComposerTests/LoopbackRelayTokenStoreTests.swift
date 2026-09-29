import XCTest
@testable import AIMailComposer

final class LoopbackRelayTokenStoreTests: XCTestCase {
    func testReadsUpdatesAndDeletesTokenWithoutChangingOtherSettings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopbackRelayTokenStoreTests-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("env")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "CHATGPT_WEB_BACKEND=browser\nCHATGPT_WEB_API_KEYS=old-token\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        let store = LoopbackRelayTokenStore(fileURL: fileURL)
        XCTAssertEqual(store.get(), "old-token")

        try store.set("new-token")
        XCTAssertEqual(store.get(), "new-token")
        let updated = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("CHATGPT_WEB_BACKEND=browser"))
        XCTAssertTrue(updated.contains("CHATGPT_WEB_API_KEYS=new-token"))
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))

        store.delete()
        XCTAssertNil(store.get())
        let deleted = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(deleted.contains("CHATGPT_WEB_BACKEND=browser"))
        XCTAssertFalse(deleted.contains("CHATGPT_WEB_API_KEYS="))
    }

    func testMissingFileReturnsNoToken() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)/env")
        XCTAssertNil(LoopbackRelayTokenStore(fileURL: fileURL).get())
    }
}
