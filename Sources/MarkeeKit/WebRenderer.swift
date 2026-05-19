import WebKit

/// Forwards `WKScriptMessage` callbacks to a weakly-held target.
/// `WKUserContentController` retains its message handler strongly; without
/// this trampoline the chain WebRenderer → webView → configuration →
/// userContentController → WebRenderer would be a retain cycle and the
/// WebRenderer would never deallocate.
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Headless Markdown renderer. Owns a `WKWebView` wired with Markee's scheme
/// handlers, loads `template.html`, and exposes async `waitUntilReady()` /
/// `render(...)`. This is the extension-side equivalent of the render path
/// inside the app's `PreviewController` — without file watching, the outline,
/// task write-back, zoom, find, or any app chrome.
@MainActor
public final class WebRenderer: NSObject, WKScriptMessageHandler {
    public let webView: WKWebView

    private let bundleHandler = BundleSchemeHandler()
    private let docHandler: DocSchemeHandler
    private var isReady = false

    /// - Parameter docRoot: directory the document lives in; relative
    ///   `markee-doc://` URLs resolve against it (sandbox permitting).
    public init(docRoot: URL) {
        self.docHandler = DocSchemeHandler(docRoot: docRoot)

        let config = WKWebViewConfiguration()
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pagePrefs
        let userContent = WKUserContentController()
        config.userContentController = userContent
        config.setURLSchemeHandler(bundleHandler, forURLScheme: BundleSchemeHandler.scheme)
        config.setURLSchemeHandler(docHandler, forURLScheme: DocSchemeHandler.scheme)

        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        // Weak trampoline: see WeakScriptMessageHandler above.
        let proxy = WeakScriptMessageHandler()
        proxy.target = self
        userContent.add(proxy, name: "markee")
    }

    /// Begin loading `template.html`. Call once, before `waitUntilReady()`.
    public func loadTemplate() {
        var components = URLComponents()
        components.scheme = BundleSchemeHandler.scheme
        components.host = "app"
        components.path = "/template.html"
        guard let url = components.url else { return }
        webView.load(URLRequest(url: url))
    }

    /// Suspend until `app.js` has posted `{kind:"ready"}`. Polls rather than
    /// parking a continuation: `template.html` may never signal ready if it
    /// fails to load, and the poll's `Task.sleep` makes a cancelled caller
    /// (e.g. the thumbnail extension's timeout) unwind cleanly instead of
    /// leaking. Throws `CancellationError` if the calling task is cancelled.
    public func waitUntilReady() async throws {
        while !isReady {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Render `source`. Resolves once the synchronous render call returns
    /// (text + layout in the DOM); asynchronous Mermaid may still finish after.
    public func render(source: String, fileName: String, readOnly: Bool) async {
        let payload: [String: Any] = [
            "source": source,
            "fileName": fileName,
            "docBase": "\(DocSchemeHandler.scheme)://doc/",
            "readOnly": readOnly,
        ]
        // `payload` always serializes to a JSON *object* literal, which is
        // also a valid JS expression — safe to interpolate as the argument.
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.markee && window.markee.render(\(json));") { _, _ in
                continuation.resume()
            }
        }
    }

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        guard message.name == "markee",
              let body = message.body as? [String: Any],
              (body["kind"] as? String) == "ready" else { return }
        isReady = true
    }
}
