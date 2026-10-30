import XCTest
import WebKit
import MarkeeKit
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

    // MARK: - Quick Edit discard warnings

    private func makeDirty(_ controller: PreviewController) {
        send(controller, ["kind": "editState", "open": true, "dirty": true, "focused": false])
    }

    func test_navigateBlockedWhenDirtyAndKept() throws {
        let a = tempDir.appendingPathComponent("a.md")
        let b = tempDir.appendingPathComponent("b.md")
        try "# A\n".write(to: a, atomically: true, encoding: .utf8)
        try "# B\n".write(to: b, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: a)
        controller.openFromTree(b)
        makeDirty(controller)
        var asked = 0
        controller.discardPrompt = { asked += 1; return false }
        let canGoForward = controller.history.canGoForward

        controller.goBack()

        XCTAssertEqual(asked, 1)
        XCTAssertEqual(controller.fileURL, b)
        XCTAssertEqual(controller.history.canGoForward, canGoForward)
        XCTAssertTrue(controller.quickEdit.open)
    }

    func test_navigateProceedsWhenNotDirty() throws {
        let a = tempDir.appendingPathComponent("a.md")
        let b = tempDir.appendingPathComponent("b.md")
        try "# A\n".write(to: a, atomically: true, encoding: .utf8)
        try "# B\n".write(to: b, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: a)
        controller.openFromTree(b)
        send(controller, ["kind": "editState", "open": true, "dirty": false, "focused": true])
        var asked = false
        controller.discardPrompt = { asked = true; return false }

        controller.goBack()

        XCTAssertFalse(asked)
        XCTAssertEqual(controller.fileURL, a)
    }

    func test_navigateDiscardsWhenConfirmed() throws {
        let a = tempDir.appendingPathComponent("a.md")
        let b = tempDir.appendingPathComponent("b.md")
        try "# A\n".write(to: a, atomically: true, encoding: .utf8)
        try "# B\n".write(to: b, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: a)
        makeDirty(controller)
        var asked = 0
        controller.discardPrompt = { asked += 1; return true }

        controller.openFromTree(b)

        XCTAssertEqual(asked, 1)
        XCTAssertEqual(controller.fileURL, b)
        XCTAssertFalse(controller.quickEdit.open)
    }

    func test_reloadAsksWhenDirty() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        makeDirty(controller)
        var asked = 0
        controller.discardPrompt = { asked += 1; return false }

        controller.reload()

        XCTAssertEqual(asked, 1)
        XCTAssertTrue(controller.quickEdit.needsDiscardConfirmation)
    }

    func test_openFolderAsksWhenDirty() throws {
        let docs = tempDir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let file = docs.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        let originalRoot = controller.workspace.root
        makeDirty(controller)
        var asked = 0
        controller.discardPrompt = { asked += 1; return false }

        XCTAssertFalse(controller.setWorkspaceRoot(tempDir))

        XCTAssertEqual(asked, 1)
        XCTAssertEqual(controller.workspace.root, originalRoot)
        XCTAssertTrue(controller.quickEdit.open)

        controller.discardPrompt = { asked += 1; return true }
        XCTAssertTrue(controller.setWorkspaceRoot(tempDir))
        XCTAssertEqual(asked, 2)
        XCTAssertFalse(controller.quickEdit.open)
    }

    func test_liveRegistryDoesNotRetain() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        weak var weakController: PreviewController?
        var id: ObjectIdentifier?
        autoreleasepool {
            let controller = PreviewController(fileURL: file)
            weakController = controller
            id = ObjectIdentifier(controller)
            XCTAssertTrue(PreviewController.live.allObjects.contains { $0 === controller })
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(weakController)
        XCTAssertFalse(PreviewController.live.allObjects.contains { ObjectIdentifier($0) == id })
    }

    // MARK: - Quick Edit save

    private func openEdit(_ controller: PreviewController) {
        send(controller, ["kind": "editState", "open": true, "dirty": true, "focused": true])
    }

    private func blockEdit(_ controller: PreviewController, _ start: Int, _ end: Int,
                           _ original: String, _ replacement: String) {
        send(controller, ["kind": "blockEdit", "start": start, "end": end,
                          "original": original, "replacement": replacement])
    }

    func test_blockEditAppliedOnceWhenSentTwice() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try Data("a\n\nb\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file)
        openEdit(controller)

        blockEdit(controller, 2, 3, "b", "b\nc")
        blockEdit(controller, 2, 3, "b", "b\nc")

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "a\n\nb\nc\n")
    }

    func test_blockEditIgnoredWithoutAnOpenEdit() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try Data("a\n\nb\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file)

        blockEdit(controller, 2, 3, "b", "z")

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "a\n\nb\n")
    }

    func test_blockEditUnencodableKeepsEditOpenAndFileUntouched() throws {
        let file = tempDir.appendingPathComponent("cp1252.md")
        let bytes = Data([0x63, 0x61, 0x66, 0xE9, 0x0A, 0x0A]) + Data("b\n".utf8)
        try bytes.write(to: file)
        let controller = PreviewController(fileURL: file)
        openEdit(controller)

        blockEdit(controller, 2, 3, "b", "b \u{1F600}")

        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertTrue(controller.quickEdit.open)
        XCTAssertNil(controller.errorBanner)
    }

    func test_blockEditKeepsUTF8BOM() throws {
        let file = tempDir.appendingPathComponent("bom.md")
        let bom = Data([0xEF, 0xBB, 0xBF])
        try (bom + Data("# T\r\n\r\nold \u{00E9}\r\n\r\nend\r\n".utf8)).write(to: file)
        let controller = PreviewController(fileURL: file)
        openEdit(controller)

        blockEdit(controller, 2, 3, "old \u{00E9}", "new \u{2192}\nline")

        XCTAssertEqual(try Data(contentsOf: file),
                       bom + Data("# T\r\n\r\nnew \u{2192}\r\nline\r\n\r\nend\r\n".utf8))
        XCTAssertNil(controller.errorBanner)
    }

    func test_blockEditKeepsUTF16AndBOM() throws {
        let file = tempDir.appendingPathComponent("utf16.md")
        let bom = Data([0xFF, 0xFE])
        let body = { (s: String) in s.data(using: .utf16LittleEndian)! }
        try (bom + body("# T\n\nold\n\nend\n")).write(to: file)
        let controller = PreviewController(fileURL: file)
        openEdit(controller)

        blockEdit(controller, 2, 3, "old", "new \u{2192}")

        XCTAssertEqual(try Data(contentsOf: file), bom + body("# T\n\nnew \u{2192}\n\nend\n"))
        XCTAssertNil(controller.errorBanner)
    }

    func test_blockEditKeepsLatin1Bytes() throws {
        let file = tempDir.appendingPathComponent("latin.md")
        // 0x81 is undefined in CP1252, so this decodes as ISO Latin-1.
        let head = Data([0x63, 0x81, 0xE9, 0x0A, 0x0A])
        try (head + Data("old\n\nend\n".utf8)).write(to: file)
        XCTAssertEqual(try readDecodedFile(at: file).encoding, .isoLatin1)
        let controller = PreviewController(fileURL: file)
        openEdit(controller)

        blockEdit(controller, 2, 3, "old", "na\u{00EF}ve")

        XCTAssertEqual(try Data(contentsOf: file),
                       head + Data([0x6E, 0x61, 0xEF, 0x76, 0x65, 0x0A, 0x0A]) + Data("end\n".utf8))
        XCTAssertNil(controller.errorBanner)
    }

    func test_closeGuardBlocksDirtyCloseAndForwardsOtherwise() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let original = StubWindowDelegate()
        window.delegate = original
        controller.guardClose(of: window)
        controller.guardClose(of: window)          // re-attach must not wrap itself

        makeDirty(controller)
        controller.discardPrompt = { false }
        window.performClose(nil)
        XCTAssertEqual(original.shouldCloseCalls, 0)
        XCTAssertFalse(original.willClose)

        send(controller, ["kind": "editState", "open": false, "dirty": false, "focused": false])
        window.setContentSize(NSSize(width: 300, height: 300))
        XCTAssertTrue(original.didResize)
        window.performClose(nil)
        XCTAssertEqual(original.shouldCloseCalls, 1)
        XCTAssertTrue(original.willClose)
    }

    // MARK: - Quick Edit follow-ups

    /// Records every `window.markee.<fn>` call the controller makes.
    private func recordJS(_ controller: PreviewController) -> () -> [(String, [Any])] {
        var calls: [(String, [Any])] = []
        controller.onJSCall = { calls.append(($0, $1)) }
        return { calls }
    }

    private func renderedSources(_ calls: [(String, [Any])]) -> [String] {
        calls.filter { $0.0 == "render" }.compactMap { ($0.1.first as? [String: Any])?["source"] as? String }
    }

    func test_takeContextBlockClearsAfterMenu() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "a\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file)
        send(controller, ["kind": "contextBlock", "label": "Edit Paragraph", "editable": true, "line": 0])

        XCTAssertEqual(controller.takeContextBlock(), QuickEditContextBlock(label: "Edit Paragraph", editable: true, line: 0))
        XCTAssertNil(controller.takeContextBlock())
    }

    func test_canQuickEditTrueForWritableFile() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "a\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(PreviewController(fileURL: file).canQuickEdit)
    }

    func test_canQuickEditFalseForUnwritableFile() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "a\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        XCTAssertFalse(PreviewController(fileURL: file).canQuickEdit)
    }

    /// The bundled support doc is writable on disk in a dev build but lives in
    /// the signed app bundle.
    func test_canQuickEditFalseInsideBundle() throws {
        let bundle = tempDir.appendingPathComponent("Fake.app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let file = resources.appendingPathComponent("Support Markee.md")
        try "a\n".write(to: file, atomically: true, encoding: .utf8)

        let controller = PreviewController(fileURL: file, appBundleURL: bundle)

        XCTAssertFalse(controller.canQuickEdit)
        XCTAssertFalse(controller.isFileWritable)
    }

    func test_canQuickEditFollowsNavigation() throws {
        let a = tempDir.appendingPathComponent("a.md")
        let b = tempDir.appendingPathComponent("b.md")
        try "# A\n".write(to: a, atomically: true, encoding: .utf8)
        try "# B\n".write(to: b, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: b.path)
        let controller = PreviewController(fileURL: a)
        XCTAssertTrue(controller.canQuickEdit)

        controller.openFromTree(b)
        XCTAssertFalse(controller.canQuickEdit)
        controller.goBack()
        XCTAssertTrue(controller.canQuickEdit)
    }

    /// An atomic write replaces even a 0444 file in a writable folder, so the
    /// save must re-check rather than rely on the write failing.
    func test_saveRefusedWhenFileBecameUnwritable() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try Data("a\n\nb\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file)
        let calls = recordJS(controller)
        openEdit(controller)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)

        blockEdit(controller, 2, 3, "b", "z")

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "a\n\nb\n")
        let resolves = calls().filter { $0.0 == "resolveQuickEdit" }
        XCTAssertEqual(resolves.count, 1)
        XCTAssertEqual((resolves.first?.1.first as? [String: Any])?["reason"] as? String, "write")
        XCTAssertTrue(controller.quickEdit.open)
        XCTAssertFalse(controller.canQuickEdit)
        XCTAssertEqual(controller.errorBanner, "Can't save: doc.md is read-only.")
    }

    /// The main-menu item is ⌘↩'s only route: a refused save must leave it
    /// enabled so the edit can be saved once permissions are fixed.
    func test_refusedSaveKeepsTheMenuItemAndSavesOnceWritableAgain() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try Data("a\n\nb\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file)
        let calls = recordJS(controller)
        openEdit(controller)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        blockEdit(controller, 2, 3, "b", "z")
        XCTAssertFalse(controller.canQuickEdit)
        XCTAssertTrue(controller.quickEditMenuEnabled)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        controller.performQuickEditCommand()
        XCTAssertEqual(calls().last?.0, "saveQuickEdit")
        blockEdit(controller, 2, 3, "b", "z")

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "a\n\nz\n")
        XCTAssertTrue(controller.canQuickEdit)
    }

    func test_menuItemFollowsWritabilityWhenNoEditIsOpen() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try "a\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        let controller = PreviewController(fileURL: file)
        XCTAssertFalse(controller.quickEditMenuEnabled)
        openEdit(controller)
        XCTAssertTrue(controller.quickEditMenuEnabled)
    }

    func test_searchPaletteStaysOpenOnKeepEditing() throws {
        let a = tempDir.appendingPathComponent("a.md")
        let b = tempDir.appendingPathComponent("b.md")
        try "# A\n".write(to: a, atomically: true, encoding: .utf8)
        try "# B\n".write(to: b, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: a)
        controller.showSearchPalette = true
        makeDirty(controller)
        controller.discardPrompt = { false }

        controller.chooseSearchResult(WorkspaceSearch.Result(url: b, name: "b.md", snippet: "", score: 1))

        XCTAssertTrue(controller.showSearchPalette)
        XCTAssertEqual(controller.fileURL, a)
    }

    /// A WebContent crash reloads the page with what's on disk now, not the
    /// text of the last render, and a later Quick Edit opens on that text.
    func test_crashReloadRendersCurrentDiskContent() throws {
        let file = tempDir.appendingPathComponent("doc.md")
        try Data("old\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file)
        let calls = recordJS(controller)
        try Data("new\n".utf8).write(to: file)

        controller.webViewWebContentProcessDidTerminate(controller.webView)
        send(controller, ["kind": "ready"])
        controller.performQuickEditCommand()

        XCTAssertEqual(renderedSources(calls()), ["new\n"])
        XCTAssertEqual(calls().first { $0.0 == "beginQuickEdit" }?.1.first as? String, "new\n")
    }

    /// Leaving a clean (unprompted) edit closes it in Swift, so the page's
    /// later editState(open: false) doesn't render the new document again.
    func test_leavingACleanEditRendersOnce() throws {
        let a = tempDir.appendingPathComponent("a.md")
        let b = tempDir.appendingPathComponent("b.md")
        try "# A\n".write(to: a, atomically: true, encoding: .utf8)
        try "# B\n".write(to: b, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: a)
        send(controller, ["kind": "ready"])
        let calls = recordJS(controller)
        let closed: [String: Any] = ["kind": "editState", "open": false, "dirty": false, "focused": false]

        send(controller, ["kind": "editState", "open": true, "dirty": false, "focused": true])
        controller.openFromTree(b)
        XCTAssertFalse(controller.quickEdit.open)
        send(controller, closed)

        send(controller, ["kind": "editState", "open": true, "dirty": false, "focused": true])
        controller.reload()
        send(controller, closed)

        XCTAssertEqual(renderedSources(calls()), ["# B\n", "# B\n"])
        XCTAssertEqual(calls().filter { $0.0 == "cancelQuickEdit" }.count, 2)
    }
}

private final class StubWindowDelegate: NSObject, NSWindowDelegate {
    var shouldCloseCalls = 0
    var willClose = false
    var didResize = false
    func windowShouldClose(_ sender: NSWindow) -> Bool { shouldCloseCalls += 1; return true }
    func windowWillClose(_ notification: Notification) { willClose = true }
    func windowDidResize(_ notification: Notification) { didResize = true }
}

private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
