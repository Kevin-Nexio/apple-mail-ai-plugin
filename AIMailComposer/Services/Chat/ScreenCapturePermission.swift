import AppKit
import CoreGraphics

/// Screen Recording permission gate for the chat-app screenshot flow.
///
/// Reading another app's window contents needs the user to list this app
/// under System Settings → Privacy & Security → Screen & System Audio
/// Recording. Unlike Accessibility, macOS applies a fresh grant only after
/// the app relaunches, hence `relaunch()`.
enum ScreenCapturePermission {

    /// True if the app may capture other apps' windows.
    static func isGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Trigger the system's one-time Screen Recording prompt. Returns the
    /// current state; a grant made in the prompt usually needs a relaunch.
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Open System Settings → Privacy & Security → Screen Recording.
    static func openSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Start a fresh instance of the app and quit this one, so a newly
    /// granted permission takes effect. Mirrors `UpdateChecker.install()`.
    @MainActor
    static func relaunch() {
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        relaunch.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try relaunch.run()
        } catch {
            NSLog("Failed to relaunch: \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }
}
