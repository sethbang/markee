import Foundation

/// What the page's Quick Edit reported last (`editState`), and the pure
/// decision behind the single ⌘↩ command: start an edit, save it, or bring
/// focus back to it — never two of those at once.
struct QuickEditState: Equatable {
    var open = false
    var dirty = false
    var focused = false

    enum Command { case begin, save, focus }

    /// Only starting an edit needs a writable file: an open one can always be
    /// refocused, and its save re-checks writability and says why it refused.
    static func command(for state: QuickEditState, writable: Bool) -> Command? {
        guard state.open else { return writable ? .begin : nil }
        return state.focused ? .save : .focus
    }

    var needsDiscardConfirmation: Bool { open && dirty }
}

/// The block under the last right-click (`contextBlock`), for the context menu.
struct QuickEditContextBlock: Equatable {
    let label: String?
    let editable: Bool
    let line: Int?
}

/// What the right-click menu offers for the block under the click. An
/// editable block in a file that can't be written gets nothing (spec call
/// #11: no Quick Edit item); a non-editable block with a known line offers
/// Open in Editor whatever the file's permissions.
enum QuickEditMenuChoice: Equatable {
    case edit(label: String)
    case openInEditor(line: Int)
    case none

    static func choose(block: QuickEditContextBlock?, writable: Bool) -> QuickEditMenuChoice {
        guard let block else { return .none }
        if block.editable {
            guard writable, let label = block.label else { return .none }
            return .edit(label: label)
        }
        return block.line.map { .openInEditor(line: $0) } ?? .none
    }
}
