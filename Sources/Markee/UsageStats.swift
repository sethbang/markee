import Foundation

/// A pure snapshot of local usage counters shown in the support drawer. All
/// persistence lives in UsageTracker; this type exists so display formatting
/// is testable in isolation.
struct UsageStats: Equatable {
    var documentsPreviewed: Int
    var rerendersWatched: Int
    var activeDays: Int
    var boxesChecked: Int

    static let zero = UsageStats(documentsPreviewed: 0, rerendersWatched: 0,
                                 activeDays: 0, boxesChecked: 0)

    /// Locale-independent thousands grouping (deterministic for tests).
    static func grouped(_ n: Int) -> String {
        let digits = Array(String(abs(n)))
        var out: [Character] = []
        for (i, c) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
}
