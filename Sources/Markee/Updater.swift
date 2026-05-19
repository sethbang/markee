import Foundation

/// A dotted numeric version (e.g. "0.4.0"), tolerant of a leading "v" and of a
/// pre-release/build suffix. Used only to compare the running app against the
/// latest GitHub release.
struct AppVersion: Comparable, Sendable {
    let components: [Int]

    init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        // Drop any pre-release suffix ("1.0.0-rc1" -> "1.0.0"). Harmless:
        // the updater only reads /releases/latest, which excludes pre-releases.
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var nums: [Int] = []
        for p in parts {
            guard let n = Int(p), n >= 0 else { return nil }
            nums.append(n)
        }
        self.components = nums
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return false }
        }
        return true
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}

/// The subset of a GitHub Release that Markee uses, decoded from the
/// `/releases/latest` API response.
struct GitHubRelease: Sendable {
    let version: AppVersion
    let tagName: String
    let pageURL: URL
    let zipURL: URL
    let notes: String

    /// Parse the GitHub `/releases/latest` JSON. Returns nil if the payload is
    /// missing required fields or has no `Markee.app.zip` asset.
    init?(json data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let version = AppVersion(tag),
              let htmlURLString = obj["html_url"] as? String,
              let pageURL = URL(string: htmlURLString),
              let assets = obj["assets"] as? [[String: Any]]
        else { return nil }

        guard let zip = assets.first(where: { ($0["name"] as? String) == "Markee.app.zip" }),
              let zipURLString = zip["browser_download_url"] as? String,
              let zipURL = URL(string: zipURLString)
        else { return nil }

        self.version = version
        self.tagName = tag
        self.pageURL = pageURL
        self.zipURL = zipURL
        self.notes = (obj["body"] as? String) ?? ""
    }
}

enum UpdaterError: LocalizedError {
    case badResponse
    case unparseable
    case downloadFailed
    case subprocessFailed
    case invalidBundle

    var errorDescription: String? {
        switch self {
        case .badResponse:      return "GitHub returned an unexpected response."
        case .unparseable:      return "Couldn't read the release information."
        case .downloadFailed:   return "The update download failed."
        case .subprocessFailed: return "Unpacking the update failed."
        case .invalidBundle:    return "The downloaded update looked invalid."
        }
    }
}

import AppKit

@MainActor
final class Updater {
    static let shared = Updater()

    private let repo = "sethbang/markee"
    private var isRunning = false

    private static let lastCheckKey = "MarkeeLastUpdateCheck"
    private static let skippedVersionKey = "MarkeeSkippedVersion"

    private init() {}

    static var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var currentVersion: AppVersion {
        AppVersion(Self.currentVersionString) ?? AppVersion("0.0.0")!
    }

    /// Once-a-day silent launch check. Throttled by a UserDefaults timestamp.
    func checkOnLaunch() {
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           now.timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        UserDefaults.standard.set(now, forKey: Self.lastCheckKey)
        Task { await check(userInitiated: false) }
    }

    /// "Check for Updates…" menu action. Always reports its result.
    func checkForUpdatesMenuAction() {
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let release: GitHubRelease
        do {
            release = try await Self.fetchLatestRelease(repo: repo)
        } catch {
            if userInitiated {
                presentError(error.localizedDescription)
            }
            return
        }

        guard release.version > currentVersion else {
            if userInitiated { presentUpToDate() }
            return
        }

        if !userInitiated,
           UserDefaults.standard.string(forKey: Self.skippedVersionKey) == release.tagName {
            return
        }

        presentUpdateAvailable(release)
    }

    nonisolated static func fetchLatestRelease(repo: String) async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdaterError.badResponse
        }
        guard let release = GitHubRelease(json: data) else {
            throw UpdaterError.unparseable
        }
        return release
    }

    // MARK: - UI

    func presentUpdateAvailable(_ release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "A new version of Markee is available"
        var info = "Markee \(release.tagName) is available — you have \(Self.currentVersionString)."
        if !release.notes.isEmpty {
            let notes = release.notes.count > 500
                ? String(release.notes.prefix(500)) + "…"
                : release.notes
            info += "\n\n" + notes
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await installUpdate(release) }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.tagName, forKey: Self.skippedVersionKey)
        default:
            break  // Remind Me Later — nothing persisted; the next check re-offers.
        }
    }

    func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Markee \(Self.currentVersionString) is the latest version."
        alert.runModal()
    }

    func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = message
        alert.runModal()
    }

    /// Used when self-replace can't proceed (read-only location, bad download).
    /// Sends the user to the release page to update by hand.
    func presentManualFallback(_ release: GitHubRelease, reason: String) {
        let alert = NSAlert()
        alert.messageText = "Update Markee manually"
        alert.informativeText = "\(reason)\n\nOpen the download page to get \(release.tagName) in your browser."
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
        }
    }

    // MARK: - Install (implemented in Task 9)

    func installUpdate(_ release: GitHubRelease) async {}
}
