import WebKit

/// WKWebView subclass that appends Markee's own items to the native
/// right-click context menu. WKWebView owns its context menu, so SwiftUI's
/// `.contextMenu` cannot reach it — we extend `willOpenMenu` instead.
final class MarkeeWebView: WKWebView {
    weak var controller: PreviewController?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        menu.addItem(.separator())

        let copyItem = NSMenuItem(
            title: "Copy Markdown Source",
            action: #selector(copyMarkdownSourceAction),
            keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

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

    @objc private func revealInFinderAction() {
        controller?.revealInFinder()
    }
}
