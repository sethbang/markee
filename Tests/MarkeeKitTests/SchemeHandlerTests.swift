import XCTest
@testable import MarkeeKit

final class SchemeHandlerTests: XCTestCase {
    private var tempDir: URL!
    private var outsideDir: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MarkeeSchemeHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.tempDir = base.appendingPathComponent("docs")
        self.outsideDir = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let base = tempDir?.deletingLastPathComponent(),
           FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.removeItem(at: base)
        }
    }

    // MARK: - Legitimate access

    func test_legitimateFile_resolvesInsideRoot() throws {
        let file = tempDir.appendingPathComponent("image.png")
        try Data([1, 2, 3]).write(to: file)
        let resolved = resolveSandboxed(root: tempDir, requestPath: "/image.png")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.lastPathComponent, "image.png")
    }

    func test_nestedFile_resolves() throws {
        let nested = tempDir.appendingPathComponent("a/b/c.txt")
        try FileManager.default.createDirectory(
            at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: nested)
        let resolved = resolveSandboxed(root: tempDir, requestPath: "/a/b/c.txt")
        XCTAssertNotNil(resolved)
    }

    // MARK: - Path traversal

    func test_dotDotTraversal_returnsNil() {
        XCTAssertNil(resolveSandboxed(root: tempDir, requestPath: "/../outside/x"))
        XCTAssertNil(resolveSandboxed(root: tempDir, requestPath: "/a/../../outside/x"))
    }

    /// Callers pass `URL.path`, which decodes `%2e%2e` to `..` — use real URLs.
    func test_percentEncodedDotDotTraversal_returnsNil() {
        for s in ["markee-doc://doc/%2e%2e/outside/x", "markee-doc://doc/%2E%2E/outside/x",
                  "markee-doc://doc/a/%2e%2e%2f%2e%2e/outside/x"] {
            let path = URL(string: s)!.path
            XCTAssertNil(resolveSandboxed(root: tempDir, requestPath: path), s)
        }
    }

    func test_fileNameContainingLiteralPercentResolves() throws {
        try Data().write(to: tempDir.appendingPathComponent("100% done.png"))
        let path = URL(string: "markee-doc://doc/100%25%20done.png")!.path
        XCTAssertEqual(resolveSandboxed(root: tempDir, requestPath: path)?.lastPathComponent, "100% done.png")
    }

    func test_symlinkedDirectoryPointingOutside_returnsNil() throws {
        try Data().write(to: outsideDir.appendingPathComponent("x.txt"))
        try FileManager.default.createSymbolicLink(
            at: tempDir.appendingPathComponent("escape"), withDestinationURL: outsideDir)
        XCTAssertNil(resolveSandboxed(root: tempDir, requestPath: "/escape/x.txt"))
    }

    func test_rootReachedThroughSymlinkStillServesItsFiles() throws {
        try Data().write(to: tempDir.appendingPathComponent("a.png"))
        let linkRoot = outsideDir.appendingPathComponent("docs-link")
        try FileManager.default.createSymbolicLink(at: linkRoot, withDestinationURL: tempDir)
        XCTAssertNotNil(resolveSandboxed(root: linkRoot, requestPath: "/a.png"))
    }

    func test_rootRequest_resolvesToRootItself() {
        // Asking for the root with an empty path should be permitted (it'll
        // 404 later when serve() can't read a directory, but it isn't an
        // escape).
        let resolved = resolveSandboxed(root: tempDir, requestPath: "/")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.path, tempDir.resolvingSymlinksInPath().path)
    }

    // MARK: - Symlink escape

    func test_symlinkPointingOutsideRoot_returnsNil() throws {
        // Create a real file outside the doc root, then a symlink inside the
        // doc root pointing at it. Before the fix this resolved to the
        // outside file and got served.
        let secret = outsideDir.appendingPathComponent("secret.txt")
        try Data("leaked".utf8).write(to: secret)

        let symlink = tempDir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: secret)

        XCTAssertNil(resolveSandboxed(root: tempDir, requestPath: "/link.txt"))
    }

    /// `resolvingSymlinksInPath` leaves the last component unresolved when the
    /// path holds `..`, so `x/../link.txt` slipped past the check. WebKit keeps
    /// `%2F` encoded and `URL.path` decodes it, so a document can send this.
    func test_outwardSymlinkBehindDotDotSegment_returnsNil() throws {
        try Data("leaked".utf8).write(to: outsideDir.appendingPathComponent("secret.txt"))
        try FileManager.default.createSymbolicLink(
            at: tempDir.appendingPathComponent("link.txt"),
            withDestinationURL: outsideDir.appendingPathComponent("secret.txt"))
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: tempDir.appendingPathComponent("dirlink"), withDestinationURL: tempDir.appendingPathComponent("sub"))
        for s in ["markee-doc://doc/x%2F..%2Flink.txt", "markee-doc://doc/sub%2F..%2Flink.txt",
                  "markee-doc://doc/dirlink%2F..%2Flink.txt"] {
            let path = URL(string: s)!.path
            XCTAssertNil(resolveSandboxed(root: tempDir, requestPath: path), s)
        }
    }

    func test_symlinkPointingInsideRoot_resolves() throws {
        let real = tempDir.appendingPathComponent("inside.txt")
        try Data().write(to: real)
        let symlink = tempDir.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: real)

        XCTAssertNotNil(resolveSandboxed(root: tempDir, requestPath: "/alias.txt"))
    }

    // MARK: - Boundary attack

    func test_siblingDirectoryWithRootAsPrefix_returnsNil() throws {
        // If docRoot is `/.../docs`, a request resolving to `/.../docs_secret`
        // would pass a naive hasPrefix check but not the boundary-aware one.
        let sibling = tempDir.deletingLastPathComponent().appendingPathComponent("docs_secret")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let prize = sibling.appendingPathComponent("prize.txt")
        try Data().write(to: prize)

        // Construct a path that resolves to the sibling via ../docs_secret.
        XCTAssertNil(resolveSandboxed(root: tempDir, requestPath: "/../docs_secret/prize.txt"))
    }
}
