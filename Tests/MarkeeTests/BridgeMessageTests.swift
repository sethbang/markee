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

    func test_parsesBlockEdit() {
        XCTAssertEqual(BridgeMessage(body: ["kind": "blockEdit", "start": 2, "end": 3,
                                            "original": "alpha beta.", "replacement": "alpha."]),
                       .blockEdit(start: 2, end: 3, original: "alpha beta.", replacement: "alpha."))
    }

    func test_blockEditMissingFieldIsNil() {
        let full: [String: Any] = ["kind": "blockEdit", "start": 2, "end": 3, "original": "a", "replacement": "b"]
        for field in ["start", "end", "original", "replacement"] {
            var body = full
            body.removeValue(forKey: field)
            XCTAssertNil(BridgeMessage(body: body), field)
        }
    }

    func test_parsesEditStateDefaults() {
        XCTAssertEqual(BridgeMessage(body: ["kind": "editState"]),
                       .editState(open: false, dirty: false, focused: false))
        XCTAssertEqual(BridgeMessage(body: ["kind": "editState", "open": true, "dirty": true, "focused": true]),
                       .editState(open: true, dirty: true, focused: true))
    }

    func test_parsesContextBlock() {
        XCTAssertEqual(BridgeMessage(body: ["kind": "contextBlock", "label": "Edit Paragraph", "editable": true, "line": 4]),
                       .contextBlock(label: "Edit Paragraph", editable: true, line: 4))
        XCTAssertEqual(BridgeMessage(body: ["kind": "contextBlock", "label": NSNull(), "line": NSNull()]),
                       .contextBlock(label: nil, editable: false, line: nil))
    }
}
