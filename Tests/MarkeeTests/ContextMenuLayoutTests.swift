import AppKit
import XCTest
@testable import Markee

final class ContextMenuLayoutTests: XCTestCase {
    private func item(_ title: String, _ id: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let id { item.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifier" + id) }
        return item
    }

    /// The menu WebKit builds over a text selection (the 1.3.0 screenshot).
    private func selectionMenu() -> NSMenu {
        let menu = NSMenu()
        [item("Look Up", "LookUp"), item("Translate", "Translate"), item("Search with Google", "SearchWeb"),
         .separator(), item("Copy", "Copy"), item("Copy Link with Highlight", "CopyLinkWithHighlight"),
         .separator(), item("Share…", "ShareMenu"), .separator(), item("Speech", "SpeechMenu")]
            .forEach(menu.addItem)
        return menu
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
    }

    private func copyAs() -> NSMenuItem { item("Copy As") }

    func test_selectionMenu_editFirst_copyAsUnderCopy_deadItemsDropped() {
        let menu = selectionMenu()
        MarkeeWebView.arrange(menu, editItem: item("Edit List Item"), copyAsItem: copyAs(),
                              revealItem: item("Reveal in Finder"))
        XCTAssertEqual(titles(menu), [
            "Edit List Item", "—",
            "Look Up", "Translate", "Search with Google", "—",
            "Copy", "Copy As", "—",
            "Share…", "—",
            "Reveal in Finder",
        ])
    }

    func test_noEditItem_noLeadingSeparator() {
        let menu = selectionMenu()
        MarkeeWebView.arrange(menu, editItem: nil, copyAsItem: copyAs(), revealItem: item("Reveal in Finder"))
        XCTAssertEqual(titles(menu).first, "Look Up")
    }

    func test_menuWithoutCopy_appendsCopyAsBeforeReveal() {
        let menu = NSMenu()
        menu.addItem(item("Reload", "Reload"))
        MarkeeWebView.arrange(menu, editItem: item("Edit Paragraph"), copyAsItem: copyAs(),
                              revealItem: item("Reveal in Finder"))
        XCTAssertEqual(titles(menu), ["Edit Paragraph", "—", "Reload", "—", "Copy As", "—", "Reveal in Finder"])
    }

    func test_emptyMenu_hasNoStraySeparators() {
        let menu = NSMenu()
        MarkeeWebView.arrange(menu, editItem: nil, copyAsItem: copyAs(), revealItem: item("Reveal in Finder"))
        XCTAssertEqual(titles(menu), ["Copy As", "—", "Reveal in Finder"])
    }
}
