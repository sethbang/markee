import XCTest
import WebKit
@testable import MarkeeKit

@MainActor
final class WebRendererTests: XCTestCase {
    func test_constructsWithAWebView() {
        let renderer = WebRenderer(docRoot: URL(fileURLWithPath: "/tmp"))
        XCTAssertNotNil(renderer.webView)
    }

    /// No loaded renderer → render throws, so Quick Look falls back instead of
    /// handing back a blank card.
    func test_renderThrowsWhenRendererIsMissing() async {
        let renderer = WebRenderer(docRoot: URL(fileURLWithPath: "/tmp"))
        do {
            try await renderer.render(source: "# x", fileName: "x.md", readOnly: true)
            XCTFail("expected render to throw")
        } catch {}
    }

    func test_remoteBlockListCompiles() async throws {
        _ = try await WebRenderer.remoteBlockList()
    }

    func test_loadTemplateDoesNotCrash() async throws {
        let renderer = WebRenderer(docRoot: URL(fileURLWithPath: "/tmp"))
        try await renderer.loadTemplate()
        XCTAssertNotNil(renderer.webView.configuration)
    }

    func test_deallocatesAfterLastReference() {
        weak var weakRenderer: WebRenderer?
        autoreleasepool {
            let renderer = WebRenderer(docRoot: URL(fileURLWithPath: "/tmp"))
            weakRenderer = renderer
            XCTAssertNotNil(weakRenderer)
        }
        // Drain autorelease pools / let WebKit settle.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(weakRenderer,
                     "WebRenderer must not be retained by its own WKWebView's message handler")
    }

    /// End-to-end against the real template + vendored libs: the CSP must let
    /// Markee's own pipeline render (incl. KaTeX) while untrusted inline
    /// script in the document never runs.
    func test_templateCSPBlocksDocumentScriptButRenders() async throws {
        let webRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/web", isDirectory: true)
        try XCTSkipUnless(FileManager.default.fileExists(
            atPath: webRoot.appendingPathComponent("vendor/markdown-it/markdown-it.min.js").path),
            "run `just fetch-vendor` first")
        let renderer = WebRenderer(docRoot: URL(fileURLWithPath: NSTemporaryDirectory()), webRoot: webRoot)
        try await renderer.loadTemplate()
        try await withTimeout(seconds: 20) { try await renderer.waitUntilReady() }
        let source = """
            # Title

            <img src="nope.png" onerror="document.title='pwned-onerror'">
            <a id="lnk" href="javascript:document.title='pwned-href'">x</a>
            <svg><script>document.title='pwned-svg'</script></svg>

            para {onmouseover="document.title='pwned-attrs'"}

            $e^{i\\pi}$
            """
        try await renderer.render(source: source, fileName: "t.md", readOnly: true)
        try await Task.sleep(for: .milliseconds(300))
        let probe = try await renderer.webView.evaluateJavaScript("""
            JSON.stringify({title: document.title,
                            h1: !!document.querySelector('#content h1'),
                            katex: !!document.querySelector('#content .katex'),
                            onAttr: !!document.querySelector('#content [onmouseover]')})
            """) as? String
        let result = try JSONSerialization.jsonObject(with: Data((probe ?? "{}").utf8)) as? [String: Any]
        XCTAssertEqual(result?["h1"] as? Bool, true)
        XCTAssertEqual(result?["katex"] as? Bool, true)
        XCTAssertEqual(result?["onAttr"] as? Bool, false)
        XCTAssertFalse((result?["title"] as? String ?? "").hasPrefix("pwned"))
    }

    /// Mermaid is lazy-loaded and injects inline styles: it must survive the CSP.
    func test_mermaidRendersUnderCSP() async throws {
        let webRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/web", isDirectory: true)
        try XCTSkipUnless(FileManager.default.fileExists(
            atPath: webRoot.appendingPathComponent("vendor/mermaid/mermaid.min.js").path),
            "run `just fetch-vendor` first")
        let renderer = WebRenderer(docRoot: URL(fileURLWithPath: NSTemporaryDirectory()), webRoot: webRoot)
        try await renderer.loadTemplate()
        try await withTimeout(seconds: 20) { try await renderer.waitUntilReady() }
        try await renderer.render(source: "```mermaid\ngraph TD; A-->B\n```\n", fileName: "m.md", readOnly: true)
        var hasSVG = false
        for _ in 0..<200 where !hasSVG {
            try await Task.sleep(for: .milliseconds(100))
            hasSVG = (try await renderer.webView.evaluateJavaScript(
                "!!document.querySelector('#content pre.mermaid svg')") as? Bool) ?? false
        }
        XCTAssertTrue(hasSVG)

        // A theme change redraws the diagram from its kept source.
        _ = try await renderer.webView.evaluateJavaScript(
            "document.querySelector('#content pre.mermaid svg').setAttribute('data-stale', '1');" +
            // Flip to whichever theme the OS isn't in, so it's a real change.
            "window.markee.applySettings({theme: matchMedia('(prefers-color-scheme: dark)').matches ? 'light' : 'dark'}); true")
        var redrawn = false
        for _ in 0..<200 where !redrawn {
            try await Task.sleep(for: .milliseconds(100))
            redrawn = (try await renderer.webView.evaluateJavaScript(
                "!!document.querySelector('#content pre.mermaid svg:not([data-stale])')") as? Bool) ?? false
        }
        XCTAssertTrue(redrawn, "diagram not redrawn after theme change")
    }

    /// Export ships the canonical light look and self-contained math fonts.
    func test_exportStandaloneIsLightAndInlinesKaTeXFonts() async throws {
        let webRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/web", isDirectory: true)
        try XCTSkipUnless(FileManager.default.fileExists(
            atPath: webRoot.appendingPathComponent("vendor/katex/katex.min.css").path),
            "run `just fetch-vendor` first")
        let renderer = WebRenderer(docRoot: URL(fileURLWithPath: NSTemporaryDirectory()), webRoot: webRoot)
        try await renderer.loadTemplate()
        try await withTimeout(seconds: 20) { try await renderer.waitUntilReady() }
        try await renderer.render(source: "# T\n\n$x^2$\n\n```swift\nlet a = 1\n```\n",
                              fileName: "e.md", readOnly: false)
        let html = try await renderer.webView.callAsyncJavaScript(
            "return await window.markee.exportStandalone();", contentWorld: .page) as? String ?? ""
        XCTAssertFalse(html.contains("#0d1117"), "github-dark leaked into the export")
        XCTAssertTrue(html.contains("url(data:font/woff2"), "KaTeX fonts not inlined")
        XCTAssertFalse(html.contains("url(fonts/KaTeX_Main-Regular.woff2)"))
        XCTAssertFalse(html.contains("data-line="))
        // Forced light, or a dark-mode reader gets theme.css's OS-dark block.
        XCTAssertTrue(html.contains("<html lang=\"en\" data-theme=\"light\">"))
        XCTAssertTrue(html.contains("<title>e.md</title>"))
    }

    /// A theme change while no diagram is on screen must still reach the next
    /// diagram drawn.
    func test_mermaidPicksUpThemeChangedWhileNoDiagramShown() async throws {
        let webRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/web", isDirectory: true)
        try XCTSkipUnless(FileManager.default.fileExists(
            atPath: webRoot.appendingPathComponent("vendor/mermaid/mermaid.min.js").path),
            "run `just fetch-vendor` first")
        let renderer = WebRenderer(docRoot: URL(fileURLWithPath: NSTemporaryDirectory()), webRoot: webRoot)
        try await renderer.loadTemplate()
        try await withTimeout(seconds: 20) { try await renderer.waitUntilReady() }
        let diagram = "```mermaid\ngraph TD; A-->B\n```\n"
        let svgStyle = "(document.querySelector('#content pre.mermaid svg style') || {}).textContent || ''"
        func waitForSVG() async throws -> String {
            for _ in 0..<200 {
                let css = try await renderer.webView.evaluateJavaScript(svgStyle) as? String ?? ""
                if !css.isEmpty { return css }
                try await Task.sleep(for: .milliseconds(100))
            }
            return ""
        }

        _ = try await renderer.webView.evaluateJavaScript("window.markee.applySettings({theme: 'light'}); true")
        try await renderer.render(source: diagram, fileName: "m.md", readOnly: true)
        let light = try await waitForSVG()
        XCTAssertTrue(light.lowercased().contains("#ececff"), "expected Mermaid's default (light) palette")

        try await renderer.render(source: "# No diagram\n", fileName: "n.md", readOnly: true)
        _ = try await renderer.webView.evaluateJavaScript("window.markee.applySettings({theme: 'dark'}); true")
        try await renderer.render(source: diagram, fileName: "m.md", readOnly: true)
        let dark = try await waitForSVG()
        XCTAssertFalse(dark.isEmpty)
        XCTAssertFalse(dark.lowercased().contains("#ececff"), "diagram drawn with the stale light theme")
    }

    /// The page's own ids (#toast, #content) are never handed to document
    /// headings or explicit {#id}s.
    func test_headingsNeverTakeThePagesOwnIds() async throws {
        let webRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/web", isDirectory: true)
        try XCTSkipUnless(FileManager.default.fileExists(
            atPath: webRoot.appendingPathComponent("vendor/markdown-it/markdown-it.min.js").path),
            "run `just fetch-vendor` first")
        let renderer = WebRenderer(docRoot: URL(fileURLWithPath: NSTemporaryDirectory()), webRoot: webRoot)
        try await renderer.loadTemplate()
        try await withTimeout(seconds: 20) { try await renderer.waitUntilReady() }
        try await renderer.render(source: "## Toast\n\n## Content\n\npara {#toast}\n",
                                  fileName: "t.md", readOnly: false)
        let probe = try await renderer.webView.evaluateJavaScript("""
            JSON.stringify({toasts: document.querySelectorAll('[id="toast"]').length,
                            contents: document.querySelectorAll('[id="content"]').length,
                            toastTag: document.getElementById('toast').tagName,
                            ids: Array.from(document.querySelectorAll('#content h2')).map(h => h.id)})
            """) as? String
        let result = try JSONSerialization.jsonObject(with: Data((probe ?? "{}").utf8)) as? [String: Any]
        XCTAssertEqual(result?["toasts"] as? Int, 1)
        XCTAssertEqual(result?["contents"] as? Int, 1)
        XCTAssertEqual(result?["toastTag"] as? String, "DIV")
        let ids = result?["ids"] as? [String] ?? []
        XCTAssertEqual(ids.count, 2)
        XCTAssertFalse(ids.contains("toast") || ids.contains("content") || ids.contains(""), "\(ids)")
    }
}
