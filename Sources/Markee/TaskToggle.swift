import Foundation

/// Pure checkbox rewrite behind task-list write-back.
enum TaskToggle {
    /// A task item's marker line: optional indent and blockquote `>`s, a bullet
    /// or `1.`/`1)` ordinal, then `[ ]`/`[x]`. Must accept every line
    /// render-core stamps as a task (`data-line`), and nothing else.
    private static let regex = try? NSRegularExpression(
        pattern: "^(\\s*(?:>\\s*)*(?:[-+*]|\\d+[.)])\\s+\\[)([ xX])(\\].*)$")

    /// Flip the checkbox on 0-indexed `line` of `text`. Returns nil — write
    /// nothing — if the line is out of range or no longer a task item (the file
    /// drifted between click and write).
    ///
    /// Line endings are preserved: split on "\n" only, so a CRLF line keeps its
    /// trailing "\r", and rejoin on "\n".
    static func toggledText(_ text: String, line: Int, checked: Bool) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard line >= 0, line < lines.count, let regex else { return nil }

        let original = lines[line]
        let hadCR = original.hasSuffix("\r")
        let body = hadCR ? String(original.dropLast()) : original
        guard let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) else {
            return nil
        }
        let nsBody = body as NSString
        let prefix = nsBody.substring(with: match.range(at: 1))
        let suffix = nsBody.substring(with: match.range(at: 3))
        lines[line] = prefix + (checked ? "x" : " ") + suffix + (hadCR ? "\r" : "")
        return lines.joined(separator: "\n")
    }
}
