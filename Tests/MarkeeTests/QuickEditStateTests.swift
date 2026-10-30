import XCTest
@testable import Markee

final class QuickEditStateTests: XCTestCase {
    func test_unwritableFileCanOnlyFinishAnOpenEdit() {
        XCTAssertNil(QuickEditState.command(for: QuickEditState(), writable: false))
        // The save re-checks writability and says why it refused.
        XCTAssertEqual(QuickEditState.command(for: QuickEditState(open: true, dirty: true, focused: true), writable: false), .save)
        XCTAssertEqual(QuickEditState.command(for: QuickEditState(open: true, dirty: true, focused: false), writable: false), .focus)
    }

    func test_closedBegins() {
        XCTAssertEqual(QuickEditState.command(for: QuickEditState(), writable: true), .begin)
    }

    func test_openAndFocusedSaves() {
        XCTAssertEqual(QuickEditState.command(for: QuickEditState(open: true, dirty: true, focused: true), writable: true), .save)
        XCTAssertEqual(QuickEditState.command(for: QuickEditState(open: true, dirty: false, focused: true), writable: true), .save)
    }

    func test_openButUnfocusedFocuses() {
        XCTAssertEqual(QuickEditState.command(for: QuickEditState(open: true, dirty: true, focused: false), writable: true), .focus)
    }

    func test_needsDiscardConfirmationOnlyWhenOpenAndDirty() {
        XCTAssertFalse(QuickEditState(open: false, dirty: false).needsDiscardConfirmation)
        XCTAssertFalse(QuickEditState(open: false, dirty: true).needsDiscardConfirmation)
        XCTAssertFalse(QuickEditState(open: true, dirty: false).needsDiscardConfirmation)
        XCTAssertTrue(QuickEditState(open: true, dirty: true).needsDiscardConfirmation)
    }

    // MARK: - Context-menu choice

    private func block(_ label: String?, editable: Bool, line: Int?) -> QuickEditContextBlock {
        QuickEditContextBlock(label: label, editable: editable, line: line)
    }

    func test_menuChoiceEditsAnEditableBlockInAWritableFile() {
        XCTAssertEqual(QuickEditMenuChoice.choose(block: block("Edit Paragraph", editable: true, line: 3), writable: true),
                       .edit(label: "Edit Paragraph"))
    }

    func test_menuChoiceNeedsALabelToEdit() {
        XCTAssertEqual(QuickEditMenuChoice.choose(block: block(nil, editable: true, line: 3), writable: true), .none)
    }

    /// Spec call #11: no Quick Edit item for a file that can't be written; an
    /// editable block there gets no item at all.
    func test_menuChoiceOffersNothingForAnEditableBlockInAnUnwritableFile() {
        XCTAssertEqual(QuickEditMenuChoice.choose(block: block("Edit Paragraph", editable: true, line: 3), writable: false), .none)
    }

    func test_menuChoiceOpensInEditorForANonEditableBlockWithALine() {
        XCTAssertEqual(QuickEditMenuChoice.choose(block: block(nil, editable: false, line: 7), writable: true), .openInEditor(line: 7))
        XCTAssertEqual(QuickEditMenuChoice.choose(block: block(nil, editable: false, line: 7), writable: false), .openInEditor(line: 7))
    }

    func test_menuChoiceOffersNothingWithoutABlockOrALine() {
        XCTAssertEqual(QuickEditMenuChoice.choose(block: block(nil, editable: false, line: nil), writable: true), .none)
        XCTAssertEqual(QuickEditMenuChoice.choose(block: nil, writable: true), .none)
    }
}
