import XCTest
@testable import Markee

final class NavigationHistoryTests: XCTestCase {
    private func u(_ s: String) -> URL { URL(fileURLWithPath: s) }

    func test_pushAdvancesCurrentAndEnablesBack() {
        var h = NavigationHistory(initial: u("/a.md"))
        XCTAssertFalse(h.canGoBack)
        XCTAssertFalse(h.canGoForward)
        h.push(u("/b.md"))
        XCTAssertEqual(h.current, u("/b.md"))
        XCTAssertTrue(h.canGoBack)
        XCTAssertFalse(h.canGoForward)
    }

    func test_backThenForwardRestores() {
        var h = NavigationHistory(initial: u("/a.md"))
        h.push(u("/b.md"))
        XCTAssertEqual(h.back(), u("/a.md"))
        XCTAssertTrue(h.canGoForward)
        XCTAssertEqual(h.forward(), u("/b.md"))
        XCTAssertFalse(h.canGoForward)
    }

    func test_pushAfterBackTruncatesForwardStack() {
        var h = NavigationHistory(initial: u("/a.md"))
        h.push(u("/b.md"))
        _ = h.back()                 // at /a.md
        h.push(u("/c.md"))           // truncates /b.md
        XCTAssertEqual(h.current, u("/c.md"))
        XCTAssertFalse(h.canGoForward)
        XCTAssertEqual(h.back(), u("/a.md"))
    }

    func test_pushSameUrlIsNoOp() {
        var h = NavigationHistory(initial: u("/a.md"))
        h.push(u("/a.md"))
        XCTAssertFalse(h.canGoBack)
    }

    func test_backAtStartReturnsNil() {
        var h = NavigationHistory(initial: u("/a.md"))
        XCTAssertNil(h.back())
    }
}
