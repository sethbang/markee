import Foundation

/// Read a text file, tolerating non-UTF-8 encodings. Tries UTF-8, then UTF-16
/// (BOM-detected), then ISO Latin-1. Returns "" only if the file has no bytes
/// decodable by any of those — never throws for an encoding miss; it throws
/// only if the file itself cannot be read.
public func readFileWithFallback(at url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    if let s = String(data: data, encoding: .utf8) { return s }
    if let s = String(data: data, encoding: .utf16) { return s }
    if let s = String(data: data, encoding: .isoLatin1) { return s }
    return ""
}
