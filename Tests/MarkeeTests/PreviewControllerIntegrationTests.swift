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
}
