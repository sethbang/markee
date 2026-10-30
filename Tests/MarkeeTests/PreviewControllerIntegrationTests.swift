import XCTest
import WebKit
@testable import Markee

/// Drives a real PreviewController against the real template + vendored libs
/// in WebKit: the bridge's frame check, task write-back and in-page link
/// handling, end to end (FakeMessage tests can't catch a frame-check misfire).
@MainActor
final class PreviewControllerIntegrationTests: XCTestCase {
    private var tempDir: URL!
    private let webRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/web", isDirectory: true)

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(
            atPath: webRoot.appendingPathComponent("vendor/markdown-it/markdown-it.min.js").path),
            "run `just fetch-vendor` first")
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MarkeeIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    // Async sleep, not RunLoop spinning: spinning inside an async test starves
    // WebKit and the template never commits.
    private func waitUntil(_ timeout: TimeInterval = 20, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func js(_ c: PreviewController, _ script: String) async throws -> Any? {
        try await c.webView.evaluateJavaScript(script)
    }

    func test_realBridgeTaskWriteBackAndFootnoteLink() async throws {
        let file = tempDir.appendingPathComponent("doc.md")
        let source = "---\r\ntags:\r\n  - [ ] yaml, not a task\r\n---\r\n# Title\r\n\r\n"
            + "> - [ ] quoted task\r\n\r\n- [ ] plain task\r\n\r\nClaim.[^1]\r\n\r\n[^1]: Note.\r\n"
        try Data(source.utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)

        // `outline` only arrives if `ready` and the render passed the frame check.
        await waitUntil { !controller.outline.isEmpty }
        XCTAssertEqual(controller.outline.first?.title, "Title")
        XCTAssertEqual(controller.outline.first?.line, 4)

        // Click the blockquoted task: exactly that line (index 6) flips.
        _ = try await js(controller, "document.querySelectorAll('li.task-list-item input')[0].click(); true")
        await waitUntil { (try? String(contentsOf: file, encoding: .utf8))?.contains("> - [x] quoted task") == true }
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertEqual(lines[6], "> - [x] quoted task\r")
        XCTAssertEqual(lines[2], "  - [ ] yaml, not a task\r")
        XCTAssertEqual(lines[8], "- [ ] plain task\r")

        // A footnote link scrolls in place; the main frame keeps the template.
        _ = try await js(controller, "document.querySelector('a[href=\"#fn1\"]').click(); true")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.webView.url.map(NavigationPolicy.isTemplate), true)
        let alive = try await js(controller, "!!window.markee") as? Bool
        XCTAssertEqual(alive, true)
        XCTAssertNil(controller.errorBanner)
    }

    func test_quickEditBeginsOnSelectionAndSavesUnchangedSilently() async throws {
        let file = tempDir.appendingPathComponent("q.md")
        let source = "# T\n\nalpha beta.\n"
        try Data(source.utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        _ = try await js(controller, """
            (() => {
                const text = document.querySelector('#content p').firstChild;
                const range = document.createRange();
                range.setStart(text, 6);
                range.setEnd(text, 10);
                const sel = window.getSelection();
                sel.removeAllRanges();
                sel.addRange(range);
                return sel.toString();
            })()
            """)
        let encoded = String(data: try JSONEncoder().encode(source), encoding: .utf8)!
        let begun = try await js(controller,
            "JSON.stringify(window.markee.beginQuickEdit(\(encoded), 'auto'))") as? String
        XCTAssertEqual(begun, #"{"ok":true}"#)

        let state = try await js(controller, """
            (() => {
                const ta = document.querySelector('.markee-quickedit textarea');
                return ta ? [ta.value, ta.selectionStart, ta.selectionEnd].join('|') : null;
            })()
            """) as? String
        XCTAssertEqual(state, "alpha beta.|6|10")

        _ = try await js(controller, "window.markee.saveQuickEdit(); true")
        try await Task.sleep(for: .milliseconds(200))
        let open = try await js(controller, "!!document.querySelector('.markee-quickedit')") as? Bool
        XCTAssertEqual(open, false)
        let restored = try await js(controller, "document.querySelector('#content p').textContent") as? String
        XCTAssertEqual(restored, "alpha beta.")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), source)
        XCTAssertNil(controller.errorBanner)
    }

    /// A heading slugged "mermaid" makes `window.mermaid` the <h2> element
    /// (named access) until the library loads; nothing may mistake it for
    /// Mermaid. Regression from the theme-redraw hook.
    func test_mermaidHeadingDoesNotShadowTheLibrary() async throws {
        let file = tempDir.appendingPathComponent("m.md")
        try "## Mermaid\n\n```mermaid\ngraph TD; A-->B\n```\n".write(to: file, atomically: true, encoding: .utf8)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }
        var hasSVG = false
        for _ in 0..<200 where !hasSVG {
            try await Task.sleep(for: .milliseconds(100))
            hasSVG = (try await js(controller, "!!document.querySelector('#content pre.mermaid svg')") as? Bool) ?? false
        }
        XCTAssertTrue(hasSVG)
        XCTAssertNil(controller.errorBanner)
    }

    // MARK: - Quick Edit (Swift side)

    private func select(_ c: PreviewController, _ elementJS: String, from start: Int, to end: Int) async throws {
        _ = try await js(c, """
            (() => {
                const text = \(elementJS).firstChild;
                const range = document.createRange();
                range.setStart(text, \(start));
                range.setEnd(text, \(end));
                const sel = window.getSelection();
                sel.removeAllRanges();
                sel.addRange(range);
                return sel.toString();
            })()
            """)
    }

    private func openQuickEdit(_ c: PreviewController, _ elementJS: String, from start: Int, to end: Int) async throws {
        try await select(c, elementJS, from: start, to: end)
        c.performQuickEditCommand()
        await waitUntil(5) { c.quickEdit.open }
        XCTAssertTrue(c.quickEdit.open)
    }

    /// The test harness's WebView has no window, so its focus events can't be
    /// relied on; deliver the same editState the page posts when the textarea
    /// has focus, through the real trust-checked entry point.
    private func deliverFocusedState(_ c: PreviewController) {
        c.receiveBridgeMessage(name: "markee", isMainFrame: true, frameURL: c.webView.url,
                               body: ["kind": "editState", "open": true, "dirty": true, "focused": true])
    }

    private func setEditText(_ c: PreviewController, _ text: String) async throws {
        let encoded = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
        _ = try await js(c, "document.querySelector('.markee-quickedit textarea').value = \(encoded); true")
    }

    private func noticeText(_ c: PreviewController) async -> String? {
        try? await js(c, """
            (() => { const n = document.querySelector('.markee-quickedit-notice');
                     return n && !n.hidden ? n.textContent : null; })()
            """) as? String
    }

    private func waitForNotice(_ c: PreviewController, _ expected: String) async -> String? {
        var notice: String?
        for _ in 0..<100 where notice != expected {
            try? await Task.sleep(for: .milliseconds(50))
            notice = await noticeText(c)
        }
        return notice
    }

    private func editText(_ c: PreviewController) async -> String? {
        try? await js(c, "(document.querySelector('.markee-quickedit textarea') || {}).value") as? String
    }

    private func editorOpen(_ c: PreviewController) async -> Bool {
        (try? await js(c, "!!document.querySelector('.markee-quickedit')") as? Bool) ?? false
    }

    func test_quickEditSaveWritesOnlyTargetLines() async throws {
        let file = tempDir.appendingPathComponent("save.md")
        try Data("# T\r\n\r\nalpha beta.\r\n\r\nend\r\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        try await openQuickEdit(controller, "document.querySelector('#content p')", from: 0, to: 5)
        try await setEditText(controller, "alpha.")
        deliverFocusedState(controller)
        controller.performQuickEditCommand()

        let expected = "# T\r\n\r\nalpha.\r\n\r\nend\r\n"
        await waitUntil(5) { (try? String(contentsOf: file, encoding: .utf8)) == expected }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), expected)
        var paragraph: String?
        for _ in 0..<100 where paragraph != "alpha." {
            try await Task.sleep(for: .milliseconds(50))
            paragraph = try await js(controller, "document.querySelector('#content p').textContent") as? String
        }
        XCTAssertEqual(paragraph, "alpha.")
        let stillOpen = await editorOpen(controller)
        XCTAssertFalse(stillOpen)
        XCTAssertFalse(controller.quickEdit.open)
        XCTAssertNil(controller.errorBanner)
    }

    func test_quickEditSaveRefusedOnConflict() async throws {
        let file = tempDir.appendingPathComponent("conflict.md")
        try Data("# T\n\nalpha beta.\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        try await openQuickEdit(controller, "document.querySelector('#content p')", from: 0, to: 5)
        let external = "# T\n\nalpha gamma.\n"
        try Data(external.utf8).write(to: file)
        // Let the watcher's notice land first, so it can't overwrite the conflict notice.
        var notice: String?
        for _ in 0..<100 where notice != "File changed on disk" {
            try await Task.sleep(for: .milliseconds(50))
            notice = await noticeText(controller)
        }
        XCTAssertEqual(notice, "File changed on disk")

        try await setEditText(controller, "alpha.")
        deliverFocusedState(controller)
        controller.performQuickEditCommand()
        for _ in 0..<100 where notice != "Changed in another editor" {
            try await Task.sleep(for: .milliseconds(50))
            notice = await noticeText(controller)
        }
        XCTAssertEqual(notice, "Changed in another editor")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), external)
        let stillOpen = await editorOpen(controller)
        XCTAssertTrue(stillOpen)
        XCTAssertTrue(controller.quickEdit.open)
    }

    func test_externalChangePausesRenderWhileEditing() async throws {
        let file = tempDir.appendingPathComponent("pause.md")
        try Data("# T\n\nalpha beta.\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        try await openQuickEdit(controller, "document.querySelector('#content p')", from: 0, to: 5)
        try Data("# T\n\nalpha beta.\n\nappended line\n".utf8).write(to: file)
        let notice = await waitForNotice(controller, "File changed on disk")
        XCTAssertEqual(notice, "File changed on disk")
        let stillOpen = await editorOpen(controller)
        XCTAssertTrue(stillOpen)
        let pausedContent = try await js(controller, "document.querySelector('#content').textContent") as? String
        XCTAssertEqual(pausedContent?.contains("appended line"), false)

        _ = try await js(controller, "window.markee.cancelQuickEdit(); true")
        var content: String?
        for _ in 0..<100 where content?.contains("appended line") != true {
            try await Task.sleep(for: .milliseconds(50))
            content = try await js(controller, "document.querySelector('#content').textContent") as? String
        }
        XCTAssertEqual(content?.contains("appended line"), true)
        XCTAssertFalse(controller.quickEdit.open)
    }

    func test_looseListItemEditsWholeItem() async throws {
        let file = tempDir.appendingPathComponent("list.md")
        try Data("- one\n\n- two\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil(10) {
            controller.docWords > 0
        }

        try await openQuickEdit(controller, "document.querySelectorAll('#content li p')[1]", from: 0, to: 3)
        let value = try await js(controller, "document.querySelector('.markee-quickedit textarea').value") as? String
        XCTAssertEqual(value, "- two")
    }

    /// Hang regression: typing in the textarea registered WebKit's undo with
    /// the document's undo manager, marking the read-only FileDocument edited;
    /// autosave, the failed Revert and the next close then deadlocked.
    func test_quickEditTypingNeverTouchesTheWindowUndoManager() async throws {
        let file = tempDir.appendingPathComponent("undo.md")
        try Data("# T\n\nalpha beta.\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        let document = ReadOnlyDocument()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let windowController = NSWindowController(window: window)
        document.addWindowController(windowController)
        window.contentView = controller.webView
        window.makeFirstResponder(controller.webView)
        defer {
            document.removeWindowController(windowController)
            window.contentView = nil
        }
        let documentUndo = try XCTUnwrap(document.undoManager)
        XCTAssertTrue(window.undoManager === documentUndo, "harness: window must use the document's undo manager")
        let webUndo = try XCTUnwrap(controller.webView.undoManager)
        XCTAssertFalse(webUndo === documentUndo)

        try await openQuickEdit(controller, "document.querySelector('#content p')", from: 0, to: 5)
        _ = try await js(controller, """
            (() => { const ta = document.querySelector('.markee-quickedit textarea');
                     ta.focus(); return document.execCommand('insertText', false, 'X'); })()
            """)
        await waitUntil(2) { webUndo.canUndo || documentUndo.canUndo || document.isDocumentEdited }

        XCTAssertFalse(documentUndo.canUndo)
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertTrue(webUndo.canUndo, "WebKit should register the textarea edit with the web view's own undo manager")
    }

    func test_quickEditDisabledForUnwritableFile() async throws {
        let file = tempDir.appendingPathComponent("ro.md")
        try Data("# T\n\nalpha beta.\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }
        XCTAssertFalse(controller.isFileWritable)

        try await select(controller, "document.querySelector('#content p')", from: 0, to: 5)
        controller.performQuickEditCommand()
        try await Task.sleep(for: .milliseconds(500))
        let opened = await editorOpen(controller)
        XCTAssertFalse(opened)
        XCTAssertFalse(controller.quickEdit.open)
    }

    func test_pageReloadDuringEditResumesLiveReload() async throws {
        let file = tempDir.appendingPathComponent("reload.md")
        try Data("# T\n\nalpha beta.\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        try await openQuickEdit(controller, "document.querySelector('#content p')", from: 0, to: 5)
        controller.webViewWebContentProcessDidTerminate(controller.webView)
        XCTAssertFalse(controller.quickEdit.open)
        var rebuilt = false
        for _ in 0..<100 where !rebuilt {
            try await Task.sleep(for: .milliseconds(50))
            rebuilt = (try? await js(controller,
                "!document.querySelector('.markee-quickedit') && !!document.querySelector('#content p')") as? Bool) ?? false
        }
        XCTAssertTrue(rebuilt)

        try Data("# T\n\nalpha beta.\n\nappended line\n".utf8).write(to: file)
        var content: String?
        for _ in 0..<100 where content?.contains("appended line") != true {
            try await Task.sleep(for: .milliseconds(50))
            content = try? await js(controller, "document.querySelector('#content').textContent") as? String
        }
        XCTAssertEqual(content?.contains("appended line"), true)
    }

    func test_taskToggleBailDuringEditKeepsTheDirtyEdit() async throws {
        let file = tempDir.appendingPathComponent("toggle.md")
        try Data("# T\n\nalpha beta.\n\n- [ ] t\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        try await openQuickEdit(controller, "document.querySelector('#content p')", from: 0, to: 5)
        try await setEditText(controller, "alpha dirty.")
        deliverFocusedState(controller)
        // Line 0 is the heading, not a task: the toggle bails.
        controller.receiveBridgeMessage(name: "markee", isMainFrame: true, frameURL: controller.webView.url,
                                        body: ["kind": "taskToggle", "line": 0, "checked": true])

        let notice = await waitForNotice(controller, "File changed on disk")
        XCTAssertEqual(notice, "File changed on disk")
        let text = await editText(controller)
        XCTAssertEqual(text, "alpha dirty.")
        XCTAssertTrue(controller.quickEdit.open)
    }

    func test_unencodableSaveShowsEncodingNoticeAndStaysRetryable() async throws {
        let file = tempDir.appendingPathComponent("cp1252.md")
        let head = Data([0x23, 0x20, 0x63, 0x61, 0x66, 0xE9, 0x0A, 0x0A])
        try (head + Data("alpha beta.\n".utf8)).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        try await openQuickEdit(controller, "document.querySelector('#content p')", from: 0, to: 5)
        try await setEditText(controller, "alpha \u{2192} beta.")
        deliverFocusedState(controller)
        controller.performQuickEditCommand()

        let expected = "Can't save: this file's encoding can't store some characters"
        let notice = await waitForNotice(controller, expected)
        XCTAssertEqual(notice, expected)
        XCTAssertEqual(try Data(contentsOf: file), head + Data("alpha beta.\n".utf8))
        let stillOpen = await editorOpen(controller)
        XCTAssertTrue(stillOpen)

        try await setEditText(controller, "alpha gamma.")
        controller.performQuickEditCommand()
        let saved = head + Data("alpha gamma.\n".utf8)
        await waitUntil(5) { (try? Data(contentsOf: file)) == saved }
        XCTAssertEqual(try Data(contentsOf: file), saved)
    }

    func test_doubleSaveAppliesTheEditOnce() async throws {
        let file = tempDir.appendingPathComponent("double.md")
        try Data("# T\n\nalpha beta.\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        try await openQuickEdit(controller, "document.querySelector('#content p')", from: 0, to: 5)
        try await setEditText(controller, "alpha beta.\nmore.")
        _ = try await js(controller, "window.markee.saveQuickEdit(); window.markee.saveQuickEdit(); true")

        let expected = "# T\n\nalpha beta.\nmore.\n"
        await waitUntil(5) { (try? String(contentsOf: file, encoding: .utf8)) == expected }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), expected)
    }

    func test_loneCarriageReturnRefusesQuickEdit() async throws {
        let file = tempDir.appendingPathComponent("cr.md")
        try Data("# T\ra\n\nalpha beta.\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        // markdown-it reads the lone "\r" as a line break, so "a" is its own paragraph.
        try await select(controller, "document.querySelectorAll('#content p')[1]", from: 0, to: 5)
        controller.performQuickEditCommand()
        try await Task.sleep(for: .milliseconds(500))
        let opened = await editorOpen(controller)
        XCTAssertFalse(opened)
        XCTAssertFalse(controller.quickEdit.open)

        _ = try await js(controller, """
            document.querySelectorAll('#content p')[1]
                .dispatchEvent(new MouseEvent('contextmenu', { bubbles: true })); true
            """)
        await waitUntil(5) { controller.lastContextBlock != nil }
        XCTAssertEqual(controller.lastContextBlock?.editable, false)
    }

    func test_findSkipsTheBlockHiddenBehindAnEdit() async throws {
        let file = tempDir.appendingPathComponent("find.md")
        try Data("# T\n\nalpha beta.\n\nalpha two.\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { !controller.outline.isEmpty }

        try await openQuickEdit(controller, "document.querySelector('#content p')", from: 0, to: 5)
        controller.findTotal = -2
        _ = try await js(controller, "window.markee.find('alpha'); true")
        await waitUntil(5) { controller.findTotal != -2 }
        XCTAssertEqual(controller.findTotal, 1)
    }
    // MARK: - Lists, HTML blocks, headings under an edit

    private func selectAcross(_ c: PreviewController, from startJS: String, _ start: Int,
                              to endJS: String, _ end: Int) async throws {
        _ = try await js(c, """
            (() => {
                const range = document.createRange();
                range.setStart(\(startJS).firstChild, \(start));
                range.setEnd(\(endJS).firstChild, \(end));
                const sel = window.getSelection();
                sel.removeAllRanges();
                sel.addRange(range);
                return sel.toString();
            })()
            """)
    }

    private func beginResult(_ c: PreviewController, _ source: String) async throws -> String? {
        let encoded = String(data: try JSONEncoder().encode(source), encoding: .utf8)!
        return try await js(c, "JSON.stringify(window.markee.beginQuickEdit(\(encoded), 'auto'))") as? String
    }

    func test_selectionAcrossListItemsEditsWholeList() async throws {
        let file = tempDir.appendingPathComponent("wholelist.md")
        try Data("- one\n- two\n- three\n\nend\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil(10) { controller.docWords > 0 }

        try await selectAcross(controller, from: "document.querySelectorAll('#content li')[0]", 0,
                               to: "document.querySelectorAll('#content li')[1]", 2)
        controller.performQuickEditCommand()
        await waitUntil(5) { controller.quickEdit.open }
        let value = await editText(controller)
        XCTAssertEqual(value, "- one\n- two\n- three")

        try await setEditText(controller, "- one\n- 2\n- three")
        deliverFocusedState(controller)
        controller.performQuickEditCommand()
        let expected = "- one\n- 2\n- three\n\nend\n"
        await waitUntil(5) { (try? String(contentsOf: file, encoding: .utf8)) == expected }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), expected)
    }

    func test_selectionInsideOneItemStillEditsTheItem() async throws {
        let file = tempDir.appendingPathComponent("oneitem.md")
        try Data("- one\n- two\n- three\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil(10) { controller.docWords > 0 }

        _ = try await js(controller, """
            document.querySelectorAll('#content li')[1]
                .dispatchEvent(new MouseEvent('contextmenu', { bubbles: true })); true
            """)
        await waitUntil(5) { controller.lastContextBlock != nil }
        XCTAssertEqual(controller.lastContextBlock?.line, 1)
        XCTAssertNotEqual(controller.lastContextBlock?.label, "Edit List")

        try await openQuickEdit(controller, "document.querySelectorAll('#content li')[1]", from: 0, to: 2)
        let value = await editText(controller)
        XCTAssertEqual(value, "- two")
    }

    func test_selfContainedHtmlBlockIsEditable() async throws {
        let file = tempDir.appendingPathComponent("html.md")
        try Data("<div>\n<b>x</b>\n</div>\n\npara\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil(10) { controller.docWords > 0 }

        try await select(controller, "document.querySelector('#content b')", from: 0, to: 1)
        let begun = try await beginResult(controller, "<div>\n<b>x</b>\n</div>\n\npara\n")
        XCTAssertEqual(begun, #"{"ok":true}"#)
        let value = await editText(controller)
        XCTAssertEqual(value, "<div>\n<b>x</b>\n</div>")
        let code = try await js(controller,
            "!!document.querySelector('.markee-quickedit.markee-quickedit-code')") as? Bool
        XCTAssertEqual(code, true)
        let hidden = try await js(controller, """
            getComputedStyle(document.querySelector('.markee-html-block')).display
            """) as? String
        XCTAssertEqual(hidden, "none")

        try await setEditText(controller, "<div>\n<i>y</i>\n</div>")
        deliverFocusedState(controller)
        controller.performQuickEditCommand()
        let expected = "<div>\n<i>y</i>\n</div>\n\npara\n"
        await waitUntil(5) { (try? String(contentsOf: file, encoding: .utf8)) == expected }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), expected)
    }

    func test_htmlBlockWrapperDoesNotChangeLayout() async throws {
        let file = tempDir.appendingPathComponent("htmllayout.md")
        try Data("<div>\n<b>x</b>\n</div>\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil(10) { controller.docWords > 0 }
        let display = try await js(controller,
            "getComputedStyle(document.querySelector('.markee-html-block')).display") as? String
        XCTAssertEqual(display, "contents")
    }

    func test_partialHtmlBlockFallsBack() async throws {
        let file = tempDir.appendingPathComponent("details.md")
        let source = "Intro.\n\n<details>\n<summary>More</summary>\n\nbody\n\n</details>\n"
        try Data(source.utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil(10) { controller.docWords > 0 }

        try await select(controller, "document.querySelector('#content summary')", from: 0, to: 4)
        let begun = try await beginResult(controller, source)
        XCTAssertEqual(begun?.contains(#""reason":"no-range""#), true, begun ?? "nil")
        let open = await editorOpen(controller)
        XCTAssertFalse(open)

        _ = try await js(controller, """
            document.querySelector('#content summary')
                .dispatchEvent(new MouseEvent('contextmenu', { bubbles: true })); true
            """)
        await waitUntil(5) { controller.lastContextBlock != nil }
        XCTAssertEqual(controller.lastContextBlock?.editable, false)
        XCTAssertNotNil(controller.lastContextBlock?.line)
    }

    func test_scrollToHeadingWhileEditingTargetsTheEdit() async throws {
        let file = tempDir.appendingPathComponent("headings.md")
        try Data("# Top\n\npara\n\n## Sub\n\ntext\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil { controller.outline.count == 2 }

        try await openQuickEdit(controller, "document.getElementById('sub')", from: 0, to: 3)
        let target = try await js(controller, """
            (() => {
                let hit = null;
                const w = document.querySelector('.markee-quickedit');
                w.scrollIntoView = () => { hit = 'wrapper'; };
                document.getElementById('sub').scrollIntoView = () => { hit = 'heading'; };
                window.markee.scrollToHeading('sub');
                return hit;
            })()
            """) as? String
        XCTAssertEqual(target, "wrapper")
    }
    func test_activeHeadingUsesTheEditStandingInForAHiddenHeading() async throws {
        let file = tempDir.appendingPathComponent("spy.md")
        let filler = (1...30).map { "Paragraph \($0)." }.joined(separator: "\n\n")
        try Data("# Top\n\n\(filler)\n\n## Sub\n\n\(filler)\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        controller.webView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        await waitUntil { controller.outline.count == 2 }
        await waitUntil(5) { controller.currentHeadingID == "top" }
        XCTAssertEqual(controller.currentHeadingID, "top")

        try await openQuickEdit(controller, "document.getElementById('sub')", from: 0, to: 3)
        // Scrolling the first heading out of the top band makes the observer re-pick.
        _ = try await js(controller, "window.scrollTo(0, 200); true")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.currentHeadingID, "top", "the hidden heading's empty rect read as on-screen")

        _ = try await js(controller, """
            window.scrollTo(0, document.querySelector('.markee-quickedit').getBoundingClientRect().top
                + window.scrollY - 10);
            true
            """)
        await waitUntil(5) { controller.currentHeadingID == "sub" }
        XCTAssertEqual(controller.currentHeadingID, "sub")
    }

    func test_codeModeEditUsesTheSharedCodeFont() async throws {
        let file = tempDir.appendingPathComponent("font.md")
        try Data("<div>\n<b>x</b>\n</div>\n\nSee `code`.\n".utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil(10) { controller.docWords > 0 }

        try await openQuickEdit(controller, "document.querySelector('#content b')", from: 0, to: 1)
        let fonts = try await js(controller, """
            (() => {
                const root = getComputedStyle(document.documentElement).getPropertyValue('--markee-code-font');
                const field = getComputedStyle(document.querySelector('.markee-quickedit-code .markee-quickedit-field'));
                const code = getComputedStyle(document.querySelector('#content p code'));
                return [root.trim() !== '', field.fontFamily === code.fontFamily,
                        field.fontSize === code.fontSize].join(',');
            })()
            """) as? String
        XCTAssertEqual(fonts, "true,true,true")
    }

    private func ledeStyle(_ source: String, _ paragraphJS: String) async throws -> String? {
        let file = tempDir.appendingPathComponent("lede-\(UUID().uuidString).md")
        try Data(source.utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil(10) { controller.docWords > 0 }
        return try await js(controller, """
            (() => { const s = getComputedStyle(\(paragraphJS));
                     return [s.fontSize, s.color, s.marginTop, s.marginBottom].join('|'); })()
            """) as? String
    }

    /// Export unwraps raw-HTML blocks, so the screen must style them as if unwrapped.
    func test_htmlBlockWrapperKeepsTheLede() async throws {
        let plain = try await ledeStyle("# T\n\nlede\n", "document.querySelector('#content p')")
        let body = try await ledeStyle("Body.\n", "document.querySelector('#content p')")
        XCTAssertNotEqual(plain, body)
        let separate = try await ledeStyle("<h1 align=\"center\">T</h1>\n\nlede\n",
                                           "document.querySelector('#content p')")
        XCTAssertEqual(separate, plain)
        let together = try await ledeStyle("<h1>T</h1>\n<p>lede</p>\n", "document.querySelector('#content p')")
        XCTAssertEqual(together, plain)
        let htmlLede = try await ledeStyle("# T\n\n<p>lede</p>\n", "document.querySelector('#content p')")
        XCTAssertEqual(htmlLede, plain)
    }

    func test_fallbackLineIsTheFirstLineAfterThePrecedingBlock() async throws {
        let file = tempDir.appendingPathComponent("longfence.md")
        let fence = "```\n" + (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n```\n"
        let source = "Intro.\n\n" + fence + "\n<details>\n<summary>More</summary>\n\nbody\n\n</details>\n"
        try Data(source.utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil(10) { controller.docWords > 0 }

        let fenceEnd = try await js(controller,
            "parseInt(document.querySelector('#content pre[data-line-end], #content [data-line-end] pre')"
            + ".closest('[data-line-end]').getAttribute('data-line-end'), 10)") as? Int
        XCTAssertEqual(fenceEnd, 24)
        _ = try await js(controller, """
            document.querySelector('#content summary')
                .dispatchEvent(new MouseEvent('contextmenu', { bubbles: true })); true
            """)
        await waitUntil(5) { controller.lastContextBlock != nil }
        XCTAssertEqual(controller.lastContextBlock?.editable, false)
        // fenceEnd is the blank line after the fence; the <details> is next.
        XCTAssertEqual(controller.lastContextBlock?.line, 25)
    }

    /// Raw HTML (wrapped or inside a partial context) and markdown-it-attrs
    /// can't hand Quick Edit or task write-back a source range of their own.
    func test_authorWrittenStampsAreDropped() async throws {
        let file = tempDir.appendingPathComponent("forged.md")
        let source = "Real para.\n\n<div><p id=\"w\" data-line=\"0\" data-line-end=\"99\">wrapped</p></div>\n\n"
            + "<details>\n\n<p id=\"d\" data-line=\"0\" data-line-end=\"99\">partial</p>\n\n</details>\n\n"
            + "x *y*{#e data-line=0 data-line-end=99}\n"
        try Data(source.utf8).write(to: file)
        let controller = PreviewController(fileURL: file, webRoot: webRoot)
        await waitUntil(10) { controller.docWords > 0 }

        let state = try await js(controller, """
            (() => {
                const has = (sel) => document.querySelector(sel).hasAttribute('data-line');
                return [has('#content > p'), has('#w'), has('#d'), has('#e'),
                        document.querySelector('#w').parentElement.parentElement.getAttribute('data-line'),
                        document.querySelectorAll('[data-markee-stamp]').length].join(',');
            })()
            """) as? String
        XCTAssertEqual(state, "true,false,false,false,2,0")
    }
}

/// Stands in for SwiftUI's DocumentGroup NSDocument: owns the undo manager
/// the window (and, through the responder chain, the web view) inherits.
private final class ReadOnlyDocument: NSDocument {
    override func read(from data: Data, ofType typeName: String) throws {}
}
