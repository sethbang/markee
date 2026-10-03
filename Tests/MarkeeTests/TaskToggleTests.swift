import XCTest
@testable import Markee

final class TaskToggleTests: XCTestCase {
    func test_checksAndUnchecks() {
        XCTAssertEqual(TaskToggle.toggledText("- [ ] a\n- [ ] b\n", line: 1, checked: true), "- [ ] a\n- [x] b\n")
        XCTAssertEqual(TaskToggle.toggledText("* [X] a", line: 0, checked: false), "* [ ] a")
    }

    func test_preservesCRLFOnEveryLine() {
        let src = "---\r\na: 1\r\n---\r\n- [ ] a\r\n- [ ] b\r\n"
        XCTAssertEqual(TaskToggle.toggledText(src, line: 4, checked: true),
                       "---\r\na: 1\r\n---\r\n- [ ] a\r\n- [x] b\r\n")
    }

    func test_acceptsEveryMarkerRenderCoreStamps() {
        XCTAssertEqual(TaskToggle.toggledText("1. [ ] a", line: 0, checked: true), "1. [x] a")
        XCTAssertEqual(TaskToggle.toggledText("2) [ ] a", line: 0, checked: true), "2) [x] a")
        XCTAssertEqual(TaskToggle.toggledText("> - [ ] q", line: 0, checked: true), "> - [x] q")
        XCTAssertEqual(TaskToggle.toggledText("> > + [ ] q", line: 0, checked: true), "> > + [x] q")
        XCTAssertEqual(TaskToggle.toggledText("    - [ ] nested", line: 0, checked: true), "    - [x] nested")
    }

    /// The file drifted between click and write: refuse rather than clobber.
    func test_bailsOnDriftedOrOutOfRangeLines() {
        XCTAssertNil(TaskToggle.toggledText("plain text\n- [ ] a", line: 0, checked: true))
        XCTAssertNil(TaskToggle.toggledText("- [ ] a", line: 5, checked: true))
        XCTAssertNil(TaskToggle.toggledText("- [ ] a", line: -1, checked: true))
        XCTAssertNil(TaskToggle.toggledText("- [?] a", line: 0, checked: true))
    }
}
