import Foundation
import MarkeeKit

/// Full-text workspace search. `rank` is pure and tested; `search` reads files
/// off the main actor and applies it.
enum WorkspaceSearch {
    struct Candidate { let url: URL; let name: String; let body: String }
    struct Result: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let name: String
        let snippet: String
        let score: Int
    }

    /// Rank candidates for `query`. Filename matches score above body matches;
    /// results are capped at `limit`. Empty/whitespace query → no results.
    static func rank(query: String, candidates: [Candidate], limit: Int) -> [Result] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var out: [Result] = []
        for c in candidates {
            let nameHit = c.name.lowercased().contains(q)
            let bodyLines = c.body.split(separator: "\n", omittingEmptySubsequences: false)
            var bodyHitLine: Substring? = nil
            for line in bodyLines where line.lowercased().contains(q) { bodyHitLine = line; break }
            guard nameHit || bodyHitLine != nil else { continue }
            let score = (nameHit ? 100 : 0) + (bodyHitLine != nil ? 10 : 0)
            let snippet = bodyHitLine.map { String($0).trimmingCharacters(in: .whitespaces) }
                ?? c.name
            out.append(Result(url: c.url, name: c.name,
                              snippet: String(snippet.prefix(140)), score: score))
        }
        return Array(out.sorted {
            $0.score != $1.score ? $0.score > $1.score
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.prefix(limit))
    }

    /// Read every file in `files` (capped) and rank against `query`.
    static func search(query: String, files: [URL], limit: Int = 50) -> [Result] {
        let capped = files.prefix(2000)
        let candidates: [Candidate] = capped.compactMap { url in
            guard let body = try? readFileWithFallback(at: url) else { return nil }
            return Candidate(url: url, name: url.lastPathComponent, body: body)
        }
        return rank(query: query, candidates: candidates, limit: limit)
    }
}
