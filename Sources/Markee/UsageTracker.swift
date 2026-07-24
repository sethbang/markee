import Combine
import CryptoKit
import Foundation

/// Local-only usage counters for the support drawer. File paths are stored as
/// salted SHA-256 prefixes, never in the clear; nothing here is ever
/// transmitted. Defaults + clock are injected for tests.
@MainActor
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    @Published private(set) var stats: UsageStats = .zero

    private let defaults: UserDefaults
    private let now: () -> Date

    // Beyond this many distinct docs we stop storing hashes and just bump an
    // overflow counter; re-opens of a post-cap doc may over-count. Fine for a
    // display-only vanity stat, and keeps the defaults array bounded.
    static let maxStoredHashes = 5000

    private enum Keys {
        static let documentHashes = "usage.documentHashes"
        static let documentOverflow = "usage.documentOverflow"
        static let rerenders = "usage.rerenders"
        static let boxesChecked = "usage.boxesChecked"
        static let activeDays = "usage.activeDays"
        static let lastActiveDay = "usage.lastActiveDay"
        static let salt = "usage.salt"
    }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.stats = snapshot()
    }

    func snapshot() -> UsageStats {
        let stored = (defaults.stringArray(forKey: Keys.documentHashes) ?? []).count
        return UsageStats(
            documentsPreviewed: stored + defaults.integer(forKey: Keys.documentOverflow),
            rerendersWatched: defaults.integer(forKey: Keys.rerenders),
            activeDays: defaults.integer(forKey: Keys.activeDays),
            boxesChecked: defaults.integer(forKey: Keys.boxesChecked))
    }

    func recordDocumentOpened(_ url: URL) {
        let h = hash(url.standardizedFileURL.path)
        var hashes = defaults.stringArray(forKey: Keys.documentHashes) ?? []
        guard !hashes.contains(h) else { return }
        if hashes.count >= Self.maxStoredHashes {
            defaults.set(defaults.integer(forKey: Keys.documentOverflow) + 1, forKey: Keys.documentOverflow)
        } else {
            hashes.append(h)
            defaults.set(hashes, forKey: Keys.documentHashes)
        }
        stats = snapshot()
    }

    func recordRerender() {
        defaults.set(defaults.integer(forKey: Keys.rerenders) + 1, forKey: Keys.rerenders)
        stats = snapshot()
    }

    func recordBoxChecked() {
        defaults.set(defaults.integer(forKey: Keys.boxesChecked) + 1, forKey: Keys.boxesChecked)
        stats = snapshot()
    }

    func recordActiveDay() {
        let today = dayString(now())
        guard defaults.string(forKey: Keys.lastActiveDay) != today else { return }
        defaults.set(defaults.integer(forKey: Keys.activeDays) + 1, forKey: Keys.activeDays)
        defaults.set(today, forKey: Keys.lastActiveDay)
        stats = snapshot()
    }

    // MARK: - Helpers

    /// Per-install random salt so a known path's hash can't be confirmed.
    private func salt() -> String {
        if let s = defaults.string(forKey: Keys.salt) { return s }
        let s = UUID().uuidString
        defaults.set(s, forKey: Keys.salt)
        return s
    }

    private func hash(_ path: String) -> String {
        let digest = SHA256.hash(data: Data((salt() + path).utf8))
        return String(digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16))
    }

    private func dayString(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
