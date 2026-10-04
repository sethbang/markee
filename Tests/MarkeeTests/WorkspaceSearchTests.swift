import XCTest
@testable import Markee

final class WorkspaceSearchTests: XCTestCase {
    private func u(_ s: String) -> URL { URL(fileURLWithPath: s) }

    func test_ranking_boostsFilenameMatchesAboveBodyMatches() {
        let candidates = [
            WorkspaceSearch.Candidate(url: u("/w/guide.md"), name: "guide.md",
                                      body: "nothing relevant here"),
            WorkspaceSearch.Candidate(url: u("/w/install.md"), name: "install.md",
                                      body: "run make to build"),
            WorkspaceSearch.Candidate(url: u("/w/notes.md"), name: "notes.md",
                                      body: "the install step matters"),
        ]
        let results = WorkspaceSearch.rank(query: "install", candidates: candidates, limit: 10)
        XCTAssertEqual(results.first?.url, u("/w/install.md"))   // filename match wins
        XCTAssertEqual(results.count, 2)                          // guide.md excluded
        XCTAssertEqual(results.last?.url, u("/w/notes.md"))       // body-only match last
    }

    func test_ranking_snippetIncludesMatch() {
        let c = [WorkspaceSearch.Candidate(url: u("/w/a.md"), name: "a.md",
                 body: "line one\nthe needle is here\nline three")]
        let r = WorkspaceSearch.rank(query: "needle", candidates: c, limit: 10)
        XCTAssertTrue(r.first?.snippet.contains("needle") ?? false)
    }

    func test_ranking_emptyQueryReturnsNothing() {
        let c = [WorkspaceSearch.Candidate(url: u("/w/a.md"), name: "a.md", body: "x")]
        XCTAssertTrue(WorkspaceSearch.rank(query: "  ", candidates: c, limit: 10).isEmpty)
    }

    func test_ranking_respectsLimit() {
        let c = (0..<20).map {
            WorkspaceSearch.Candidate(url: u("/w/\($0).md"), name: "\($0).md", body: "match")
        }
        XCTAssertEqual(WorkspaceSearch.rank(query: "match", candidates: c, limit: 5).count, 5)
    }

    func test_ranking_filenameMatchIgnoresExtension() {
        let c = [WorkspaceSearch.Candidate(url: u("/w/a.md"), name: "a.md", body: "x"),
                 WorkspaceSearch.Candidate(url: u("/w/markdown-tips.md"), name: "markdown-tips.md", body: "x")]
        XCTAssertTrue(WorkspaceSearch.rank(query: "md", candidates: c, limit: 10).isEmpty)
        XCTAssertEqual(WorkspaceSearch.rank(query: "mark", candidates: c, limit: 10).map(\.name), ["markdown-tips.md"])
    }

    func test_search_seesEditsAfterCaching() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("n.md")
        try "alpha".write(to: f, atomically: true, encoding: .utf8)
        XCTAssertEqual(WorkspaceSearch.search(query: "alpha", files: [f]).count, 1)
        try "beta".write(to: f, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: f.path)
        XCTAssertEqual(WorkspaceSearch.search(query: "beta", files: [f]).count, 1)
        XCTAssertEqual(WorkspaceSearch.search(query: "alpha", files: [f]).count, 0)
    }
}
