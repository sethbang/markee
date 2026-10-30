import WebKit

/// WKWebView subclass that reshapes the native right-click context menu
/// (see `arrange`). WKWebView owns its context menu, so SwiftUI's
/// `.contextMenu` cannot reach it — we override `willOpenMenu` instead.
final class MarkeeWebView: WKWebView {
    /// Weak to avoid a retain cycle: PreviewController owns this webView.
    weak var controller: PreviewController?

    /// Page editing (Quick Edit's textarea) must never reach the window's undo
    /// manager, which is the read-only DocumentGroup NSDocument's: an undo group
    /// marks it edited → autosave → "changed by another application" → a failed
    /// Revert that leaves a serialization activity open → the next close hangs.
    private let pageUndoManager = UndoManager()

    override var undoManager: UndoManager? { pageUndoManager }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // No isKeyWindow guard needed: a right-click targets this exact
        // window directly (unlike the broadcast-to-all-windows menu commands).
        let copyAs = NSMenu(title: "Copy As")
        copyAs.addItem(menuItem("Markdown Source", #selector(copyMarkdownSourceAction)))
        copyAs.addItem(menuItem("Reflowed Markdown", #selector(copyReflowedMarkdownAction)))
        copyAs.addItem(menuItem("Rendered Text", #selector(copyRenderedTextAction)))
        let copyAsItem = NSMenuItem(title: "Copy As", action: nil, keyEquivalent: "")
        copyAsItem.submenu = copyAs

        Self.arrange(menu,
                     editItem: quickEditItem(),
                     copyAsItem: copyAsItem,
                     revealItem: menuItem("Reveal in Finder", #selector(revealInFinderAction)))
    }

    /// WebKit's private identifiers (`WKMenuItemIdentifiers`); matched as
    /// strings, so a rename only means the item stays in the menu.
    static let copyIdentifier = "WKMenuItemIdentifierCopy"
    static let droppedIdentifiers: Set<String> = [
        "WKMenuItemIdentifierCopyLinkWithHighlight", // always disabled for a local file
        "WKMenuItemIdentifierSpeechMenu",
    ]

    /// Reshapes WebKit's menu: Quick Edit first, Copy As right under Copy
    /// (else at the end), Reveal in Finder last. AppKit appends Services after.
    static func arrange(_ menu: NSMenu, editItem: NSMenuItem?, copyAsItem: NSMenuItem, revealItem: NSMenuItem) {
        for item in menu.items where droppedIdentifiers.contains(item.identifier?.rawValue ?? "") {
            menu.removeItem(item)
        }

        if let copy = menu.items.firstIndex(where: { $0.identifier?.rawValue == copyIdentifier }) {
            menu.insertItem(copyAsItem, at: copy + 1)
        } else {
            menu.addItem(.separator())
            menu.addItem(copyAsItem)
        }
        menu.addItem(.separator())
        menu.addItem(revealItem)

        if let editItem {
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(editItem, at: 0)
        }

        // Removals and insertions leave stray separators; collapse them.
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator {
                menu.removeItem(item)
            } else {
                previousWasSeparator = item.isSeparatorItem
            }
        }
        if let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// The page posts `contextBlock` from a capture-phase listener before
    /// WebKit opens this menu; consumed here so it never outlives the menu.
    private func quickEditItem() -> NSMenuItem? {
        guard let controller else { return nil }
        switch QuickEditMenuChoice.choose(block: controller.takeContextBlock(), writable: controller.isFileWritable) {
        case .edit(let label):
            return menuItem(label, #selector(quickEditAction))
        case .openInEditor(let line):
            let item = menuItem("Open in Editor at This Line", #selector(openInEditorAction(_:)))
            item.representedObject = line
            return item
        case .none:
            return nil
        }
    }

    @objc private func quickEditAction() {
        controller?.beginQuickEditFromContextMenu()
    }

    @objc private func openInEditorAction(_ sender: NSMenuItem) {
        controller?.openInEditor(atLine: sender.representedObject as? Int)
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
