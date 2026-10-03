import Cocoa
import Quartz
import MarkeeKit

/// Quick Look preview principal class. Hosts a `MarkeeKit.WebRenderer`'s
/// WKWebView and renders the previewed file into it.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var renderer: WebRenderer?

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL,
                              completionHandler handler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            // The controller may be reused for successive previews; drop the
            // previous renderer's view before mounting the new one.
            self.renderer?.webView.removeFromSuperview()
            let renderer = WebRenderer(docRoot: url.deletingLastPathComponent())
            self.renderer = renderer

            renderer.webView.frame = self.view.bounds
            renderer.webView.autoresizingMask = [.width, .height]
            self.view.addSubview(renderer.webView)

            do {
                try await renderer.loadTemplate()
                // Bounded: a template that never posts `ready` (broken bundle,
                // JS throw before setup) must fail over to the system preview.
                try await withTimeout(seconds: 10) { try await renderer.waitUntilReady() }
                let source = try readFileWithFallback(at: url)
                try await renderer.render(source: source,
                                          fileName: url.lastPathComponent,
                                          readOnly: true)
                handler(nil)
            } catch {
                handler(error)
            }
        }
    }
}
