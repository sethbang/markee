import Cocoa
import Quartz
import MarkeeKit

/// Quick Look preview principal class. Hosts a `MarkeeKit.WebRenderer`'s
/// WKWebView and renders the previewed file into it.
class PreviewViewController: NSViewController, QLPreviewingController {
    private var renderer: WebRenderer?

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL,
                              completionHandler handler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            let renderer = WebRenderer(docRoot: url.deletingLastPathComponent())
            self.renderer = renderer

            renderer.webView.frame = self.view.bounds
            renderer.webView.autoresizingMask = [.width, .height]
            self.view.addSubview(renderer.webView)

            renderer.loadTemplate()
            do {
                try await renderer.waitUntilReady()
                let source = try readFileWithFallback(at: url)
                await renderer.render(source: source,
                                      fileName: url.lastPathComponent,
                                      readOnly: true)
                handler(nil)
            } catch {
                handler(error)
            }
        }
    }
}
