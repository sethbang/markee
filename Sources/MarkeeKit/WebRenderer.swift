import WebKit

/// Headless Markdown renderer. Owns a `WKWebView` wired with Markee's scheme
/// handlers, loads `template.html`, and exposes async `waitUntilReady()` /
/// `render(...)`. This is the extension-side equivalent of the render path
/// inside the app's `PreviewController` — without file watching, the outline,
/// task write-back, zoom, find, or any app chrome.
@MainActor
public final class WebRenderer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    public let webView: WKWebView

    private let bundleHandler: BundleSchemeHandler
    private let docHandler: DocSchemeHandler
    private var isReady = false

    /// - Parameters:
    ///   - docRoot: directory the document lives in; relative
    ///     `markee-doc://` URLs resolve against it (sandbox permitting).
    ///   - webRoot: override for the bundle's `web/` directory (tests only).
    public init(docRoot: URL, webRoot: URL? = nil) {
        self.docHandler = DocSchemeHandler(docRoot: docRoot)
        self.bundleHandler = webRoot.map(BundleSchemeHandler.init(webRoot:)) ?? BundleSchemeHandler()

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

        userContent.add(WeakScriptMessageHandler(target: self), name: "markee")
        webView.navigationDelegate = self
    }

    /// Quick Look renders arbitrary files with no user action (Finder icon
    /// view), so nothing may leave the machine: the template CSP already pins
    /// scripts to the bundle, and this rule list blocks the remote images and
    /// media the CSP allows in the app.
    /// Content-blocker regexes have no `|` alternation: one rule per scheme.
    static let blockRemoteRules = """
        [{"trigger": {"url-filter": "^https?://"}, "action": {"type": "block"}},
         {"trigger": {"url-filter": "^wss?://"}, "action": {"type": "block"}},
         {"trigger": {"url-filter": "^ftp://"}, "action": {"type": "block"}}]
        """

    static func remoteBlockList() async throws -> WKContentRuleList {
        guard let store = WKContentRuleListStore.default(),
              let list = try await store.compileContentRuleList(
                  forIdentifier: "markee-block-remote", encodedContentRuleList: blockRemoteRules)
        else { throw URLError(.cannotLoadFromNetwork) }
        return list
    }

    /// Install the remote-load block list, then begin loading `template.html`.
    /// Call once, before `waitUntilReady()`. Fails closed: if the block list
    /// can't be installed, nothing renders and Quick Look falls back.
    public func loadTemplate() async throws {
        webView.configuration.userContentController.add(try await Self.remoteBlockList())
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

    /// The main frame only ever holds the template; link clicks in a Quick Look
    /// preview go nowhere rather than replacing it.
    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let isTemplate = url.scheme == BundleSchemeHandler.scheme && url.host == "app"
            && url.path == "/template.html" && navigationAction.navigationType != .linkActivated
        decisionHandler(isMainFrame ? (isTemplate ? .allow : .cancel)
                                    : (url.scheme == "about" ? .allow : .cancel))
    }

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        guard message.name == "markee",
              message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              (body["kind"] as? String) == "ready" else { return }
        isReady = true
    }
}
