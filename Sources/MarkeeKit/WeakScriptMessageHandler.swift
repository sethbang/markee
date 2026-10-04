import WebKit

/// Forwards `WKScriptMessage` callbacks to a weakly-held target.
/// `WKUserContentController` retains its message handler strongly; registering
/// the owner directly makes owner → webView → configuration →
/// userContentController → owner a retain cycle, so the owner (and its
/// WebContent process, watchers and observers) never deallocates.
@MainActor
public final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    public weak var target: WKScriptMessageHandler?

    public init(target: WKScriptMessageHandler) {
        self.target = target
    }

    public func userContentController(_ controller: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
