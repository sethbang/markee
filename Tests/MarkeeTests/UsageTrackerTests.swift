import XCTest
@testable import Markee

@MainActor
final class UsageTrackerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "UsageTrackerTests")!
        defaults.removePersistentDomain(forName: "UsageTrackerTests")
        clock = Date(timeIntervalSince1970: 1_750_000_000)
    }

    private func make() -> UsageTracker {
        UsageTracker(defaults: defaults, now: { self.clock })
    }

    func test_distinctDocumentsCountedOnce() {
        let t = make()
        t.recordDocumentOpened(URL(fileURLWithPath: "/tmp/a.md"))
        t.recordDocumentOpened(URL(fileURLWithPath: "/tmp/a.md"))
        t.recordDocumentOpened(URL(fileURLWithPath: "/tmp/b.md"))
        XCTAssertEqual(t.stats.documentsPreviewed, 2)
    }

    func test_rawPathIsNeverStored() {
        let t = make()
        t.recordDocumentOpened(URL(fileURLWithPath: "/tmp/secret-name.md"))
        let dump = defaults.dictionaryRepresentation()
        let blob = dump.values.map { "\($0)" }.joined()
        XCTAssertFalse(blob.contains("secret-name"), "raw path leaked into defaults")
    }

    func test_rerenderAndBoxCountersIncrement() {
        let t = make()
        t.recordRerender(); t.recordRerender()
        t.recordBoxChecked()
        XCTAssertEqual(t.stats.rerendersWatched, 2)
        XCTAssertEqual(t.stats.boxesChecked, 1)
    }

    func test_activeDayBumpsOncePerCalendarDay() {
        let t = make()
        t.recordActiveDay()
        t.recordActiveDay()
        XCTAssertEqual(t.stats.activeDays, 1)
        clock = clock.addingTimeInterval(24 * 3600)
        t.recordActiveDay()
        XCTAssertEqual(t.stats.activeDays, 2)
    }

    func test_persistsAcrossInstances() {
        let t = make()
        t.recordDocumentOpened(URL(fileURLWithPath: "/tmp/a.md"))
        t.recordRerender()
        let reloaded = make()
        XCTAssertEqual(reloaded.stats.documentsPreviewed, 1)
        XCTAssertEqual(reloaded.stats.rerendersWatched, 1)
    }
}
