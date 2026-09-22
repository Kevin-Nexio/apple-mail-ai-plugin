import Foundation

/// An app the shortcut composes for from a screenshot of its window.
struct ScreenshotApp: Codable, Hashable, Identifiable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}

/// The user's opt-in list of screenshot apps.
///
/// Empty by default, so someone who only uses Mail is never asked for Screen
/// Recording. A plain value with JSON encoding, so the toggle and add/remove
/// rules are testable without touching UserDefaults. `SettingsStore` keeps
/// the encoded bytes in UserDefaults under the app's stable bundle
/// identifier, which is what preserves the list across updates.
struct ScreenshotAppList: Equatable {
    private(set) var apps: [ScreenshotApp]

    static let empty = ScreenshotAppList(apps: [])

    init(apps: [ScreenshotApp]) {
        self.apps = apps
    }

    /// Decode stored bytes. Anything unreadable means nothing is enabled.
    init(data: Data) {
        apps = (try? JSONDecoder().decode([ScreenshotApp].self, from: data)) ?? []
    }

    func encoded() -> Data {
        (try? JSONEncoder().encode(apps)) ?? Data()
    }

    var isEmpty: Bool { apps.isEmpty }

    func contains(bundleIdentifier: String) -> Bool {
        apps.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    /// A preset counts as enabled when any of its bundle ids is listed.
    func isEnabled(_ preset: ComposerTarget) -> Bool {
        preset.bundleIdentifiers.contains(where: contains(bundleIdentifier:))
    }

    mutating func setEnabled(_ enabled: Bool, preset: ComposerTarget) {
        apps.removeAll { preset.bundleIdentifiers.contains($0.bundleIdentifier) }
        if enabled {
            apps.append(preset.asScreenshotApp)
        }
    }

    /// Add an app the user picked. Mail and this app itself are refused:
    /// Mail has its own flow, and a screenshot of our own panel is useless.
    mutating func add(_ app: ScreenshotApp) {
        guard !ComposerTarget.mail.bundleIdentifiers.contains(app.bundleIdentifier),
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !contains(bundleIdentifier: app.bundleIdentifier)
        else { return }
        apps.append(app)
    }

    mutating func remove(bundleIdentifier: String) {
        apps.removeAll { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Entries that aren't one of the presets; shown as their own rows.
    var customApps: [ScreenshotApp] {
        apps.filter { ComposerTarget.preset(matching: $0.bundleIdentifier) == nil }
    }

    /// The target for the frontmost app, or `nil` when it isn't enabled and
    /// the shortcut should stay with the Mail flow.
    func target(forBundleIdentifier bundleIdentifier: String) -> ComposerTarget? {
        if let preset = ComposerTarget.preset(matching: bundleIdentifier) {
            return isEnabled(preset) ? preset : nil
        }
        guard let app = apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }
        return ComposerTarget.custom(app)
    }
}
