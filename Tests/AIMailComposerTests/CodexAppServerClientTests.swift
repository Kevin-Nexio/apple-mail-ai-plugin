import Foundation
import XCTest
@testable import AIMailComposer

final class CodexAppServerClientTests: XCTestCase {
    func testInspectionAcceptsChatGPTAccountAndLoadsModels() async {
        let inspection = await CodexAppServerClient.inspect(configuration: configuration(script: """
        IFS= read -r _
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r _
        IFS= read -r _
        printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"mail@example.com","planType":"plus"}}}'
        IFS= read -r _
        printf '%s\n' '{"id":3,"result":{"data":[{"model":"gpt-test","displayName":"GPT Test","hidden":false},{"model":"hidden","hidden":true}]}}'
        """))

        XCTAssertEqual(
            inspection.status,
            .connected(email: "mail@example.com", plan: "plus")
        )
        XCTAssertEqual(inspection.models.map(\.id), [CodexAppServerClient.automaticModelID, "gpt-test"])
        XCTAssertTrue(inspection.models.allSatisfy { $0.provider == .codex })
    }

    func testGenerationStreamsOnlyFinalAnswer() async throws {
        let client = CodexAppServerClient(
            model: CodexAppServerClient.automaticModelID,
            configuration: configuration(script: """
            IFS= read -r _
            printf '%s\n' '{"id":1,"result":{}}'
            IFS= read -r _
            IFS= read -r _
            printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","planType":"plus"}}}'
            IFS= read -r thread_request
            case "$thread_request" in
              *'"shell_tool":false'*) ;;
              *) printf '%s\n' '{"id":3,"error":{"message":"shell tool was not disabled"}}'; exit 0 ;;
            esac
            printf '%s\n' '{"id":3,"result":{"thread":{"id":"thread-1"}}}'
            IFS= read -r _
            printf '%s\n' '{"id":4,"result":{"account":{"type":"chatgpt","planType":"plus"}}}'
            IFS= read -r _
            printf '%s\n' '{"id":5,"result":{"turn":{"id":"turn-1"}}}'
            printf '%s\n' '{"method":"item/started","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"analysis-1","type":"agentMessage","phase":"commentary"}}}'
            printf '%s\n' '{"method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"analysis-1","delta":"internal"}}'
            printf '%s\n' '{"method":"item/started","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"answer-1","type":"agentMessage","phase":"final_answer"}}}'
            printf '%s\n' '{"method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"answer-1","delta":"Bonjour "}}'
            printf '%s\n' '{"method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"answer-1","delta":"Kevin"}}'
            printf '%s\n' '{"method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"answer-1","type":"agentMessage","phase":"final_answer","text":"Bonjour Kevin"}}}'
            printf '%s\n' '{"method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}'
            """)
        )

        let result = try await client.complete(systemPrompt: "Reply in French", userMessage: "Hello")
        XCTAssertEqual(result, "Bonjour Kevin")
    }

    func testGenerationUsesLastCompletedMessageWhenLegacyServerOmitsPhase() async throws {
        let client = CodexAppServerClient(
            model: CodexAppServerClient.automaticModelID,
            configuration: configuration(script: """
            IFS= read -r _; printf '%s\n' '{"id":1,"result":{}}'
            IFS= read -r _; IFS= read -r _; printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","planType":"plus"}}}'
            IFS= read -r _; printf '%s\n' '{"id":3,"result":{"thread":{"id":"thread-1"}}}'
            IFS= read -r _; printf '%s\n' '{"id":4,"result":{"account":{"type":"chatgpt","planType":"plus"}}}'
            IFS= read -r _; printf '%s\n' '{"id":5,"result":{"turn":{"id":"turn-1"}}}'
            printf '%s\n' '{"method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"message-1","type":"agentMessage","text":"Legacy reply"}}}'
            printf '%s\n' '{"method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}'
            """)
        )

        let result = try await client.complete(systemPrompt: "Reply", userMessage: "Hello")
        XCTAssertEqual(result, "Legacy reply")
    }

    func testGenerationRejectsAPIKeyAuthentication() async {
        let client = CodexAppServerClient(
            model: CodexAppServerClient.automaticModelID,
            configuration: configuration(script: """
            IFS= read -r _
            printf '%s\n' '{"id":1,"result":{}}'
            IFS= read -r _
            IFS= read -r _
            printf '%s\n' '{"id":2,"result":{"account":{"type":"apiKey"}}}'
            """)
        )

        do {
            _ = try await client.complete(systemPrompt: "Reply", userMessage: "Hello")
            XCTFail("API key authentication must never be accepted as a ChatGPT subscription")
        } catch let error as CodexAppServerError {
            guard case .subscriptionAuthenticationRequired(let method) = error else {
                return XCTFail("Unexpected Codex error: \(error)")
            }
            XCTAssertEqual(method, "apiKey")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInspectionTimesOutWhenCodexStopsResponding() async {
        let inspection = await CodexAppServerClient.inspect(configuration: CodexProcessConfiguration(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "IFS= read -r _; while IFS= read -r _; do :; done"],
            inspectionTimeout: .milliseconds(50),
            turnTimeout: .seconds(1)
        ))

        guard case .unavailable(let message) = inspection.status else {
            return XCTFail("A stalled Codex process should become unavailable")
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains("timed out"))
    }

    private func configuration(script: String) -> CodexProcessConfiguration {
        CodexProcessConfiguration(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )
    }
}
