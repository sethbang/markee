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

    /// Rank candidates for `query`. Filename matches (on the stem, so "md" or
    /// "mark" doesn't hit every file) score above body matches; results are
    /// capped at `limit`. Empty/whitespace query → no results.
    static func rank(query: String, candidates: [Candidate], limit: Int) -> [Result] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var out: [Result] = []
        for c in candidates {
            let nameHit = (c.name as NSString).deletingPathExtension.lowercased().contains(q)
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

    /// At most this many files are read per query (the first N in path order);
    /// beyond that a workspace is too large for read-everything search.
    static let maxFilesRead = 2000

    /// Read up to `maxFilesRead` files and rank against `query`. Bodies are
    /// cached by modification date, so typing doesn't re-read the workspace on
    /// every keystroke.
    static func search(query: String, files: [URL], limit: Int = 50) -> [Result] {
        let candidates: [Candidate] = files.prefix(maxFilesRead).compactMap { url in
            guard let body = bodyCache.body(for: url) else { return nil }
            return Candidate(url: url, name: url.lastPathComponent, body: body)
        }
        return rank(query: query, candidates: candidates, limit: limit)
    }

    private static let bodyCache = BodyCache()
}

/// File bodies keyed by URL, invalidated by content-modification date.
private final class BodyCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [URL: (modified: Date, body: String)] = [:]

    func body(for url: URL) -> String? {
        // FileManager, not URL.resourceValues: the latter caches on the URL
        // instance, and the same URLs are reused across queries.
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate]
            as? Date ?? .distantPast
        lock.lock()
        let cached = entries[url]
        lock.unlock()
        if let cached, cached.modified == modified { return cached.body }
        guard let body = try? readFileWithFallback(at: url) else { return nil }
        lock.lock()
        entries[url] = (modified, body)
        lock.unlock()
        return body
    }
}
