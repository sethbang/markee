import Foundation
import Combine

extension Notification.Name {
    /// Posted whenever any persisted setting changes (including a custom-CSS
    /// file edit detected by the shared watcher). PreviewControllers observe
    /// this and re-push settings into their WebView.
    static let settingsDidChange = Notification.Name("MarkeeSettingsDidChange")
}

enum ThemeOverride: String, CaseIterable {
    case system, light, dark
}

/// Single source of truth for user preferences. Backed by `UserDefaults`;
/// every mutation persists and broadcasts `.settingsDidChange`. Owns the one
/// shared FileWatcher for the custom-CSS file (custom CSS is global, so one
/// watcher serves every window).
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore(defaults: .standard)

    let defaults: UserDefaults
    static let fontRange: ClosedRange<Double> = 10...28

    private var cssWatcher: FileWatcher?
    private var cssText: String = ""

    private enum Key {
        static let theme = "MarkeeThemeOverride"
        static let accent = "MarkeeAccentColor"
        static let baseFont = "MarkeeBaseFontSize"
        static let cssPath = "MarkeeCustomCSSPath"
        static let updateCheck = "MarkeeUpdateCheckEnabled"
        static let defaultFloat = "MarkeeDefaultFloatOnTop"
        // Un-prefixed to match the key EditorLauncher.preferredEditor() reads
        // from UserDefaults.standard — changing this key name breaks that contract.
        static let editor = "editor"
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        reloadCustomCSS()
    }

    // MARK: - Properties (computed: getters validate against defaults on each read)

    var themeOverride: ThemeOverride {
        get {
            guard let raw = defaults.string(forKey: Key.theme),
                  let value = ThemeOverride(rawValue: raw) else { return .system }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.theme)
            broadcast()
        }
    }

    var accentHex: String {
        get {
            let raw = defaults.string(forKey: Key.accent) ?? ""
            return Self.isHexColor(raw) ? raw : ""
        }
        set {
            let value = Self.isHexColor(newValue) ? newValue : ""
            defaults.set(value, forKey: Key.accent)
            broadcast()
        }
    }

    var baseFontSize: Double {
        get {
            let stored = defaults.object(forKey: Key.baseFont) as? Double ?? 14
            return stored.clamped(to: Self.fontRange)
        }
        set {
            let clamped = newValue.clamped(to: Self.fontRange)
            defaults.set(clamped, forKey: Key.baseFont)
            broadcast()
        }
    }

    var customCSSPath: String {
        get { defaults.string(forKey: Key.cssPath) ?? "" }
        set {
            defaults.set(newValue, forKey: Key.cssPath)
            reloadCustomCSS()   // installs new watcher; does NOT broadcast
            broadcast()         // exactly one notification for the path change
        }
    }

    var updateCheckEnabled: Bool {
        get { defaults.object(forKey: Key.updateCheck) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Key.updateCheck)
            broadcast()
        }
    }

    var defaultFloatOnTop: Bool {
        get { defaults.bool(forKey: Key.defaultFloat) }
        set {
            defaults.set(newValue, forKey: Key.defaultFloat)
            broadcast()
        }
    }

    var editorOverride: String {
        get {
            let raw = defaults.string(forKey: Key.editor) ?? ""
            return EditorLauncher.isSafeEditorName(raw) ? raw : ""
        }
        set {
            let value = EditorLauncher.isSafeEditorName(newValue) ? newValue : ""
            defaults.set(value, forKey: Key.editor)
            broadcast()
        }
    }

    // MARK: - Payload

    func payload() -> [String: Any] {
        [
            "theme": themeOverride.rawValue,
            "accent": accentHex,
            "baseFont": baseFontSize,
            "userCSS": cssText,
        ]
    }

    // MARK: - Helpers

    static func isHexColor(_ s: String) -> Bool {
        guard s.hasPrefix("#") else { return false }
        let hex = s.dropFirst()
        guard hex.count == 3 || hex.count == 6 else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }

    private func broadcast() {
        objectWillChange.send()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    // Does NOT broadcast; callers are responsible for calling broadcast() when needed.
    private func reloadCustomCSS() {
        cssWatcher?.cancel()
        cssWatcher = nil
        let path = defaults.string(forKey: Key.cssPath) ?? ""
        guard !path.isEmpty else { cssText = ""; return }
        let url = URL(fileURLWithPath: path)
        cssText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        cssWatcher = FileWatcher(url: url) { [weak self] in
            guard let self else { return }
            self.cssText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            self.broadcast()    // file-edit path: exactly one notification
        }
    }
}

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
