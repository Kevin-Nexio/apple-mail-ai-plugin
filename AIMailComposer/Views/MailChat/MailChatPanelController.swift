import AppKit
import SwiftUI

@MainActor
final class MailChatPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var viewModel: MailChatViewModel?
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init()
    }

    func showPanel() {
        if let panel {
            if panel.isMiniaturized { panel.deminiaturize(nil) }
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = MailChatViewModel(settingsStore: settingsStore)
        let rootView = MailChatView(viewModel: viewModel)
            .environmentObject(settingsStore)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Mail AI Chat"
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.contentMinSize = NSSize(width: 500, height: 560)
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: rootView)
        panel.delegate = self
        panel.center()

        self.panel = panel
        self.viewModel = viewModel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Task { [weak self] in
            if let frame = await MailBridge.fetchMessageViewerFrame() {
                self?.anchorPanel(toMailWindow: frame)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        viewModel?.cancel()
        panel = nil
        viewModel = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        viewModel?.isSavingDrafts != true
    }

    private func anchorPanel(toMailWindow mailFrame: CGRect) {
        guard let panel, let primary = NSScreen.screens.first else { return }
        let cocoaFrame = CGRect(
            x: mailFrame.minX,
            y: primary.frame.height - mailFrame.maxY,
            width: mailFrame.width,
            height: mailFrame.height
        )
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)) } ?? primary
        let visible = screen.visibleFrame
        let width = min(max(panel.frame.width, 500), visible.width - 24)
        let height = min(max(cocoaFrame.height, 620), visible.height - 24)
        var x = cocoaFrame.maxX + 10
        if x + width > visible.maxX {
            x = max(visible.minX + 12, cocoaFrame.minX - width - 10)
        }
        let y = max(visible.minY + 12, min(cocoaFrame.minY, visible.maxY - height - 12))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: true)
    }
}
