import XCTest
@testable import MarkeeKit

final class FileReaderTests: XCTestCase {
    func test_plainUTF8() {
        let d = decodeText(Data("café\n".utf8))
        XCTAssertEqual(d.text, "café\n")
        XCTAssertEqual(d.encoding, .utf8)
        XCTAssertTrue(d.bom.isEmpty)
    }

    func test_utf8BOMIsStrippedAndRestoredOnEncode() {
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("- [ ] a\n".utf8)
        let d = decodeText(bytes)
        XCTAssertEqual(d.text, "- [ ] a\n")
        XCTAssertEqual(d.encode(d.text), bytes)
    }

    func test_utf16WithBOMRoundTrips() throws {
        let le = Data([0xFF, 0xFE]) + "héllo\n".data(using: .utf16LittleEndian)!
        let be = Data([0xFE, 0xFF]) + "héllo\n".data(using: .utf16BigEndian)!
        for bytes in [le, be] {
            let d = decodeText(bytes)
            XCTAssertEqual(d.text, "héllo\n")
            XCTAssertEqual(d.encode(d.text), bytes)
        }
    }

    /// Without a BOM, legacy 8-bit text must not be guessed as UTF-16.
    func test_cp1252IsNotMisreadAsUTF16() {
        let bytes = Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94])   // café “q”
        let d = decodeText(bytes)
        XCTAssertEqual(d.text, "café \u{201C}q\u{201D}")
        XCTAssertEqual(d.encoding, .windowsCP1252)
        XCTAssertEqual(d.encode(d.text), bytes)
    }

    func test_bytesUndefinedInCP1252FallBackToLatin1() {
        let bytes = Data([0x61, 0x81, 0x62])
        let d = decodeText(bytes)
        XCTAssertEqual(d.text.unicodeScalars.map(\.value), [0x61, 0x81, 0x62])
        XCTAssertEqual(d.encode(d.text), bytes)
    }

    func test_emptyFile() {
        XCTAssertEqual(decodeText(Data()).text, "")
    }
}
