import XCTest
@testable import Markee

final class SupportMilestonesTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_750_000_000)
    private let minute: TimeInterval = 60

    private func stats(docs: Int = 0, rerenders: Int = 0, days: Int = 0, boxes: Int = 0) -> UsageStats {
        UsageStats(documentsPreviewed: docs, rerendersWatched: rerenders,
                   activeDays: days, boxesChecked: boxes)
    }

    func test_nothingCrossedOnFreshInstall() {
        XCTAssertTrue(SupportMilestones.crossed(.zero).isEmpty)
        XCTAssertNil(SupportMilestones.next(stats: .zero, celebrated: [], lastShown: nil, now: epoch))
    }

    func test_crossingAThresholdIsCelebrated() {
        let m = SupportMilestones.next(stats: stats(rerenders: 100), celebrated: [], lastShown: nil, now: epoch)
        XCTAssertEqual(m, SupportMilestone(kind: .rerenders, threshold: 100))
    }

    func test_justBelowAThresholdIsNot() {
        XCTAssertNil(SupportMilestones.next(stats: stats(rerenders: 99), celebrated: [], lastShown: nil, now: epoch))
    }

    func test_highestThresholdOfAKindWins() {
        let m = SupportMilestones.next(stats: stats(rerenders: 1_200), celebrated: [], lastShown: nil, now: epoch)
        XCTAssertEqual(m?.threshold, 1_000)
    }

    func test_activeDaysOutrankOtherKinds() {
        let m = SupportMilestones.next(stats: stats(rerenders: 100, days: 30), celebrated: [], lastShown: nil, now: epoch)
        XCTAssertEqual(m?.kind, .activeDays)
    }

    func test_celebratedMilestonesAreSkipped() {
        let s = stats(rerenders: 100, days: 30)
        let m = SupportMilestones.next(stats: s, celebrated: ["activeDays.30"], lastShown: nil, now: epoch)
        XCTAssertEqual(m, SupportMilestone(kind: .rerenders, threshold: 100))
    }

    func test_lowerTiersAreNotCelebratedOnceAHigherOneWas() {
        let s = stats(rerenders: 1_200)
        let shown = SupportMilestone(kind: .rerenders, threshold: 1_000)
        let after = SupportMilestones.celebrated(afterShowing: shown, stats: s, previously: [])
        XCTAssertNil(SupportMilestones.next(stats: s, celebrated: after, lastShown: nil, now: epoch))
    }

    func test_pastTheListMilestonesContinueInFixedSteps() {
        XCTAssertEqual(SupportMilestones.thresholds(.rerenders, upTo: 35_000),
                       [100, 500, 1_000, 5_000, 10_000, 20_000, 30_000])
        XCTAssertEqual(SupportMilestones.thresholds(.activeDays, upTo: 1_100), [30, 100, 365, 730, 1_095])
        let m = SupportMilestones.next(stats: stats(rerenders: 100_000), celebrated: ["rerenders.90000"],
                                       lastShown: nil, now: epoch)
        XCTAssertEqual(m?.threshold, 100_000, "a heavy user's next milestone is one step away, not 4x")
    }

    func test_otherKindsTopTierWaitsForALaterDay() {
        let s = stats(docs: 100, rerenders: 1_200, days: 30)
        let first = SupportMilestones.next(stats: s, celebrated: [], lastShown: nil, now: epoch)!
        XCTAssertEqual(first.kind, .activeDays)
        var done = SupportMilestones.celebrated(afterShowing: first, stats: s, previously: [])

        let nextDay = epoch.addingTimeInterval(SupportMilestones.quietPeriod)
        XCTAssertNil(SupportMilestones.next(stats: s, celebrated: done, lastShown: epoch,
                                            now: nextDay.addingTimeInterval(-minute)))
        let second = SupportMilestones.next(stats: s, celebrated: done, lastShown: epoch, now: nextDay)
        XCTAssertEqual(second, SupportMilestone(kind: .rerenders, threshold: 1_000))

        done = SupportMilestones.celebrated(afterShowing: second!, stats: s, previously: done)
        let third = SupportMilestones.next(stats: s, celebrated: done, lastShown: nextDay,
                                           now: nextDay.addingTimeInterval(SupportMilestones.quietPeriod))
        XCTAssertEqual(third, SupportMilestone(kind: .documents, threshold: 100))
        done = SupportMilestones.celebrated(afterShowing: third!, stats: s, previously: done)
        XCTAssertNil(SupportMilestones.next(stats: s, celebrated: done, lastShown: nil, now: epoch),
                     "lower tiers never resurface")
    }

    func test_yearMultiplesReadAsAnniversaries() {
        XCTAssertEqual(SupportMilestone(kind: .activeDays, threshold: 365).headline, "1 year with Markee 🎉")
        XCTAssertEqual(SupportMilestone(kind: .activeDays, threshold: 730).headline, "2 years with Markee 🎉")
        XCTAssertEqual(SupportMilestone(kind: .activeDays, threshold: 100).headline, "100 days with Markee 🎉")
    }

    func test_quietPeriodHoldsTheNextCelebration() {
        let s = stats(rerenders: 100)
        let justBefore = epoch.addingTimeInterval(SupportMilestones.quietPeriod - minute)
        XCTAssertNil(SupportMilestones.next(stats: s, celebrated: [], lastShown: epoch, now: justBefore))
        let atBoundary = epoch.addingTimeInterval(SupportMilestones.quietPeriod)
        XCTAssertNotNil(SupportMilestones.next(stats: s, celebrated: [], lastShown: epoch, now: atBoundary))
    }

    func test_headlinesGroupThousands() {
        XCTAssertEqual(SupportMilestone(kind: .rerenders, threshold: 1_000).headline,
                       "1,000 re-renders watched 🎉")
    }
}
