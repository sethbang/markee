import WebKit

/// WKWebView subclass that appends Markee's own items to the native
/// right-click context menu. WKWebView owns its context menu, so SwiftUI's
/// `.contextMenu` cannot reach it — we extend `willOpenMenu` instead.
final class MarkeeWebView: WKWebView {
    /// Weak to avoid a retain cycle: PreviewController owns this webView.
    weak var controller: PreviewController?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // No isKeyWindow guard needed: a right-click targets this exact
        // window directly (unlike the broadcast-to-all-windows menu commands).
        menu.addItem(.separator())

        let copyItem = NSMenuItem(
            title: "Copy Markdown Source",
            action: #selector(copyMarkdownSourceAction),
            keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let reflowItem = NSMenuItem(
            title: "Copy Reflowed Markdown",
            action: #selector(copyReflowedMarkdownAction),
            keyEquivalent: "")
        reflowItem.target = self
        menu.addItem(reflowItem)

        let renderedItem = NSMenuItem(
            title: "Copy as Rendered Text",
            action: #selector(copyRenderedTextAction),
            keyEquivalent: "")
        renderedItem.target = self
        menu.addItem(renderedItem)

        let revealItem = NSMenuItem(
            title: "Reveal in Finder",
            action: #selector(revealInFinderAction),
            keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)
    }

    @objc private func copyMarkdownSourceAction() {
        controller?.copyMarkdownSource()
    }

    @objc private func copyReflowedMarkdownAction() {
        controller?.copyReflowedMarkdown()
    }

    @objc private func copyRenderedTextAction() {
        controller?.copyRenderedText()
    }

    @objc private func revealInFinderAction() {
        controller?.revealInFinder()
    }
}
