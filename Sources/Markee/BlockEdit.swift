import Foundation

/// Pure conflict-checked line replacement behind Quick Edit write-back.
enum BlockEdit {
    /// Replace 0-indexed lines `start..<end` of `text` with `replacement`, but
    /// only if those lines still read `expected`. Returns nil — write nothing —
    /// if the range is out of bounds or the file changed since the editor opened.
    ///
    /// `expected` and `replacement` are "\n"-joined with no "\r"; `text` is split
    /// and re-joined on "\n" only, so every untouched byte survives. Line-ending
    /// rule for the new lines:
    /// - the last new line ends in "\r" exactly when the original last replaced
    ///   line did, so the boundary into the following line is unchanged and a
    ///   file's final newline-less line stays bare;
    /// - every other new line ends in "\r" when the file's ending at the range
    ///   is CRLF: the first replaced line's ending, or, when that line is the
    ///   file's unterminated last line, the ending of the line before it;
    /// - an insertion (`start == end`) has no original last line, so all its
    ///   lines use that range ending.
    /// An empty `replacement` deletes the lines; deleting through the end of
    /// the file also drops the "\r" of the new last line, so it stays bare.
    static func replacing(_ text: String, start: Int, end: Int, expected: String, with replacement: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard start >= 0, start <= end, end <= lines.count else { return nil }

        let lengthBefore = lines.count
        let original = lines[start..<end]
        let current = original.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        // By scalars: String == treats canonically equivalent text (e.g.
        // decomposed vs precomposed "é") as equal, which would let a save
        // silently renormalize lines it was told were unchanged.
        guard current.joined(separator: "\n").unicodeScalars.elementsEqual(expected.unicodeScalars) else { return nil }

        let probe = start < lines.count - 1 ? start : start - 1
        let rangeCR = probe >= 0 && lines[probe].hasSuffix("\r")
        let lastCR = original.last.map { $0.hasSuffix("\r") } ?? rangeCR

        var newLines = replacement.isEmpty ? [] : replacement.components(separatedBy: "\n")
        for i in newLines.indices where i == newLines.count - 1 ? lastCR : rangeCR {
            newLines[i] += "\r"
        }
        lines.replaceSubrange(start..<end, with: newLines)
        if newLines.isEmpty, end == lengthBefore, start > 0, lines[start - 1].hasSuffix("\r") {
            lines[start - 1].removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
