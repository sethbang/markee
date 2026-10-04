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

    func test_pathsWithURLMetacharactersArePercentEncoded() throws {
        _ = try touch("C# notes/50% off?.md")
        let r = WorkspaceModel.enumerate(root: tmp.standardizedFileURL)
        let href = try XCTUnwrap(r.wikiIndex["50% off?"])
        XCTAssertEqual(href, "markee-doc://doc/C%23%20notes/50%25%20off%3F.md")
        XCTAssertEqual(URL(string: href)?.path, "/C# notes/50% off?.md")
        XCTAssertEqual(WorkspaceModel.docBase(for: URL(fileURLWithPath: "/repo/C# notes/x.md"),
                                              root: URL(fileURLWithPath: "/repo")),
                       "markee-doc://doc/C%23%20notes/")
    }

    func test_sameStemResolvesToShallowestFile() throws {
        _ = try touch("docs/api/readme.md")
        _ = try touch("docs/readme.md")
        _ = try touch("z/readme.md")
        let r = WorkspaceModel.enumerate(root: tmp.standardizedFileURL)
        XCTAssertEqual(r.wikiIndex["readme"], "markee-doc://doc/docs/readme.md")
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

    /// The file tree starts collapsed except for the open file's folders, and
    /// those ids must match the directory nodes `buildTree` produces.
    func test_revealedFolderIDsMatchTreeNodesOfTheOpenFile() throws {
        let file = try touch("docs/api/ref.md")
        _ = try touch("other/x.md")
        let root = tmp.standardizedFileURL
        let tree = WorkspaceModel.buildTree(root: root, files: [file, root.appendingPathComponent("other/x.md")])
        let docs = try XCTUnwrap(tree.first { $0.name == "docs" })
        let api = try XCTUnwrap(docs.children.first { $0.name == "api" })

        let ids = WorkspaceModel.folderIDsRevealing(file, root: root)
        XCTAssertEqual(ids, [docs.id, api.id])
        XCTAssertTrue(WorkspaceModel.folderIDsRevealing(root.appendingPathComponent("top.md"), root: root).isEmpty)
        XCTAssertTrue(WorkspaceModel.folderIDsRevealing(URL(fileURLWithPath: "/elsewhere/a/b.md"), root: root).isEmpty)
    }

    func test_allFolderIDsCollectsEveryNestedFolder() throws {
        let root = tmp.standardizedFileURL
        let files = ["a/b/c/x.md", "a/y.md", "d/z.md", "top.md"].map { root.appendingPathComponent($0) }
        let ids = WorkspaceModel.allFolderIDs(in: WorkspaceModel.buildTree(root: root, files: files))
        XCTAssertEqual(ids, Set(["a", "a/b", "a/b/c", "d"].map { root.appendingPathComponent($0).path }))
    }

    /// The sidebar renders this flat list lazily; collapsed folders' subtrees
    /// are never visited.
    func test_visibleRowsFlattenOnlyExpandedFolders() throws {
        let root = tmp.standardizedFileURL
        let files = ["a/b/x.md", "a/y.md", "d/z.md", "top.md"].map { root.appendingPathComponent($0) }
        let tree = WorkspaceModel.buildTree(root: root, files: files)
        let a = root.appendingPathComponent("a").path

        let collapsed = WorkspaceModel.visibleRows(tree, expanded: [])
        XCTAssertEqual(collapsed.map(\.node.name), ["a", "d", "top.md"])
        XCTAssertEqual(collapsed.map(\.depth), [0, 0, 0])

        let open = WorkspaceModel.visibleRows(tree, expanded: [a])
        XCTAssertEqual(open.map(\.node.name), ["a", "b", "y.md", "d", "top.md"])
        XCTAssertEqual(open.map(\.depth), [0, 1, 1, 0, 0])

        let all = WorkspaceModel.visibleRows(tree, expanded: WorkspaceModel.allFolderIDs(in: tree))
        XCTAssertEqual(all.map(\.node.name), ["a", "b", "x.md", "y.md", "d", "z.md", "top.md"])
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
    }

    @MainActor
    func test_changingRootCollapsesTheTree() throws {
        let file = try touch("a/doc.md")
        let model = WorkspaceModel(documentURL: file)
        model.expandedFolders = ["/somewhere"]
        model.setRoot(tmp)
        XCTAssertTrue(model.expandedFolders.isEmpty)
    }
}

final class WorkspaceRootBoundTests: XCTestCase {
    private var tmp: URL!
    private var home: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wsb-" + UUID().uuidString).standardizedFileURL
        home = tmp.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }
    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    /// A dotfiles repo at ~ must not make the whole home tree the workspace.
    func test_homeGitRepoIsNeverTheRoot() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let doc = home.appendingPathComponent("Downloads/x/readme.md")
        try touch(doc)
        XCTAssertEqual(WorkspaceModel.inferRoot(for: doc, home: home).path,
                       home.appendingPathComponent("Downloads/x").path)
    }

    func test_homeWithSeveralNotesIsNeverTheRoot() throws {
        try touch(home.appendingPathComponent("a.md"))
        try touch(home.appendingPathComponent("b.md"))
        let doc = home.appendingPathComponent("sub/only.md")
        try touch(doc)
        XCTAssertEqual(WorkspaceModel.inferRoot(for: doc, home: home).path,
                       home.appendingPathComponent("sub").path)
    }

    func test_fileDirectlyInHomeFallsBackToHomeItself() throws {
        let doc = home.appendingPathComponent("note.md")
        try touch(doc)
        XCTAssertEqual(WorkspaceModel.inferRoot(for: doc, home: home).path, home.path)
    }

    func test_repoInsideHomeIsStillFound() throws {
        let repo = home.appendingPathComponent("Code/proj")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let doc = repo.appendingPathComponent("docs/guide.md")
        try touch(doc)
        XCTAssertEqual(WorkspaceModel.inferRoot(for: doc, home: home).path, repo.path)
    }

    func test_forbiddenRootIsEnumeratedShallowly() throws {
        try touch(home.appendingPathComponent("top.md"))
        try touch(home.appendingPathComponent("Documents/deep.md"))
        let r = WorkspaceModel.enumerate(root: home, home: home)
        XCTAssertEqual(r.files.map(\.lastPathComponent), ["top.md"])
    }

    func test_forbiddenRoots() {
        XCTAssertTrue(WorkspaceModel.isForbiddenRoot("/", homePath: "/Users/me"))
        XCTAssertTrue(WorkspaceModel.isForbiddenRoot("/Users", homePath: "/Users/me"))
        XCTAssertTrue(WorkspaceModel.isForbiddenRoot("/Users/me", homePath: "/Users/me"))
        XCTAssertFalse(WorkspaceModel.isForbiddenRoot("/Users/me/Code", homePath: "/Users/me"))
        XCTAssertFalse(WorkspaceModel.isForbiddenRoot("/Users/mex", homePath: "/Users/me"))
        XCTAssertFalse(WorkspaceModel.isForbiddenRoot("/Volumes/Docs", homePath: "/Users/me"))
    }

    func test_enumerateHonorsFileCapAndSkipSet() throws {
        for i in 0..<5 { try touch(tmp.appendingPathComponent("w/n\(i).md")) }
        try touch(tmp.appendingPathComponent("w/Pods/x/readme.md"))
        try touch(tmp.appendingPathComponent("w/target/doc.md"))
        let root = tmp.appendingPathComponent("w")
        XCTAssertEqual(WorkspaceModel.enumerate(root: root).files.count, 5)
        XCTAssertEqual(WorkspaceModel.enumerate(root: root, maxFiles: 3).files.count, 3)
    }
}
