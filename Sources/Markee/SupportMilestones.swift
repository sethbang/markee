import Foundation

/// A usage threshold the support drawer celebrates once, when it's crossed.
struct SupportMilestone: Equatable {
    enum Kind: String, CaseIterable {
        case activeDays, rerenders, documents, boxes
    }

    let kind: Kind
    let threshold: Int

    var id: String { "\(kind.rawValue).\(threshold)" }

    var headline: String {
        let n = UsageStats.grouped(threshold)
        switch kind {
        case .activeDays where threshold % 365 == 0:
            let years = threshold / 365
            return "\(years) year\(years == 1 ? "" : "s") with Markee 🎉"
        case .activeDays: return "\(n) days with Markee 🎉"
        case .rerenders: return "\(n) re-renders watched 🎉"
        case .documents: return "\(n) documents previewed 🎉"
        case .boxes: return "\(n) boxes checked 🎉"
        }
    }
}

/// Pure selection rules for milestone celebrations. Persistence and the
/// grace-period/supporter gates live in SupportController.
enum SupportMilestones {
    static let quietPeriod: TimeInterval = 24 * 3600

    /// Hand-picked early thresholds; past the last one, milestones continue in
    /// fixed steps of that last value. Fixed steps, not a geometric sequence,
    /// so a steady user keeps getting them at a steady pace instead of ever
    /// more rarely.
    static func listed(_ kind: SupportMilestone.Kind) -> [Int] {
        switch kind {
        case .activeDays: return [30, 100, 365]
        case .rerenders: return [100, 500, 1_000, 5_000, 10_000]
        case .documents: return [25, 100, 500]
        case .boxes: return [50, 250, 1_000]
        }
    }

    static func thresholds(_ kind: SupportMilestone.Kind, upTo value: Int) -> [Int] {
        let early = listed(kind)
        guard let step = early.last else { return [] }
        var all = early.filter { $0 <= value }
        var t = step + step
        while t <= value {
            all.append(t)
            t += step
        }
        return all
    }

    /// Every reached milestone, strongest first: kinds in declaration order,
    /// highest threshold first within a kind.
    static func crossed(_ stats: UsageStats) -> [SupportMilestone] {
        SupportMilestone.Kind.allCases.flatMap { kind in
            thresholds(kind, upTo: value(kind, in: stats))
                .sorted(by: >)
                .map { SupportMilestone(kind: kind, threshold: $0) }
        }
    }

    /// After `shown` is displayed: every crossed tier counts as celebrated
    /// except each other kind's highest one, so a user who crossed several at
    /// once gets one per kind on later days rather than a backlog of every
    /// tier (or losing the rest outright).
    static func celebrated(afterShowing shown: SupportMilestone, stats: UsageStats,
                           previously: Set<String>) -> Set<String> {
        var ids = previously
        let reached = crossed(stats)
        for kind in SupportMilestone.Kind.allCases {
            let tiers = reached.filter { $0.kind == kind }
            let keepTop = kind != shown.kind && tiers.first.map { !previously.contains($0.id) } == true
            ids.formUnion(tiers.dropFirst(keepTop ? 1 : 0).map(\.id))
        }
        ids.insert(shown.id)
        return ids
    }

    static func next(stats: UsageStats, celebrated: Set<String>, lastShown: Date?, now: Date) -> SupportMilestone? {
        if let lastShown, now.timeIntervalSince(lastShown) < quietPeriod { return nil }
        return crossed(stats).first { !celebrated.contains($0.id) }
    }

    private static func value(_ kind: SupportMilestone.Kind, in stats: UsageStats) -> Int {
        switch kind {
        case .activeDays: return stats.activeDays
        case .rerenders: return stats.rerendersWatched
        case .documents: return stats.documentsPreviewed
        case .boxes: return stats.boxesChecked
        }
    }
}
