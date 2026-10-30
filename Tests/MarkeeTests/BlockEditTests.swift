import XCTest
@testable import Markee

final class BlockEditTests: XCTestCase {
    private let doc = "a\n\nb c\n\nd\n"

    func test_replacesMiddleParagraph() {
        XCTAssertEqual(
            BlockEdit.replacing(doc, start: 2, end: 3, expected: "b c", with: "b"),
            "a\n\nb\n\nd\n")
    }

    func test_refusesWhenLinesChanged() {
        XCTAssertNil(BlockEdit.replacing(doc, start: 2, end: 3, expected: "b x", with: "b"))
    }

    /// Swift `String ==` treats canonically equivalent text as equal, so a
    /// decomposed "e\u{0301}" on disk would pass for a precomposed "\u{00E9}"
    /// and the write would silently renormalize the line.
    func test_conflictCheckIsUnicodeExact() {
        let decomposed = "caf\u{0065}\u{0301}\n"
        XCTAssertNil(BlockEdit.replacing(decomposed, start: 0, end: 1, expected: "caf\u{00E9}", with: "x"))
        XCTAssertEqual(BlockEdit.replacing(decomposed, start: 0, end: 1, expected: "caf\u{0065}\u{0301}", with: "x"), "x\n")
    }

    func test_refusesOutOfRange() {
        XCTAssertNil(BlockEdit.replacing(doc, start: 9, end: 10, expected: "", with: "z"))
        XCTAssertNil(BlockEdit.replacing(doc, start: 2, end: 99, expected: "b c\n\nd\n", with: "z"))
        XCTAssertNil(BlockEdit.replacing(doc, start: -1, end: 1, expected: "a", with: "z"))
        XCTAssertNil(BlockEdit.replacing(doc, start: 3, end: 2, expected: "", with: "z"))
    }

    func test_preservesCRLF() {
        XCTAssertEqual(
            BlockEdit.replacing("a\r\nb\r\nc\r\n", start: 1, end: 2, expected: "b", with: "B1\nB2"),
            "a\r\nB1\r\nB2\r\nc\r\n")
    }

    func test_deletingBlockRemovesLines() {
        XCTAssertEqual(
            BlockEdit.replacing("a\n\nb\n\nc", start: 2, end: 3, expected: "b", with: ""),
            "a\n\n\nc")
    }

    func test_lastLineWithoutTrailingNewline() {
        XCTAssertEqual(
            BlockEdit.replacing("a\nb", start: 1, end: 2, expected: "b", with: "z"),
            "a\nz")
    }

    func test_multiLineBlockquoteKeepsPrefixes() {
        XCTAssertEqual(
            BlockEdit.replacing("> one\n> two\n", start: 0, end: 2, expected: "> one\n> two", with: "> one"),
            "> one\n")
    }

    // MARK: - Line endings

    func test_crlfNoTrailingNewline_editingLastBlockKeepsFinalLineBare() {
        let text = "a\r\nb\r\nc"
        XCTAssertEqual(BlockEdit.replacing(text, start: 1, end: 3, expected: "b\nc", with: "b\nC"),
                       "a\r\nb\r\nC")
    }

    func test_crlfNoTrailingNewline_joiningLastBlock() {
        XCTAssertEqual(BlockEdit.replacing("a\r\nb\r\nc", start: 1, end: 3, expected: "b\nc", with: "b c"),
                       "a\r\nb c")
    }

    func test_crlfNoTrailingNewline_extendingLastBlock() {
        XCTAssertEqual(BlockEdit.replacing("a\r\nb\r\nc", start: 1, end: 3, expected: "b\nc", with: "b\nc\nd"),
                       "a\r\nb\r\nc\r\nd")
    }

    func test_crlfSingleLineLastBlockGainingALineUsesCRLFBetween() {
        XCTAssertEqual(BlockEdit.replacing("a\r\nb", start: 1, end: 2, expected: "b", with: "b\nc"),
                       "a\r\nb\r\nc")
    }

    func test_crlfTerminatedBlockKeepsCRLFOnEveryLine() {
        XCTAssertEqual(BlockEdit.replacing("a\r\nb\r\nc\r\n", start: 1, end: 3, expected: "b\nc", with: "x"),
                       "a\r\nx\r\n")
    }

    func test_insertionAtStartEqualsEndUsesFileEnding() {
        XCTAssertEqual(BlockEdit.replacing("a\r\nb\r\n", start: 1, end: 1, expected: "", with: "x\ny"),
                       "a\r\nx\r\ny\r\nb\r\n")
        XCTAssertEqual(BlockEdit.replacing("a\nb\n", start: 1, end: 1, expected: "", with: "x"),
                       "a\nx\nb\n")
    }

    func test_mixedCRInRangeKeepsBoundaryEnding() {
        XCTAssertEqual(BlockEdit.replacing("a\r\nb\nc\r\n", start: 0, end: 2, expected: "a\nb", with: "x\ny\nz"),
                       "x\r\ny\r\nz\nc\r\n")
        XCTAssertEqual(BlockEdit.replacing("a\nb\r\nc\n", start: 0, end: 2, expected: "a\nb", with: "x\ny\nz"),
                       "x\ny\nz\r\nc\n")
    }

    func test_lfSingleLineFileStaysLF() {
        XCTAssertEqual(BlockEdit.replacing("b", start: 0, end: 1, expected: "b", with: "b\nc"), "b\nc")
    }

    func test_crlfNoTrailingNewline_clearingLastBlockLeavesNoStrayCR() {
        XCTAssertEqual(BlockEdit.replacing("a\r\nb\r\nc", start: 2, end: 3, expected: "c", with: ""), "a\r\nb")
    }

    func test_crlfNoTrailingNewline_clearingMultiLineLastBlockLeavesNoStrayCR() {
        XCTAssertEqual(BlockEdit.replacing("a\r\nb\r\nc", start: 1, end: 3, expected: "b\nc", with: ""), "a")
    }

    func test_crlfNoTrailingNewline_clearingTwoLineFileLastLineLeavesNoStrayCR() {
        XCTAssertEqual(BlockEdit.replacing("a\r\nb", start: 1, end: 2, expected: "b", with: ""), "a")
    }

    func test_lfNoTrailingNewline_clearingLastBlock() {
        XCTAssertEqual(BlockEdit.replacing("a\nb\nc", start: 2, end: 3, expected: "c", with: ""), "a\nb")
    }

    func test_crlfTrailingNewline_clearingLastBlockKeepsTerminator() {
        XCTAssertEqual(BlockEdit.replacing("a\r\nb\r\nc\r\n", start: 2, end: 3, expected: "c", with: ""), "a\r\nb\r\n")
    }
}
