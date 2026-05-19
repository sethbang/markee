import WebKit

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
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []

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
        userContent.add(self, name: "markee")
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

    /// Suspend until `app.js` has posted `{kind:"ready"}`. Returns immediately
    /// if that already happened.
    public func waitUntilReady() async {
        if isReady { return }
        await withCheckedContinuation { continuation in
            readyWaiters.append(continuation)
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
        let waiters = readyWaiters
        readyWaiters = []
        for w in waiters { w.resume() }
    }
}
