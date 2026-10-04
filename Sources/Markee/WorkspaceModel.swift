import Foundation
import MarkeeKit

/// Owns the workspace root and the indexes derived from it (file tree, the
/// `.md` name → URL map used by the file sidebar / search / wiki-links).
/// Pure inference helpers are `static` so they unit-test without an instance.
@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var root: URL
    @Published private(set) var fileTree: [FileNode] = []
    /// Ids of the expanded folders in the file tree. Folders start collapsed (a
    /// messy Downloads folder fully expanded is unnavigable); the open file's
    /// folders are revealed. Lives here so it survives sidebar-mode switches.
    @Published var expandedFolders: Set<String> = []
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
    ///
    /// The walk never reaches the home folder, any ancestor of it, or `/`: the
    /// root is the `markee-doc://` serving boundary and the enumeration scope,
    /// so a dotfiles `~/.git` (or a few notes in `~`) must not widen it to the
    /// whole home tree. Those cases fall back to the file's own directory.
    /// `nonisolated` (pure, no main-actor state) so tests and `init` can call it.
    nonisolated static func inferRoot(
        for file: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let start = file.deletingLastPathComponent().standardizedFileURL
        let fm = FileManager.default
        let homePath = home.standardizedFileURL.path

        // Candidate roots, nearest first, stopping before a forbidden one.
        var candidates: [URL] = []
        var dir = start
        while !isForbiddenRoot(dir.path, homePath: homePath) {
            candidates.append(dir)
            // Standardize so the filesystem root terminates the walk: Foundation's
            // URL("/").deletingLastPathComponent() yields "/..", which the bare
            // path-equality guard never catches — standardizing collapses it to "/".
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { break }
            dir = parent
        }

        if let git = candidates.first(where: { fm.fileExists(atPath: $0.appendingPathComponent(".git").path) }) {
            return git
        }
        if let docs = candidates.first(where: { markdownCount(in: $0, fm: fm) > 1 }) {
            return docs
        }
        return start
    }

    /// `/`, the home folder, and every ancestor of home are never inferred.
    nonisolated static func isForbiddenRoot(_ path: String, homePath: String) -> Bool {
        path == "/" || path == homePath || homePath.hasPrefix(path.hasSuffix("/") ? path : path + "/")
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
            return "\(scheme)://doc/\(encodePath(rel))/"
        }
        // Document outside root: unreachable via inference or Open Folder (which
        // rejects folders not containing the document); bare base as a fallback.
        return "\(scheme)://doc/"
    }

    /// Percent-encode each component of a root-relative path for a
    /// `markee-doc://` URL, so `#`, `?` and `%` in names (`C# notes/`) don't
    /// truncate or corrupt it.
    nonisolated static func encodePath(_ relative: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/;")
        return relative.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "/")
    }

    /// Drops the previous root's indexes immediately so nothing (wiki-links,
    /// search) resolves against them while the new walk runs.
    func setRoot(_ url: URL) {
        self.root = url.standardizedFileURL
        markdownFiles = []
        wikiIndex = [:]
        fileTree = []
        expandedFolders = []
        rebuild()
    }

    /// Re-enumerate the workspace off-main, then publish on main. Safe to call
    /// repeatedly (Files tab shown, palette opened, Open Folder). A result whose
    /// root no longer matches is dropped.
    func rebuild() {
        // Coalesce: while a walk is in flight, just note that another is wanted.
        guard !rebuildInFlight else { rebuildPending = true; return }
        rebuildInFlight = true
        let root = self.root
        enumerationQueue.async { [weak self] in
            let r = WorkspaceModel.enumerate(root: root)
            DispatchQueue.main.async {
                guard let self else { return }
                self.rebuildInFlight = false
                if self.root.standardizedFileURL == root.standardizedFileURL {
                    self.markdownFiles = r.files
                    self.wikiIndex = r.wikiIndex
                    self.fileTree = r.tree
                    self.onIndexUpdated?()
                }
                if self.rebuildPending {
                    self.rebuildPending = false
                    self.rebuild()
                }
            }
        }
    }
    private var rebuildInFlight = false
    private var rebuildPending = false

    /// Dependency/build directories that hold no docs worth indexing. (Hidden
    /// directories — `.git`, `.venv`, … — are already skipped.)
    nonisolated static let skippedDirectories: Set<String> = [
        "node_modules", "bower_components", ".build", "build", "dist", "DerivedData", ".next",
        "Pods", "Carthage", "target", "vendor", "venv", "__pycache__", "site-packages",
    ]
    /// Bounds on one walk, so an unexpectedly large root can't stall the index.
    nonisolated static let maxDepth = 12
    nonisolated static let maxFiles = 5000

    /// Pure walk: every `.md` under `root` (heavy build dirs skipped, bounded by
    /// `maxDepth`/`maxFiles`), the `stem → markee-doc:// url` index, and the
    /// file tree. `nonisolated` so it runs on the enumeration queue and is
    /// unit-testable.
    ///
    /// A forbidden root (home, its ancestors, `/` — reachable only for a file
    /// sitting directly in one of them) is walked one level deep, never recursively.
    nonisolated static func enumerate(
        root: URL,
        maxFiles: Int = maxFiles,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> WorkspaceIndex {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        let depthLimit = isForbiddenRoot(rootPath, homePath: home.standardizedFileURL.path) ? 1 : maxDepth
        var files: [URL] = []
        var index: [String: String] = [:]
        if let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in en {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    if skippedDirectories.contains(url.lastPathComponent) || en.level >= depthLimit {
                        en.skipDescendants()
                    }
                    continue
                }
                if files.count >= maxFiles { break }
                guard isMarkdown(url) else { continue }
                files.append(url.standardizedFileURL)
            }
        }
        let sorted = files.sorted { $0.path < $1.path }
        // Same-stem files (`docs/readme.md` vs `docs/api/readme.md`): the
        // shallowest wins, ties broken by path — independent of walk order.
        let byDepth = sorted.sorted {
            let (a, b) = ($0.pathComponents.count, $1.pathComponents.count)
            return a != b ? a < b : $0.path < $1.path
        }
        for file in byDepth where file.path.hasPrefix(rootPath + "/") {
            let stem = file.deletingPathExtension().lastPathComponent.lowercased()
            guard index[stem] == nil else { continue }
            let rel = String(file.path.dropFirst(rootPath.count + 1))
            index[stem] = "\(DocSchemeHandler.scheme)://doc/\(encodePath(rel))"
        }
        return WorkspaceIndex(files: sorted, wikiIndex: index,
                              tree: buildTree(root: root, files: sorted))
    }

    /// Build a folder/file tree containing only the directories that lead to a
    /// markdown file. Folders sort before files; both alphabetical. Recurses by
    /// grouping files on their next path component under `dir`.
    nonisolated static func buildTree(root: URL, files: [URL]) -> [FileNode] {
        childrenOf(dir: root.standardizedFileURL, files: files.map { $0.standardizedFileURL })
    }

    /// Ids of the folder nodes between `root` and `file` (outermost first): the
    /// only folders the file tree expands on its own. Empty for a file at the
    /// root or outside it.
    nonisolated static func folderIDsRevealing(_ file: URL, root: URL) -> [String] {
        let rootPath = root.standardizedFileURL.path
        var ids: [String] = []
        var dir = file.standardizedFileURL.deletingLastPathComponent()
        while dir.path.hasPrefix(rootPath + "/") {
            ids.insert(dir.path, at: 0)
            dir = dir.deletingLastPathComponent()
        }
        return ids
    }

    /// Every folder node's id in `tree`, at any depth (Expand All).
    nonisolated static func allFolderIDs(in tree: [FileNode]) -> Set<String> {
        var ids: Set<String> = []
        for node in tree where node.isDirectory {
            ids.insert(node.id)
            ids.formUnion(allFolderIDs(in: node.children))
        }
        return ids
    }

    /// The tree flattened to the rows currently on display (pre-order, with
    /// depth), skipping collapsed folders' subtrees. The sidebar renders this
    /// in one LazyVStack so only on-screen rows are built: nesting row views
    /// built an expanded folder's whole subtree eagerly, freezing Expand All
    /// on large folders.
    nonisolated static func visibleRows(_ tree: [FileNode], expanded: Set<String>) -> [FileTreeItem] {
        var rows: [FileTreeItem] = []
        func visit(_ nodes: [FileNode], depth: Int) {
            for node in nodes {
                rows.append(FileTreeItem(node: node, depth: depth))
                if node.isDirectory && expanded.contains(node.id) { visit(node.children, depth: depth + 1) }
            }
        }
        visit(tree, depth: 0)
        return rows
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

/// One visible row of the flattened file tree.
struct FileTreeItem: Identifiable {
    let node: FileNode
    let depth: Int
    var id: String { node.id }
}

/// One node in the workspace file tree.
struct FileNode: Identifiable, Hashable {
    let id: String          // absolute path
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]
}
