import XCTest
@testable import Markee

final class BridgeMessageTests: XCTestCase {
    func test_parsesEveryKind() {
        XCTAssertEqual(BridgeMessage(body: ["kind": "ready"]), .ready)
        XCTAssertEqual(BridgeMessage(body: ["kind": "outline", "items": [
            ["id": "a", "level": 1, "title": "A", "line": 3],
            ["id": "b", "level": 2, "title": "B"],
            ["id": "bad"],
        ]]), .outline([OutlineEntry(id: "a", level: 1, title: "A", line: 3),
                       OutlineEntry(id: "b", level: 2, title: "B", line: nil)]))
        XCTAssertEqual(BridgeMessage(body: ["kind": "error", "message": "x"]), .error("x"))
        XCTAssertEqual(BridgeMessage(body: ["kind": "taskToggle", "line": 4, "checked": true]),
                       .taskToggle(line: 4, checked: true))
        XCTAssertEqual(BridgeMessage(body: ["kind": "scrollSection"]), .scrollSection(id: nil))
        XCTAssertEqual(BridgeMessage(body: ["kind": "copyText", "text": "t"]), .copyText("t", note: "Copied"))
        XCTAssertEqual(BridgeMessage(body: ["kind": "docStats", "words": 9]), .docStats(words: 9, minutes: 1))
        XCTAssertEqual(BridgeMessage(body: ["kind": "findResult", "current": 1, "total": 2]),
                       .findResult(current: 1, total: 2))
        XCTAssertEqual(BridgeMessage(body: ["kind": "navigate", "path": "/a.md", "newWindow": true]),
                       .navigate(path: "/a.md", fragment: "", newWindow: true))
    }

    func test_rejectsUnknownOrIncompleteMessages() {
        XCTAssertNil(BridgeMessage(body: "ready"))
        XCTAssertNil(BridgeMessage(body: ["kind": "launchMissiles"]))
        XCTAssertNil(BridgeMessage(body: ["kind": "taskToggle", "line": "4", "checked": true]))
        XCTAssertNil(BridgeMessage(body: ["kind": "copyText"]))
        XCTAssertNil(BridgeMessage(body: ["kind": "navigate"]))
    }
}
