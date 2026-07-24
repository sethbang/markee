import XCTest
@testable import Markee

final class SupportNudgeStateTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_750_000_000)
    private func days(_ n: Double) -> Date { epoch.addingTimeInterval(n * 24 * 3600) }
    // Offset from epoch by a raw interval, so boundary tests track the tunable
    // constants instead of hardcoding day counts.
    private func at(_ interval: TimeInterval) -> Date { epoch.addingTimeInterval(interval) }
    private let minute: TimeInterval = 60

    private func state(
        isSupporter: Bool = false,
        firstLaunchDate: Date? = nil,
        launchCount: Int = 0,
        lastSupportDocShownDate: Date? = nil
    ) -> SupportNudgeState {
        SupportNudgeState(
            isSupporter: isSupporter,
            firstLaunchDate: firstLaunchDate,
            launchCount: launchCount,
            lastSupportDocShownDate: lastSupportDocShownDate)
    }

    // Grace period: gracePeriod elapsed AND >= minLaunches. Boundaries are
    // derived from the constants so tuning them doesn't break these tests.

    private var enoughLaunches: Int { SupportNudgeState.minLaunches }

    func test_noNudgesJustBeforeGraceElapses() {
        let s = state(firstLaunchDate: epoch, launchCount: enoughLaunches)
        let justBefore = at(SupportNudgeState.gracePeriod - minute)
        XCTAssertFalse(s.shouldOpenSupportDoc(now: justBefore))
    }

    func test_noNudgesBelowMinLaunches() {
        let s = state(firstLaunchDate: epoch, launchCount: SupportNudgeState.minLaunches - 1)
        let wellPast = at(SupportNudgeState.gracePeriod * 100)
        XCTAssertFalse(s.shouldOpenSupportDoc(now: wellPast))
    }

    func test_nudgesStartAtGraceBoundary() {
        let s = state(firstLaunchDate: epoch, launchCount: enoughLaunches)
        let atBoundary = at(SupportNudgeState.gracePeriod)
        XCTAssertTrue(s.shouldOpenSupportDoc(now: atBoundary))
    }

    func test_noNudgesWhenFirstLaunchUnknown() {
        let s = state(firstLaunchDate: nil, launchCount: 99)
        XCTAssertFalse(s.shouldOpenSupportDoc(now: at(SupportNudgeState.gracePeriod * 100)))
    }

    // Supporter suppresses everything, forever

    func test_supporterSeesNoNudges() {
        let s = state(isSupporter: true, firstLaunchDate: epoch, launchCount: 99)
        XCTAssertFalse(s.shouldOpenSupportDoc(now: days(1000)))
    }

    private var pastGrace: TimeInterval { SupportNudgeState.gracePeriod }

    // Support doc: docQuietPeriod after showing

    func test_docSuppressedWithinQuietPeriod() {
        let s = state(firstLaunchDate: epoch, launchCount: enoughLaunches,
                      lastSupportDocShownDate: at(pastGrace))
        let justBefore = at(pastGrace + SupportNudgeState.docQuietPeriod - minute)
        XCTAssertFalse(s.shouldOpenSupportDoc(now: justBefore))
    }

    func test_docReturnsAfterQuietPeriod() {
        let s = state(firstLaunchDate: epoch, launchCount: enoughLaunches,
                      lastSupportDocShownDate: at(pastGrace))
        let atBoundary = at(pastGrace + SupportNudgeState.docQuietPeriod)
        XCTAssertTrue(s.shouldOpenSupportDoc(now: atBoundary))
    }

    // ignoringGracePeriod (MARKEE_FORCE_NUDGES preview mode)

    func test_ignoringGracePeriodShowsNudgesImmediately() {
        let s = state(firstLaunchDate: epoch, launchCount: 1)
        XCTAssertTrue(s.shouldOpenSupportDoc(now: days(0), ignoringGracePeriod: true))
    }

    func test_ignoringGracePeriodStillSuppressesForSupporter() {
        let s = state(isSupporter: true, firstLaunchDate: epoch, launchCount: 1)
        XCTAssertFalse(s.shouldOpenSupportDoc(now: days(0), ignoringGracePeriod: true))
    }
}
