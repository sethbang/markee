import Foundation

/// A decoded text file plus what's needed to write it back byte-compatibly:
/// the detected encoding and any byte-order mark (stripped from `text`).
public struct DecodedFile: Equatable, Sendable {
    public let text: String
    public let encoding: String.Encoding
    public let bom: Data

    /// Re-encode `newText` the way the file was read (same encoding, same BOM).
    /// Nil if `newText` holds characters the encoding can't represent.
    public func encode(_ newText: String) -> Data? {
        guard let body = newText.data(using: encoding, allowLossyConversion: false) else { return nil }
        return bom + body
    }
}

/// Read a text file, tolerating non-UTF-8 encodings. Decodes, in order:
/// UTF-8 (BOM optional), UTF-16 only when a BOM says so, Windows-1252, then
/// ISO Latin-1 (which maps every byte, so decoding never fails). Throws only
/// if the file itself cannot be read.
///
/// UTF-16 is never guessed: without a BOM almost any even-length byte run
/// "decodes" as UTF-16, turning legacy 8-bit files into CJK mojibake.
public func readDecodedFile(at url: URL) throws -> DecodedFile {
    decodeText(try Data(contentsOf: url))
}

public func decodeText(_ data: Data) -> DecodedFile {
    let utf8BOM = Data([0xEF, 0xBB, 0xBF])
    let utf16LE = Data([0xFF, 0xFE])
    let utf16BE = Data([0xFE, 0xFF])

    if data.starts(with: utf8BOM),
       let s = String(data: data.dropFirst(3), encoding: .utf8) {
        return DecodedFile(text: s, encoding: .utf8, bom: utf8BOM)
    }
    if data.starts(with: utf16LE),
       let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
        return DecodedFile(text: s, encoding: .utf16LittleEndian, bom: utf16LE)
    }
    if data.starts(with: utf16BE),
       let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
        return DecodedFile(text: s, encoding: .utf16BigEndian, bom: utf16BE)
    }
    if let s = String(data: data, encoding: .utf8) {
        return DecodedFile(text: s, encoding: .utf8, bom: Data())
    }
    if let s = String(data: data, encoding: .windowsCP1252) {
        return DecodedFile(text: s, encoding: .windowsCP1252, bom: Data())
    }
    let latin1 = String(decoding: data.map { UInt16($0) }, as: UTF16.self)
    return DecodedFile(text: latin1, encoding: .isoLatin1, bom: Data())
}

/// Text-only convenience over `readDecodedFile(at:)`.
public func readFileWithFallback(at url: URL) throws -> String {
    try readDecodedFile(at: url).text
}
