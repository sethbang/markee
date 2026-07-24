import XCTest
@testable import Markee

final class UsageStatsTests: XCTestCase {
    func test_groupedAddsThousandsSeparators() {
        XCTAssertEqual(UsageStats.grouped(0), "0")
        XCTAssertEqual(UsageStats.grouped(142), "142")
        XCTAssertEqual(UsageStats.grouped(1203), "1,203")
        XCTAssertEqual(UsageStats.grouped(1_000_000), "1,000,000")
    }

    func test_zeroStatsAreEqual() {
        XCTAssertEqual(UsageStats.zero, UsageStats.zero)
    }
}
