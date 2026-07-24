import Foundation

/// Pure cadence logic for the supporter nudges. All persistence and UI live
/// in SupportController; this type exists so the timing rules are testable
/// with injected dates.
struct SupportNudgeState {
    var isSupporter: Bool
    var firstLaunchDate: Date?
    var launchCount: Int
    var lastSupportDocShownDate: Date?

    static let gracePeriod: TimeInterval = 7 * 24 * 3600
    static let minLaunches = 3
    static let docQuietPeriod: TimeInterval = 30 * 24 * 3600

    func isPastGracePeriod(now: Date) -> Bool {
        guard let first = firstLaunchDate, launchCount >= Self.minLaunches else { return false }
        return now.timeIntervalSince(first) >= Self.gracePeriod
    }

    func shouldOpenSupportDoc(now: Date, ignoringGracePeriod: Bool = false) -> Bool {
        guard !isSupporter, ignoringGracePeriod || isPastGracePeriod(now: now) else { return false }
        guard let shown = lastSupportDocShownDate else { return true }
        return now.timeIntervalSince(shown) >= Self.docQuietPeriod
    }
}
