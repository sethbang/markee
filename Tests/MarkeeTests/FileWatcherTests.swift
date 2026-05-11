import XCTest
@testable import Markee

final class FileWatcherTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MarkeeFileWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    /// Watcher fires when the file is written to in place.
    func test_inPlaceWriteFiresCallback() throws {
        let file = tempDir.appendingPathComponent("a.md")
        try "initial\n".write(to: file, atomically: false, encoding: .utf8)

        let expectation = XCTestExpectation(description: "in-place write triggers callback")
        let watcher = FileWatcher(url: file) {
            expectation.fulfill()
        }
        defer { watcher.cancel() }

        // Give FileWatcher time to attach
        usleep(50_000)

        let fd = open(file.path, O_WRONLY | O_APPEND)
        XCTAssertGreaterThanOrEqual(fd, 0)
        let payload = "more\n"
        payload.withCString { ptr in
            _ = write(fd, ptr, strlen(ptr))
        }
        close(fd)

        wait(for: [expectation], timeout: 2.0)
    }

    /// Atomic-save pattern: write to a temp file, rename it over the target.
    /// The watcher must re-attach to the new inode and fire afterward.
    func test_atomicRenameFiresCallbackAfterReattach() throws {
        let file = tempDir.appendingPathComponent("b.md")
        try "v1\n".write(to: file, atomically: false, encoding: .utf8)

        let expectation = XCTestExpectation(description: "atomic save triggers callback")
        expectation.assertForOverFulfill = false
        let watcher = FileWatcher(url: file) {
            expectation.fulfill()
        }
        defer { watcher.cancel() }

        usleep(50_000)

        // Atomic save: write to temp, rename over the target
        let tmp = tempDir.appendingPathComponent("b.md.tmp")
        try "v2\n".write(to: tmp, atomically: false, encoding: .utf8)
        var resulting: NSURL? = nil
        try FileManager.default.replaceItem(
            at: file, withItemAt: tmp,
            backupItemName: nil, options: [], resultingItemURL: &resulting
        )

        wait(for: [expectation], timeout: 2.0)
    }

    /// Delete the file, recreate at the same path — the watcher should re-attach
    /// and fire on the new file's creation.
    func test_deleteThenRecreateFires() throws {
        let file = tempDir.appendingPathComponent("c.md")
        try "v1\n".write(to: file, atomically: false, encoding: .utf8)

        let expectation = XCTestExpectation(description: "recreate triggers callback")
        expectation.assertForOverFulfill = false
        let watcher = FileWatcher(url: file) {
            expectation.fulfill()
        }
        defer { watcher.cancel() }

        usleep(50_000)

        try FileManager.default.removeItem(at: file)
        // Wait long enough for the watcher's first re-attach retry (~150ms)
        usleep(250_000)
        try "v2\n".write(to: file, atomically: false, encoding: .utf8)

        wait(for: [expectation], timeout: 3.0)
    }

    /// Cancel must be safe to call multiple times and after deinit.
    func test_cancelIsIdempotent() throws {
        let file = tempDir.appendingPathComponent("d.md")
        try "v1\n".write(to: file, atomically: false, encoding: .utf8)
        let watcher = FileWatcher(url: file, onChange: {})
        watcher.cancel()
        watcher.cancel()
    }
}
