import XCTest
@testable import Markee

/// The live FileWatcher behind a PreviewController (no WebKit page needed):
/// which disk changes count toward the "re-renders watched" stat.
@MainActor
final class QuickEditWatcherTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MarkeeQuickEditWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private var rerenders: Int { UsageTracker.shared.stats.rerendersWatched }

    private func send(_ controller: PreviewController, _ body: [String: Any]) {
        controller.receiveBridgeMessage(name: "markee", isMainFrame: true,
                                        frameURL: URL(string: "markee-app://app/template.html"), body: body)
    }

    /// Long enough for an atomic save's reattach (0.15 s) and any second event.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(900))
    }

    private func makeController(_ text: String) async throws -> (PreviewController, URL) {
        let file = tempDir.appendingPathComponent("doc.md")
        try Data(text.utf8).write(to: file)
        let controller = PreviewController(fileURL: file)
        await settle()           // watcher attached, initial events drained
        return (controller, file)
    }

    func test_ownWriteDoesNotCountAsRerender() async throws {
        let (controller, file) = try await makeController("- [ ] a\n\nb\n")
        var rendered: [String] = []
        send(controller, ["kind": "ready"])
        controller.onJSCall = { fn, args in
            if fn == "render", let source = (args.first as? [String: Any])?["source"] as? String {
                rendered.append(source)
            }
        }
        let before = rerenders

        send(controller, ["kind": "taskToggle", "line": 0, "checked": true])
        await settle()
        XCTAssertEqual(rerenders, before, "task toggle's own write")
        XCTAssertEqual(rendered.last, "- [x] a\n\nb\n", "own write still re-renders")

        send(controller, ["kind": "editState", "open": true, "dirty": true, "focused": true])
        send(controller, ["kind": "blockEdit", "start": 2, "end": 3, "original": "b", "replacement": "c"])
        await settle()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "- [x] a\n\nc\n")
        XCTAssertEqual(rerenders, before, "Quick Edit's own write")

        try Data("outside\n".utf8).write(to: file, options: .atomic)
        await settle()
        XCTAssertEqual(rerenders, before + 1, "an outside save still counts")
        withExtendedLifetime(controller) {}
    }

    func test_rerenderNotCountedWhilePaused() async throws {
        let (controller, file) = try await makeController("a\n")
        let before = rerenders
        send(controller, ["kind": "editState", "open": true, "dirty": true, "focused": true])

        try Data("outside\n".utf8).write(to: file, options: .atomic)
        await settle()

        XCTAssertEqual(rerenders, before)
        withExtendedLifetime(controller) {}
    }

    /// A write Markee made in one document can't excuse an outside change to
    /// the next one from the "re-renders watched" count.
    func test_navigateForgetsTheLastSelfWrite() async throws {
        let (controller, a) = try await makeController("- [ ] t\n")
        let b = tempDir.appendingPathComponent("b.md")
        try Data("# B\n".utf8).write(to: b)
        send(controller, ["kind": "taskToggle", "line": 0, "checked": true])
        let written = try Data(contentsOf: a)
        controller.openFromTree(b)
        await settle()
        let before = rerenders

        try written.write(to: b, options: .atomic)
        await settle()

        XCTAssertEqual(rerenders, before + 1)
        withExtendedLifetime(controller) {}
    }
}
