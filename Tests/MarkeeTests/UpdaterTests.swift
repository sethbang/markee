import XCTest
@testable import Markee

final class AppVersionTests: XCTestCase {
    func test_parsesDottedNumbers() {
        XCTAssertEqual(AppVersion("0.4.0")?.components, [0, 4, 0])
    }

    func test_toleratesLeadingV() {
        XCTAssertEqual(AppVersion("v1.2.3")?.components, [1, 2, 3])
    }

    func test_dropsPrereleaseSuffix() {
        XCTAssertEqual(AppVersion("0.5.0-beta")?.components, [0, 5, 0])
    }

    func test_newerComparesGreater() {
        XCTAssertTrue(AppVersion("0.5.0")! > AppVersion("0.4.0")!)
        XCTAssertTrue(AppVersion("0.4.1")! > AppVersion("0.4.0")!)
        XCTAssertTrue(AppVersion("1.0.0")! > AppVersion("0.9.9")!)
    }

    func test_missingTrailingComponentsTreatedAsZero() {
        XCTAssertEqual(AppVersion("0.4"), AppVersion("0.4.0"))
        XCTAssertFalse(AppVersion("0.4")! > AppVersion("0.4.0")!)
    }

    func test_rejectsNonNumeric() {
        XCTAssertNil(AppVersion("not-a-version"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1.x.0"))
    }
}
