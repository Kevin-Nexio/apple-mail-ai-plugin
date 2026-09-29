import MailKit

@MainActor
final class ComposeSessionHandler: NSObject, MEComposeSessionHandler {
    func mailComposeSessionDidBegin(_ session: MEComposeSession) {}

    func mailComposeSessionDidEnd(_ session: MEComposeSession) {}

    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        ComposeSessionViewController(subject: session.mailMessage.subject)
    }
}
