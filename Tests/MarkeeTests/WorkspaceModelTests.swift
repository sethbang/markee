import XCTest
@testable import Markee

final class WorkspaceModelTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ws-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }
    private func touch(_ rel: String) throws -> URL {
        let u = tmp.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: u)
        return u
    }

    func test_inferRoot_prefersGitRoot() throws {
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let doc = try touch("docs/guide.md")
        let root = WorkspaceModel.inferRoot(for: doc)
        XCTAssertEqual(root.standardizedFileURL.path, tmp.standardizedFileURL.path)
    }

    func test_inferRoot_nearestAncestorWithMultipleMarkdown() throws {
        let doc = try touch("notes/a.md")
        _ = try touch("notes/b.md")
        let root = WorkspaceModel.inferRoot(for: doc)
        XCTAssertEqual(root.standardizedFileURL.path,
                       tmp.appendingPathComponent("notes").standardizedFileURL.path)
    }

    func test_inferRoot_singleFileFallsBackToOwnDir() throws {
        let doc = try touch("lonely/only.md")
        let root = WorkspaceModel.inferRoot(for: doc)
        XCTAssertEqual(root.standardizedFileURL.path,
                       tmp.appendingPathComponent("lonely").standardizedFileURL.path)
    }

    func test_docBase_atRoot_isBare() {
        let root = URL(fileURLWithPath: "/repo")
        XCTAssertEqual(WorkspaceModel.docBase(for: URL(fileURLWithPath: "/repo/README.md"), root: root),
                       "markee-doc://doc/")
    }

    func test_docBase_inSubdir_isRootRelative() {
        let root = URL(fileURLWithPath: "/repo")
        XCTAssertEqual(WorkspaceModel.docBase(for: URL(fileURLWithPath: "/repo/docs/api/ref.md"), root: root),
                       "markee-doc://doc/docs/api/")
    }

    func test_enumerate_indexesMarkdownSkipsHeavyDirsBuildsTree() throws {
        _ = try touch("docs/guide.md")
        _ = try touch("docs/api/ref.md")
        _ = try touch("README.md")
        _ = try touch("docs/logo.png")               // non-markdown ignored
        _ = try touch("node_modules/pkg/readme.md")  // heavy dir → skipped
        let root = tmp.standardizedFileURL

        let r = WorkspaceModel.enumerate(root: root)
        XCTAssertEqual(r.files.count, 3)             // node_modules excluded
        XCTAssertEqual(r.wikiIndex["ref"], "markee-doc://doc/docs/api/ref.md")
        XCTAssertEqual(r.wikiIndex["readme"], "markee-doc://doc/README.md")
        // Tree top level: docs/ before README.md (folders first, alphabetical)
        XCTAssertEqual(r.tree.first?.name, "docs")
        XCTAssertTrue(r.tree.first?.isDirectory ?? false)
    }
}
