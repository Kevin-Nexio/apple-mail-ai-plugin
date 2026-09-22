import AppKit

/// The app the composer panel is working against.
///
/// `.mail` is the original Apple Mail flow (AppleScript plus Accessibility).
/// Screenshot targets read the conversation from a screenshot of the app's
/// front window and write the result into its message box. Discord and
/// WhatsApp are presets that carry layout hints for the model; any other app
/// the user adds in Settings gets a generic target from `custom(_:)`.
struct ComposerTarget: Hashable {
    enum Flow: Hashable {
        case mail
        case screenshot
    }

    let flow: Flow
    /// Every bundle identifier this target answers to. Discord ships three
    /// release channels. WhatsApp's Mac Catalyst build replaced the older
    /// Electron app (bundle id `WhatsApp`), and both are still installed in
    /// the wild.
    let bundleIdentifiers: [String]
    let displayName: String
    /// SF Symbol used where the app's own icon isn't available.
    let symbolName: String
    /// Preset-specific guidance for telling the user's own messages apart in
    /// the screenshot. `nil` means the generic hint applies.
    let screenshotHint: String?

    /// Screenshot targets take their context from a window screenshot instead
    /// of a structured email thread.
    var usesScreenshot: Bool { flow == .screenshot }

    var primaryBundleIdentifier: String { bundleIdentifiers[0] }

    static let mail = ComposerTarget(
        flow: .mail,
        bundleIdentifiers: ["com.apple.mail"],
        displayName: "Apple Mail",
        symbolName: "envelope.fill",
        screenshotHint: nil
    )

    static let discord = ComposerTarget(
        flow: .screenshot,
        bundleIdentifiers: ["com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"],
        displayName: "Discord",
        symbolName: "bubble.left.and.bubble.right.fill",
        screenshotHint: "Every message shows its author's name. The user's own account name is in the panel at the bottom-left of the window; messages under that name are the user's."
    )

    static let whatsapp = ComposerTarget(
        flow: .screenshot,
        bundleIdentifiers: ["net.whatsapp.WhatsApp", "WhatsApp"],
        displayName: "WhatsApp",
        symbolName: "message.fill",
        screenshotHint: "The user's own messages are the right-aligned bubbles (usually green). Messages from the other person or group members are left-aligned."
    )

    /// Apps offered as one-click toggles in Settings.
    static let presets: [ComposerTarget] = [.discord, .whatsapp]

    static func preset(matching bundleIdentifier: String) -> ComposerTarget? {
        presets.first { $0.bundleIdentifiers.contains(bundleIdentifier) }
    }

    /// Target for an app the user added themselves. Resolves to the preset
    /// when the bundle id belongs to one, so its layout hint isn't lost.
    static func custom(_ app: ScreenshotApp) -> ComposerTarget {
        if let preset = preset(matching: app.bundleIdentifier) {
            return preset
        }
        return ComposerTarget(
            flow: .screenshot,
            bundleIdentifiers: [app.bundleIdentifier],
            displayName: app.name,
            symbolName: "app.fill",
            screenshotHint: nil
        )
    }

    /// The Settings entry written when this preset is switched on.
    var asScreenshotApp: ScreenshotApp {
        ScreenshotApp(bundleIdentifier: primaryBundleIdentifier, name: displayName)
    }

    /// The running instance of this app, if any.
    var runningApplication: NSRunningApplication? {
        for id in bundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                return app
            }
        }
        return nil
    }
}
