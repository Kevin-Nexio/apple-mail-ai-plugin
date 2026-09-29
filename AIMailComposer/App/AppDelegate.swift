import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// How often to silently re-check GitHub for a newer release while the
    /// app is running. The status menu surfaces an "Install Update…" entry
    /// when one is downloaded; we never interrupt the user with a modal.
    private static let updateCheckInterval: TimeInterval = 60 * 60 // 1 hour

    private var statusItem: NSStatusItem!
    private var hotkeyService: HotkeyService?
    private var panelController: ComposerPanelController?
    private var mailChatPanelController: MailChatPanelController?
    private var settingsWindow: NSWindow?
    private var statusMenu: NSMenu!
    private var composeMenuItem: NSMenuItem!
    private var updateMenuItem: NSMenuItem!
    private var updateSeparator: NSMenuItem!
    private var updateCheckTimer: Timer?
    private var updateStateCancellable: AnyCancellable?
    private var defaultPresentationWorkItem: DispatchWorkItem?
    private var pendingComposeURL = false
    private var didFinishLaunching = false
    let settingsStore = SettingsStore()
    let updateChecker = UpdateChecker()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI's Settings scene auto-creates an empty window on launch.
        // Close any auto-created windows before we present our own UI.
        NSApp.windows.forEach { $0.close() }

        setupMenuBar()
        setupHotkey()
        observeHotkeyChanges()
        observeUpdateState()
        scheduleRecurringUpdateChecks()
        settingsStore.startAutoRefresh()
        didFinishLaunching = true
        if pendingComposeURL {
            pendingComposeURL = false
            DispatchQueue.main.async { [weak self] in
                self?.presentComposerFromURL()
            }
        } else {
            scheduleDefaultPresentation()
        }
        Task { updateChecker.checkForUpdates() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: Self.isComposeURL) else { return }
        receiveComposeURL()
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value),
              Self.isComposeURL(url) else { return }
        receiveComposeURL()
    }

    private func receiveComposeURL() {
        guard didFinishLaunching else {
            pendingComposeURL = true
            return
        }
        presentComposerFromURL()
    }

    private func presentComposerFromURL() {
        defaultPresentationWorkItem?.cancel()
        settingsWindow?.orderOut(nil)
        openComposerPanel(target: .mail)
    }

    static func isComposeURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "aimailcomposer" && url.host?.lowercased() == "compose"
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    private func scheduleDefaultPresentation() {
        guard !pendingComposeURL else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.pendingComposeURL else { return }
            self.openSettings()
        }
        defaultPresentationWorkItem = workItem

        // Launch Services delivers custom URLs just after didFinishLaunching.
        // Give that event priority so an extension launch opens the composer
        // instead of briefly creating a settings window over it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let shortcut = currentShortcutDisplay()
        composeMenuItem = NSMenuItem(
            title: "Compose Reply (\(shortcut))",
            action: #selector(showComposerPanel),
            keyEquivalent: ""
        )

        // Reserved slot for "Install Update vX.Y.Z…". We toggle visibility
        // rather than insert/remove so the relative order stays predictable.
        updateMenuItem = NSMenuItem(title: "", action: #selector(installUpdate), keyEquivalent: "")
        updateMenuItem.target = self
        updateMenuItem.isHidden = true
        updateSeparator = NSMenuItem.separator()
        updateSeparator.isHidden = true

        statusMenu = NSMenu()
        statusMenu.addItem(updateMenuItem)
        statusMenu.addItem(updateSeparator)
        statusMenu.addItem(NSMenuItem(title: "Open Mail AI Chat…", action: #selector(showMailChat), keyEquivalent: ""))
        statusMenu.addItem(composeMenuItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit Apple Mail AI Plugin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "envelope.badge.fill", accessibilityDescription: "Apple Mail AI Plugin")
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.async { [weak self] in
                self?.statusItem.menu = nil
            }
        } else {
            showMailChat()
        }
    }

    // MARK: - Mail Chat

    @objc private func showMailChat() {
        if mailChatPanelController == nil {
            mailChatPanelController = MailChatPanelController(settingsStore: settingsStore)
        }
        mailChatPanelController?.showPanel()
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyService = HotkeyService { [weak self] in
            self?.showComposerPanel()
        }
        hotkeyService?.register(
            keyCode: UInt32(settingsStore.hotkeyKeyCode),
            modifiers: UInt32(settingsStore.hotkeyModifiers)
        )
    }

    private func observeHotkeyChanges() {
        NotificationCenter.default.addObserver(
            forName: SettingsStore.hotkeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshHotkey()
            }
        }
    }

    private func refreshHotkey() {
        hotkeyService?.register(
            keyCode: UInt32(settingsStore.hotkeyKeyCode),
            modifiers: UInt32(settingsStore.hotkeyModifiers)
        )
        composeMenuItem.title = "Compose Reply (\(currentShortcutDisplay()))"
    }

    private func currentShortcutDisplay() -> String {
        HotkeyService.shortcutDisplayString(
            keyCode: UInt32(settingsStore.hotkeyKeyCode),
            modifiers: UInt32(settingsStore.hotkeyModifiers)
        )
    }

    // MARK: - Updates

    private func scheduleRecurringUpdateChecks() {
        updateCheckTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.updateCheckInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateChecker.checkForUpdates()
            }
        }
        // Default mode pauses while a menu is tracking; common keeps it firing.
        RunLoop.main.add(timer, forMode: .common)
        updateCheckTimer = timer
    }

    private func observeUpdateState() {
        updateStateCancellable = updateChecker.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.refreshUpdateMenuItem(for: state)
            }
    }

    private func refreshUpdateMenuItem(for state: UpdateChecker.State) {
        let isReady: Bool
        if case .readyToInstall = state { isReady = true } else { isReady = false }

        if isReady {
            let version = updateChecker.latestVersion ?? "new version"
            updateMenuItem.title = "Install Update v\(version)…"
        }
        updateMenuItem.isHidden = !isReady
        updateSeparator.isHidden = !isReady
    }

    @objc private func installUpdate() {
        updateChecker.install()
    }

    // MARK: - Composer

    @objc func showComposerPanel() {
        // Resolve the target before the panel activates this app, otherwise
        // the frontmost app would be us.
        openComposerPanel(target: resolveTarget())
    }

    private func openComposerPanel(target: ComposerTarget) {
        if panelController == nil {
            panelController = ComposerPanelController(settingsStore: settingsStore)
        }
        panelController?.showPanel(target: target)
    }

    /// Pick the app to compose for from whatever is frontmost when the
    /// shortcut fires. Apps the user enabled under Settings → General get
    /// the screenshot flow. Mail and every other app get the Mail flow,
    /// which is what the shortcut always did. When we are frontmost
    /// ourselves (the panel is already open) keep its target.
    private func resolveTarget() -> ComposerTarget {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return panelController?.currentTarget ?? .mail
        }
        guard let bundleIdentifier = frontmost?.bundleIdentifier else { return .mail }
        return settingsStore.screenshotApps.target(forBundleIdentifier: bundleIdentifier) ?? .mail
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if let window = settingsWindow {
            // makeKeyAndOrderFront alone won't restore a miniaturized window,
            // and with LSUIElement there is no Dock icon to restore it from.
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(settingsStore)
            .environmentObject(updateChecker)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Apple Mail AI Plugin"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.contentMinSize = NSSize(width: 540, height: 560)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }
}
