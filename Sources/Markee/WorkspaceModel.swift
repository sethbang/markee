import Foundation
import MarkeeKit

/// Owns the workspace root and the indexes derived from it (file tree, the
/// `.md` name → URL map used by the file sidebar / search / wiki-links).
/// Pure inference helpers are `static` so they unit-test without an instance.
@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var root: URL
    @Published private(set) var fileTree: [FileNode] = []
    /// stem (lowercased filename, no extension) → resolvable markee-doc:// URL.
    private(set) var wikiIndex: [String: String] = [:]
    /// Every `.md`/`.markdown` file under root, absolute URLs, for search.
    private(set) var markdownFiles: [URL] = []

    private let enumerationQueue = DispatchQueue(label: "com.markee.workspace.enum", qos: .userInitiated)
    /// Called on the main thread after each (re)build assigns the @Published data.
    var onIndexUpdated: (() -> Void)?

    init(documentURL: URL) {
        self.root = WorkspaceModel.inferRoot(for: documentURL)
        rebuild()
    }

    /// Walk up: git root (nearest ancestor with `.git`) → nearest ancestor
    /// containing more than one `.md` → the file's own directory.
    /// `nonisolated` (pure, no main-actor state) so tests and `init` can call it.
    nonisolated static func inferRoot(for file: URL) -> URL {
        let start = file.deletingLastPathComponent().standardizedFileURL
        let fm = FileManager.default

        var dir = start
        while true {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            // Standardize so the filesystem root terminates the walk: Foundation's
            // URL("/").deletingLastPathComponent() yields "/..", which the bare
            // path-equality guard never catches — standardizing collapses it to "/".
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { break }
            dir = parent
        }

        dir = start
        while true {
            if markdownCount(in: dir, fm: fm) > 1 { return dir }
            // Standardize so the filesystem root terminates the walk: Foundation's
            // URL("/").deletingLastPathComponent() yields "/..", which the bare
            // path-equality guard never catches — standardizing collapses it to "/".
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { break }
            dir = parent
        }
        return start
    }

    nonisolated private static func markdownCount(in dir: URL, fm: FileManager) -> Int {
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { isMarkdown($0) }.count
    }

    nonisolated static func isMarkdown(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    /// `<base href>` for a document: `markee-doc://doc/<docDir-relative-to-root>/`.
    nonisolated static func docBase(for file: URL, root: URL) -> String {
        let dir = file.deletingLastPathComponent().standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        let scheme = DocSchemeHandler.scheme
        guard dir != rootPath else { return "\(scheme)://doc/" }
        if dir.hasPrefix(rootPath + "/") {
            let rel = String(dir.dropFirst(rootPath.count + 1))
            return "\(scheme)://doc/\(rel)/"
        }
        // Document outside root (shouldn't happen — root is an ancestor): bare.
        return "\(scheme)://doc/"
    }

    func setRoot(_ url: URL) {
        self.root = url.standardizedFileURL
        rebuild()
    }

    /// Re-enumerate the workspace off-main, then publish on main. Safe to call
    /// repeatedly (Files tab shown, palette opened, Open Folder). A result whose
    /// root no longer matches is dropped.
    func rebuild() {
        let root = self.root
        enumerationQueue.async { [weak self] in
            let r = WorkspaceModel.enumerate(root: root)
            DispatchQueue.main.async {
                guard let self, self.root.standardizedFileURL == root.standardizedFileURL else { return }
                self.markdownFiles = r.files
                self.wikiIndex = r.wikiIndex
                self.fileTree = r.tree
                self.onIndexUpdated?()
            }
        }
    }

    /// Pure walk: every `.md` under `root` (heavy build dirs skipped), the
    /// `stem → markee-doc:// url` index, and the file tree. `nonisolated` so it
    /// runs on the enumeration queue and is unit-testable.
    nonisolated static func enumerate(root: URL) -> WorkspaceIndex {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        let skip: Set<String> = ["node_modules", ".build", "build", "dist", "DerivedData", ".next", ".git"]
        var files: [URL] = []
        var index: [String: String] = [:]
        if let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in en {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    if skip.contains(url.lastPathComponent) { en.skipDescendants() }
                    continue
                }
                guard isMarkdown(url) else { continue }
                let std = url.standardizedFileURL
                files.append(std)
                guard std.path.hasPrefix(rootPath + "/") else { continue }
                let rel = String(std.path.dropFirst(rootPath.count + 1))
                let stem = std.deletingPathExtension().lastPathComponent.lowercased()
                // First writer wins; same-stem ambiguity is rare in doc repos.
                if index[stem] == nil { index[stem] = "\(DocSchemeHandler.scheme)://doc/\(rel)" }
            }
        }
        let sorted = files.sorted { $0.path < $1.path }
        return WorkspaceIndex(files: sorted, wikiIndex: index,
                              tree: buildTree(root: root, files: sorted))
    }

    /// Build a folder/file tree containing only the directories that lead to a
    /// markdown file. Folders sort before files; both alphabetical. Recurses by
    /// grouping files on their next path component under `dir`.
    nonisolated static func buildTree(root: URL, files: [URL]) -> [FileNode] {
        childrenOf(dir: root.standardizedFileURL, files: files.map { $0.standardizedFileURL })
    }

    nonisolated private static func childrenOf(dir: URL, files: [URL]) -> [FileNode] {
        let prefix = dir.path + "/"
        let under = files.filter { $0.path.hasPrefix(prefix) }
        var fileNodes: [FileNode] = []
        var subdirNames: Set<String> = []
        for f in under {
            let rest = String(f.path.dropFirst(prefix.count))
            if let slash = rest.firstIndex(of: "/") {
                subdirNames.insert(String(rest[rest.startIndex..<slash]))
            } else {
                fileNodes.append(FileNode(id: f.path, name: rest, url: f,
                                          isDirectory: false, children: []))
            }
        }
        let dirNodes: [FileNode] = subdirNames.map { name in
            let sub = dir.appendingPathComponent(name)
            return FileNode(id: sub.path, name: name, url: sub, isDirectory: true,
                            children: childrenOf(dir: sub, files: under))
        }
        let dirs = dirNodes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let fs = fileNodes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return dirs + fs   // folders before files
    }
}

/// The three derived indexes a single workspace walk produces.
struct WorkspaceIndex {
    let files: [URL]
    let wikiIndex: [String: String]
    let tree: [FileNode]
}

/// One node in the workspace file tree.
struct FileNode: Identifiable, Hashable {
    let id: String          // absolute path
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]
}
