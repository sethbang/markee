import XCTest
import WebKit
@testable import Markee

@MainActor
final class PreviewControllerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MarkeePreviewControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    /// Posting a `scrollSection` message with an id updates `currentHeadingID`.
    func test_scrollSectionMessage_updatesCurrentHeadingID() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)

        XCTAssertNil(controller.currentHeadingID)

        controller.userContentController(
            WKUserContentController(),
            didReceive: FakeMessage(name: "markee", body: ["kind": "scrollSection", "id": "setup"])
        )

        XCTAssertEqual(controller.currentHeadingID, "setup")
    }

    /// A `scrollSection` with no id (null) clears `currentHeadingID`.
    func test_scrollSectionMessage_withNoID_clears() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        controller.currentHeadingID = "setup"

        controller.userContentController(
            WKUserContentController(),
            didReceive: FakeMessage(name: "markee", body: ["kind": "scrollSection"])
        )

        XCTAssertNil(controller.currentHeadingID)
    }
}

/// WKScriptMessage has no public initializer. This is the standard test
/// workaround — a minimal subclass that overrides `name` and `body`.
private final class FakeMessage: WKScriptMessage {
    private let _name: String
    private let _body: Any
    init(name: String, body: Any) { self._name = name; self._body = body; super.init() }
    override var name: String { _name }
    override var body: Any { _body }
}
