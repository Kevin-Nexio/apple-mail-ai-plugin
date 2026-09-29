import AppKit
import MailKit

@MainActor
final class ComposeSessionViewController: MEExtensionViewController {
    private let subject: String
    private var requestedOpen = false

    init(subject: String) {
        self.subject = subject
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        subject = ""
        super.init(coder: coder)
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 116))

        let icon = NSImageView(image: NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "AI Reply"
        ) ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentTintColor = .controlAccentColor

        let title = NSTextField(labelWithString: "Opening AI Reply…")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let detailText = subject.isEmpty ? "Current draft" : subject
        let detail = NSTextField(wrappingLabelWithString: detailText)
        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2

        let reopen = NSButton(title: "Open assistant", target: self, action: #selector(openAssistant))
        reopen.translatesAutoresizingMaskIntoConstraints = false
        reopen.bezelStyle = .rounded
        reopen.controlSize = .small

        for subview in [icon, title, detail, reopen] {
            container.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),

            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),

            reopen.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            reopen.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
        ])

        view = container
        preferredContentSize = NSSize(width: 320, height: 116)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !requestedOpen else { return }
        requestedOpen = true
        openAssistant()
    }

    @objc private func openAssistant() {
        guard let url = URL(string: "aimailcomposer://compose") else { return }
        NSWorkspace.shared.open(url)
    }
}
