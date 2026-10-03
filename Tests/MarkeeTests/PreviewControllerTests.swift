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

    /// Closing a window must free its controller (and with it the WebContent
    /// process, FileWatcher and observers). Guards the script-handler cycle.
    func test_controllerDeallocatesWhenReleased() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        weak var weakController: PreviewController?
        autoreleasepool {
            let controller = PreviewController(fileURL: file)
            weakController = controller
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(weakController)
    }

    /// Messages from an iframe or a non-template origin are ignored — the
    /// bridge can write files and the clipboard.
    func test_messagesFromUntrustedFramesAreIgnored() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        let body: [String: Any] = ["kind": "scrollSection", "id": "x"]

        controller.userContentController(
            WKUserContentController(),
            didReceive: FakeMessage(name: "markee", body: body, mainFrame: false))
        controller.userContentController(
            WKUserContentController(),
            didReceive: FakeMessage(name: "markee", body: body, frameURL: "https://evil.example/"))

        XCTAssertNil(controller.currentHeadingID)
    }

    private func toggle(_ controller: PreviewController, line: Int, checked: Bool) {
        controller.userContentController(
            WKUserContentController(),
            didReceive: FakeMessage(name: "markee",
                                    body: ["kind": "taskToggle", "line": line, "checked": checked]))
    }

    func test_taskToggle_writesThroughSymlinkToTarget() throws {
        let real = tempDir.appendingPathComponent("real.md")
        let link = tempDir.appendingPathComponent("link.md")
        try "- [ ] a\n".write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let controller = PreviewController(fileURL: link)

        toggle(controller, line: 0, checked: true)

        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8), "- [x] a\n")
        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
    }

    func test_taskToggle_keepsLegacyEncodingAndBOM() throws {
        let file = tempDir.appendingPathComponent("legacy.md")
        let cp1252 = Data([0x63, 0x61, 0x66, 0xE9, 0x0A]) + Data("- [ ] t\n".utf8)
        try cp1252.write(to: file)
        let controller = PreviewController(fileURL: file)
        toggle(controller, line: 1, checked: true)
        XCTAssertEqual(try Data(contentsOf: file), Data([0x63, 0x61, 0x66, 0xE9, 0x0A]) + Data("- [x] t\n".utf8))

        let bomFile = tempDir.appendingPathComponent("bom.md")
        let bom = Data([0xEF, 0xBB, 0xBF])
        try (bom + Data("- [ ] t\r\n".utf8)).write(to: bomFile)
        let bomController = PreviewController(fileURL: bomFile)
        toggle(bomController, line: 0, checked: true)
        XCTAssertEqual(try Data(contentsOf: bomFile), bom + Data("- [x] t\r\n".utf8))
        XCTAssertNil(bomController.errorBanner)
    }

    func test_taskToggle_driftedLineLeavesFileUntouched() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# moved\n- [ ] a\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        toggle(controller, line: 0, checked: true)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# moved\n- [ ] a\n")
    }

    func test_setWorkspaceRoot_rejectsFolderNotContainingDocument() throws {
        let docs = tempDir.appendingPathComponent("docs")
        let other = tempDir.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let file = docs.appendingPathComponent("a.md")
        try "# A\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)

        XCTAssertFalse(controller.setWorkspaceRoot(other))
        XCTAssertTrue(controller.setWorkspaceRoot(docs))
        XCTAssertEqual(controller.workspace.root.path, docs.standardizedFileURL.path)
        XCTAssertTrue(controller.workspace.wikiIndex.isEmpty)   // old root's index dropped
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
/// workaround — a minimal subclass that overrides `name`, `body` and the
/// sending frame (the template's main frame by default).
private final class FakeMessage: WKScriptMessage {
    private let _name: String
    private let _body: Any
    private let _frame: WKFrameInfo
    init(name: String, body: Any, mainFrame: Bool = true,
         frameURL: String = "markee-app://app/template.html") {
        self._name = name; self._body = body
        self._frame = FakeFrameInfo(mainFrame: mainFrame, url: URL(string: frameURL)!)
        super.init()
    }
    override var name: String { _name }
    override var body: Any { _body }
    override var frameInfo: WKFrameInfo { _frame }
}

private final class FakeFrameInfo: WKFrameInfo {
    private let _mainFrame: Bool
    private let _request: URLRequest
    init(mainFrame: Bool, url: URL) {
        self._mainFrame = mainFrame
        self._request = URLRequest(url: url)
        super.init()
    }
    override var isMainFrame: Bool { _mainFrame }
    override var request: URLRequest { _request }
}
