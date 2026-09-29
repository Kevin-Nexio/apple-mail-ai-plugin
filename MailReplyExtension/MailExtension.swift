import MailKit

@MainActor
final class MailExtension: NSObject, MEExtension {
    func handler(for session: MEComposeSession) -> MEComposeSessionHandler {
        ComposeSessionHandler()
    }
}
