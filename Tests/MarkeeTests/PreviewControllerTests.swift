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

        send(controller, ["kind": "scrollSection", "id": "setup"])

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

        send(controller, body, mainFrame: false)
        send(controller, body, frameURL: "https://evil.example/")

        XCTAssertNil(controller.currentHeadingID)
    }

    /// Deliver a bridge message as if from `frameURL` (the template's main
    /// frame by default).
    private func send(_ controller: PreviewController, _ body: [String: Any], mainFrame: Bool = true,
                      frameURL: String = "markee-app://app/template.html") {
        controller.receiveBridgeMessage(name: "markee", isMainFrame: mainFrame,
                                        frameURL: URL(string: frameURL), body: body)
    }

    private func toggle(_ controller: PreviewController, line: Int, checked: Bool) {
        send(controller, ["kind": "taskToggle", "line": line, "checked": checked])
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

        XCTAssertFalse(controller.canSetWorkspaceRoot(other))
        XCTAssertTrue(controller.canSetWorkspaceRoot(docs))
        XCTAssertFalse(controller.setWorkspaceRoot(other))
        XCTAssertTrue(controller.setWorkspaceRoot(docs))
        XCTAssertEqual(controller.workspace.root.path, docs.standardizedFileURL.path)
        XCTAssertTrue(controller.workspace.wikiIndex.isEmpty)   // old root's index dropped
    }

    /// Navigation keeps addressing files through a symlinked workspace root, so
    /// docBase and history stay consistent with the root (and %-escapes decode).
    func test_navigate_keepsSymlinkedRootAndDecodesPath() throws {
        let real = tempDir.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "# A\n".write(to: real.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "# B\n".write(to: real.appendingPathComponent("b c.md"), atomically: true, encoding: .utf8)
        let link = tempDir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let controller = PreviewController(fileURL: link.appendingPathComponent("a.md"))

        send(controller, ["kind": "navigate", "path": "/b%20c.md"])

        XCTAssertEqual(controller.fileURL.path, link.appendingPathComponent("b c.md").standardizedFileURL.path)
        XCTAssertNil(controller.errorBanner)
    }

    /// Repeated WebContent crashes stop auto-reloading and surface a banner.
    func test_contentCrashLoopIsCapped() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        for _ in 0..<3 { controller.webViewWebContentProcessDidTerminate(controller.webView) }
        XCTAssertNil(controller.errorBanner)
        controller.webViewWebContentProcessDidTerminate(controller.webView)
        XCTAssertNotNil(controller.errorBanner)
    }

    /// Menu commands are broadcast to every window; a controller whose window
    /// isn't key (here: no window at all) must ignore them.
    func test_menuCommandsOnlyActInTheKeyWindow() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        NotificationCenter.default.post(name: .toggleOutline, object: nil)
        NotificationCenter.default.post(name: .findInPreview, object: nil)
        XCTAssertFalse(controller.showOutline)
        XCTAssertFalse(controller.showFindBar)
    }

    /// The positive side of the command table: in the key window every routed
    /// command reaches its handler.
    func test_menuCommandsDispatchInTheKeyWindow() async throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                               styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = controller.webView
        let zoomKey = "MarkeeZoomLevel"
        let savedZoom = UserDefaults.standard.object(forKey: zoomKey)
        defer { UserDefaults.standard.set(savedZoom, forKey: zoomKey) }
        UserDefaults.standard.set(1.0, forKey: zoomKey)

        for name: Notification.Name in [.toggleOutline, .toggleFloatOnTop, .findNext, .zoomIn] {
            NotificationCenter.default.post(name: name, object: nil)
        }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(controller.showOutline)
        XCTAssertTrue(controller.pinState.floatOnTop)
        XCTAssertTrue(controller.showFindBar)          // ⌘G with no query reveals the bar
        XCTAssertEqual(UserDefaults.standard.double(forKey: zoomKey), 1.1)
        withExtendedLifetime(window) {}
    }

    /// A `scrollSection` with no id (null) clears `currentHeadingID`.
    func test_scrollSectionMessage_withNoID_clears() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        controller.currentHeadingID = "setup"

        send(controller, ["kind": "scrollSection"])

        XCTAssertNil(controller.currentHeadingID)
    }
}

private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
