import SwiftUI
import WebKit
import UniformTypeIdentifiers
import MarkeeKit

/// Discrete zoom rungs, browser-style. Zoom commands only ever land the
/// page on one of these values.
let zoomSteps: [Double] = [0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

enum ZoomDirection {
    case `in`, out
}

/// Step `current` one rung along `zoomSteps`. Off-ladder inputs snap to the
/// nearest rung first; the result is clamped at the array bounds.
func nextZoom(from current: Double, direction: ZoomDirection) -> Double {
    let nearest = zoomSteps.indices.min(by: {
        abs(zoomSteps[$0] - current) < abs(zoomSteps[$1] - current)
    }) ?? 0
    switch direction {
    case .in:
        return zoomSteps[min(nearest + 1, zoomSteps.count - 1)]
    case .out:
        return zoomSteps[max(nearest - 1, 0)]
    }
}

struct OutlineEntry: Identifiable, Hashable {
    let id: String        // heading slug / anchor
    let level: Int        // 1..6
    let title: String
    let line: Int?        // 0-indexed source line; nil if JS didn't supply one
}

@MainActor
final class PreviewController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    enum SidebarMode { case outline, files }
    @Published var sidebarMode: SidebarMode = .outline {
        didSet { if sidebarMode == .files { workspace.rebuild() } }   // refresh on show
    }

    @Published var outline: [OutlineEntry] = []
    @Published var errorBanner: String? = nil
    @Published var showOutline: Bool = false
    @Published var currentHeadingID: String? = nil
    @Published var showFindBar: Bool = false
    @Published var findQuery: String = ""
    @Published var findNotFound: Bool = false
    @Published var findCurrent: Int = 0
    @Published var findTotal: Int = 0   // -1 = total unknown (fallback path)
    @Published var pinState = WindowPinState()
    @Published var docWords: Int = 0
    @Published var docMinutes: Int = 0
    @Published var statsPillVisible: Bool = false
    private var statsHideWork: DispatchWorkItem?
    @Published var showSearchPalette: Bool = false
    @Published var searchQuery: String = "" { didSet { scheduleSearch() } }
    @Published var searchResults: [WorkspaceSearch.Result] = []
    private var searchWork: DispatchWorkItem?
    private let searchQueue = DispatchQueue(label: "com.markee.search", qos: .userInitiated)

    let webView: MarkeeWebView
    let bundleHandler: BundleSchemeHandler
    let docHandler: DocSchemeHandler

    @Published private(set) var fileURL: URL
    let workspace: WorkspaceModel
    private var watcher: FileWatcher?
    private var lastGoodSource: String = ""
    private var templateLoaded = false
    private var pendingRender: String?
    private var didApplyInitialPin = false
    private var indexPopulated = false
    // Applies pinState to the NSWindow; mutate pinState first, then call update.
    private lazy var pinController = WindowPinController(
        windowProvider: { [weak self] in self?.webView.window })

    /// - Parameter webRoot: override for the bundle's `web/` directory (tests
    ///   only — the xctest host bundle has none).
    init(fileURL: URL, webRoot: URL? = nil) {
        self.fileURL = fileURL
        self.bundleHandler = webRoot.map(BundleSchemeHandler.init(webRoot:)) ?? BundleSchemeHandler()
        self.workspace = WorkspaceModel(documentURL: fileURL)
        self.docHandler = DocSchemeHandler(docRoot: workspace.root)

        let config = WKWebViewConfiguration()
        let prefs = WKPreferences()
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pagePrefs
        config.preferences = prefs

        let userContent = WKUserContentController()
        config.userContentController = userContent

        // Register both scheme handlers BEFORE creating the webView
        config.setURLSchemeHandler(bundleHandler, forURLScheme: BundleSchemeHandler.scheme)
        config.setURLSchemeHandler(docHandler, forURLScheme: DocSchemeHandler.scheme)

        self.webView = MarkeeWebView(frame: .zero, configuration: config)
        self.history = NavigationHistory(initial: fileURL)
        super.init()

        if SettingsStore.shared.defaultFloatOnTop {
            self.pinState.floatOnTop = true
        }

        self.webView.controller = self
        self.workspace.onIndexUpdated = { [weak self] in self?.reRenderForIndexIfNeeded() }

        userContent.add(WeakScriptMessageHandler(target: self), name: "markee")
        self.webView.navigationDelegate = self
        self.webView.allowsBackForwardNavigationGestures = false

        loadTemplate()
        startWatching()
        loadFromDisk(reason: "initial")
        registerCommands()
        UsageTracker.shared.recordDocumentOpened(fileURL)
    }

    // MARK: - Menu command routing

    /// Menu commands are posted to every window over NotificationCenter; only
    /// the key window's controller acts, and that guard lives here once. The
    /// two `broadcasts` deliberately reach every window (each re-applies the
    /// shared zoom / settings to its own page).
    private func registerCommands() {
        let keyWindowCommands: [(Notification.Name, (PreviewController) -> Void)] = [
            (.toggleOutline, { $0.toggleOutline() }),
            (.exportHTML, { $0.exportHTML() }),
            (.exportPDF, { $0.exportPDF() }),
            (.printPreview, { $0.printPreview() }),
            (.openInEditor, { $0.openInEditor(atLine: $0.currentHeadingLine()) }),
            (.findInPreview, { $0.showFindBar = true }),
            (.findNext, { $0.findNextOrReveal(backwards: false) }),
            (.findPrevious, { $0.findNextOrReveal(backwards: true) }),
            (.zoomIn, { $0.changeZoom { nextZoom(from: $0, direction: .in) } }),
            (.zoomOut, { $0.changeZoom { nextZoom(from: $0, direction: .out) } }),
            (.zoomReset, { $0.changeZoom { _ in 1.0 } }),
            (.reloadFile, { $0.reload() }),
            (.copyMarkdownSource, { $0.copyMarkdownSource() }),
            (.copyReflowedMarkdown, { $0.copyReflowedMarkdown() }),
            (.copyRenderedText, { $0.copyRenderedText() }),
            (.revealInFinder, { $0.revealInFinder() }),
            (.toggleFloatOnTop, { $0.updatePin { $0.toggleFloatOnTop() } }),
            (.toggleAllSpaces, { $0.updatePin { $0.toggleAllSpaces() } }),
            (.toggleFollowActive, { $0.updatePin { $0.toggleFollowActive() } }),
            (.toggleGhostMode, { $0.updatePin { $0.toggleGhostMode() } }),
            (.navigateBack, { $0.goBack() }),
            (.navigateForward, { $0.goForward() }),
            (.openFolder, { $0.chooseWorkspaceFolder() }),
            (.searchPalette, { $0.openSearchPalette() }),
        ]
        let broadcasts: [(Notification.Name, (PreviewController) -> Void)] = [
            (.zoomDidChange, { $0.applyZoom() }),
            (.settingsDidChange, { $0.applySettings() }),
        ]
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, keyWindowOnly: Bool, _ action: @escaping (PreviewController) -> Void) {
            // Block observers aren't removed by removeObserver(self): keep the
            // tokens for deinit, and capture weakly so they don't retain us.
            observerTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !keyWindowOnly || self.webView.window?.isKeyWindow == true else { return }
                    action(self)
                }
            })
        }
        for (name, action) in keyWindowCommands { observe(name, keyWindowOnly: true, action) }
        for (name, action) in broadcasts { observe(name, keyWindowOnly: false, action) }
    }
    private var observerTokens: [NSObjectProtocol] = []

    /// Navigate the current window to a file picked in the tree.
    func openFromTree(_ url: URL) {
        pushAndNavigate(to: url, fragment: "")
    }

    private func chooseWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Set Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard setWorkspaceRoot(url) else {
            errorBanner = "\(fileURL.lastPathComponent) isn't inside \(url.lastPathComponent) — choose a folder that contains it."
            return
        }
        sidebarMode = .files
        showOutline = true
    }

    /// Re-root the workspace at `folder`, which must contain the open document
    /// (its `<base href>` and the sandbox are both relative to the root).
    /// Re-renders now with an empty wiki index, then again once the new index
    /// lands, so links never resolve against the previous root.
    @discardableResult
    func setWorkspaceRoot(_ folder: URL) -> Bool {
        let rootPath = folder.standardizedFileURL.path
        guard fileURL.standardizedFileURL.path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/") else {
            return false
        }
        workspace.setRoot(folder)
        docHandler.setDocRoot(workspace.root)
        indexPopulated = false
        loadFromDisk(reason: "open-folder")
        return true
    }

    private func openSearchPalette() {
        workspace.rebuild()        // refresh the file list before searching
        showSearchPalette = true
    }

    private func scheduleSearch() {
        searchWork?.cancel()
        let query = searchQuery
        let files = workspace.markdownFiles
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []; return
        }
        let work = DispatchWorkItem { [weak self] in
            let results = WorkspaceSearch.search(query: query, files: files)
            DispatchQueue.main.async {
                // A slower, older search must not overwrite newer results (Return
                // would then open the wrong file), nor repopulate a closed palette.
                guard let self, self.showSearchPalette, self.searchQuery == query else { return }
                self.searchResults = results
            }
        }
        searchWork = work
        searchQueue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func chooseSearchResult(_ result: WorkspaceSearch.Result) {
        showSearchPalette = false
        searchQuery = ""
        searchResults = []
        pushAndNavigate(to: result.url, fragment: "")
    }

    deinit {
        watcher?.cancel()
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }

    /// Re-render the current document the first time the workspace index
    /// populates, so wiki-links in the initially-shown doc resolve. Guarded so
    /// later refreshes (Files tab / palette open) never re-render what the user
    /// is reading.
    private func reRenderForIndexIfNeeded() {
        guard !indexPopulated, !workspace.wikiIndex.isEmpty else { return }
        indexPopulated = true
        loadFromDisk(reason: "index-ready")
    }

    // MARK: - Template load

    private func loadTemplate() {
        // Load via the bundle scheme so relative <link>/<script> resolve correctly
        var components = URLComponents()
        components.scheme = BundleSchemeHandler.scheme
        components.host = "app"
        components.path = "/template.html"
        guard let url = components.url else { return }
        webView.load(URLRequest(url: url))
    }

    // MARK: - File watching

    private func startWatching() {
        watcher?.cancel()
        let name = fileURL.lastPathComponent
        watcher = FileWatcher(url: fileURL, onMissing: { [weak self] in
            // Cleared by the next successful load if the file comes back.
            self?.errorBanner = "\(name) was moved or deleted. Markee will reload it if it reappears."
        }, onChange: { [weak self] in
            UsageTracker.shared.recordRerender()
            self?.loadFromDisk(reason: "fs-change")
        })
    }

    private func loadFromDisk(reason: String) {
        guard let source = readCurrentFile() else { return }
        self.errorBanner = nil
        self.lastGoodSource = source
        render(source: source)
    }

    /// Read the open file (encoding-tolerant), or show why not and return nil.
    private func readCurrentFile() -> String? {
        do {
            return try readFileWithFallback(at: fileURL)
        } catch {
            errorBanner = "Couldn't read \(fileURL.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    /// Call `window.markee.<function>(args…)` if the page exposes it. Every
    /// argument is JSON-encoded, so no string or payload can break out of the
    /// call expression.
    private func callJS(_ function: String, _ args: Any...,
                        completion: (@MainActor @Sendable (Any?, Error?) -> Void)? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: args, options: [.fragmentsAllowed]),
              let list = String(data: data, encoding: .utf8) else { return }
        let argList = String(list.dropFirst().dropLast())   // strip the array brackets
        let fn = "window.markee && window.markee.\(function)"
        webView.evaluateJavaScript("(\(fn)) ? \(fn)(\(argList)) : null;", completionHandler: completion)
    }

    // MARK: - Render

    private func render(source: String) {
        if !templateLoaded {
            pendingRender = source
            return
        }
        var payload: [String: Any] = [
            "source": source,
            "fileName": fileURL.lastPathComponent,
            "docBase": WorkspaceModel.docBase(for: fileURL, root: workspace.root),
            "wikiIndex": workspace.wikiIndex,
            "readOnly": false
        ]
        if pendingNavigated {
            payload["navigated"] = true
            pendingNavigated = false
        }
        if !pendingScrollTo.isEmpty {
            payload["scrollTo"] = pendingScrollTo
            pendingScrollTo = ""
        }
        callJS("render", payload) { [weak self] _, err in
            if let err {
                self?.errorBanner = "Render error: \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Commands

    private func toggleOutline() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showOutline.toggle()
        }
    }

    /// ⌘G / ⇧⌘G — with no query yet, just reveal the find bar (like ⌘F);
    /// otherwise step through matches with the last query, bar visible or not.
    /// macOS WKWebView has no find UI: the FindBar drives the JS engine
    /// (window.markee.find), which paints matches with the CSS Custom Highlight
    /// API and reports the counter back over the bridge.
    private func findNextOrReveal(backwards: Bool) {
        if findQuery.isEmpty {
            showFindBar = true
        } else {
            runFind(backwards: backwards)
        }
    }

    /// ⌘R — manually re-read and re-render the file. Same path the file
    /// watcher drives; a fallback for the rare save the watcher misses.
    private func reload() {
        if !templateLoaded && !recentContentCrashes.isEmpty {
            recentContentCrashes = []
            reloadTemplateAndRerender()
            return
        }
        loadFromDisk(reason: "manual")
    }

    /// Write arbitrary text to the general pasteboard and confirm via the
    /// in-page toast. Backs the code-block copy button and heading copy-link
    /// (JS posts {kind: "copyText", text, note}).
    func copyTextToPasteboard(_ text: String, note: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        callJS("toast", note)
    }

    /// Reveal the word-count pill, then fade it after a few idle seconds. Each
    /// new render resets the timer so it stays visible during active editing.
    private func showStatsPillBriefly() {
        statsHideWork?.cancel()
        statsPillVisible = true
        let work = DispatchWorkItem { [weak self] in
            self?.statsPillVisible = false
        }
        statsHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    /// ⌘⇧C — copy the file's raw Markdown to the clipboard. Reads fresh from
    /// disk via the renderer's read path so the clipboard never holds a stale
    /// snapshot. Public so MarkeeWebView's context menu can call it directly.
    func copyMarkdownSource() {
        guard let source = readCurrentFile() else { return }
        setPasteboardString(source)
    }

    /// Shared pasteboard writer for the copy actions.
    private func setPasteboardString(_ s: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(s, forType: .string)
    }

    /// ⌥⌘C — copy the file's Markdown with soft-wrapped paragraphs unwrapped
    /// (syntax preserved). Reads fresh from disk, reflows in JS. Public so
    /// MarkeeWebView's context menu can call it directly.
    func copyReflowedMarkdown() {
        guard let source = readCurrentFile() else { return }
        callJS("reflow", source) { [weak self] result, error in
            guard let self else { return }
            if let text = result as? String, error == nil {
                self.setPasteboardString(text)
            } else {
                self.errorBanner = "Couldn't reflow Markdown."
            }
        }
    }

    /// ⌥⇧⌘C — copy the rendered content as flowing plain text (syntax stripped).
    /// Reads the live DOM. Public so MarkeeWebView's context menu can call it.
    func copyRenderedText() {
        callJS("renderedText") { [weak self] result, error in
            guard let self else { return }
            if let text = result as? String, error == nil {
                self.setPasteboardString(text)
            } else {
                self.errorBanner = "Couldn't copy rendered text."
            }
        }
    }

    /// ⌘⇧R — reveal the current file in Finder. Public so MarkeeWebView's
    /// context menu can call it directly.
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func findNext() { runFind(backwards: false) }
    func findPrevious() { runFind(backwards: true) }

    func closeFind() {
        showFindBar = false
        findNotFound = false
        findCurrent = 0
        findTotal = 0
        callJS("clearFind")
    }

    private func runFind(backwards: Bool) {
        guard !findQuery.isEmpty else {
            findNotFound = false; findCurrent = 0; findTotal = 0
            callJS("clearFind")
            return
        }
        callJS("find", findQuery, ["backwards": backwards])
    }

    // MARK: - Zoom

    /// UserDefaults key for the single, global zoom level (shared across all
    /// windows and remembered across launches).
    private static let zoomDefaultsKey = "MarkeeZoomLevel"

    private static var storedZoom: Double {
        get { UserDefaults.standard.object(forKey: zoomDefaultsKey) as? Double ?? 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: zoomDefaultsKey) }
    }

    /// Compute + persist a new zoom level, then broadcast so every open
    /// window re-applies it (the zoom command itself is key-window only).
    private func changeZoom(_ transform: (Double) -> Double) {
        Self.storedZoom = transform(Self.storedZoom)
        NotificationCenter.default.post(name: .zoomDidChange, object: nil)
    }

    /// Push the stored zoom level into this window's WebView.
    private func applyZoom() {
        callJS("setZoom", Self.storedZoom)
    }

    /// Push current settings into this window's WebView. Mirrors applyZoom():
    /// a no-op until JS is ready, and re-run from the `ready` handler so a window
    /// opened after a change still receives it.
    private func applySettings() {
        callJS("applySettings", SettingsStore.shared.payload())
    }

    /// Apply the pin state seeded in init (e.g. from MarkeeDefaultFloatOnTop) to
    /// the NSWindow once it exists. Seeding `pinState` alone only drives the menu
    /// checkmark; the window level is owned by `pinController`, which needs the
    /// attached window. `configureWindow` calls this on first attach (and every
    /// becomeKey), so it's guarded to run exactly once — and only after the window
    /// is available, so an early nil-window call doesn't mark it done prematurely.
    func applyInitialPinStateIfNeeded() {
        guard !didApplyInitialPin, webView.window != nil else { return }
        didApplyInitialPin = true
        pinController.update(pinState)
    }

    // MARK: - Window pinning

    /// Mutate the pin state, then apply it to the window.
    private func updatePin(_ change: (inout WindowPinState) -> Void) {
        change(&pinState)
        pinController.update(pinState)
    }

    /// Looks up the source line of the currently-active heading, if any.
    func currentHeadingLine() -> Int? {
        guard let id = currentHeadingID else { return nil }
        return outline.first(where: { $0.id == id })?.line
    }

    /// Launch the user's external editor at `line` (0-indexed) in the current file.
    /// Pass `nil` to open without a line target.
    func openInEditor(atLine line: Int?) {
        EditorLauncher.open(file: fileURL, line: line) { [weak self] result in
            if case .failure(let err) = result { self?.errorBanner = err.message }
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Only the template's own main frame may drive the bridge (task
        // write-back, clipboard, navigation) — never an iframe or a foreign page.
        guard message.name == "markee",
              message.frameInfo.isMainFrame,
              message.frameInfo.request.url.map(NavigationPolicy.isTemplate) == true,
              let decoded = BridgeMessage(body: message.body) else { return }
        handle(decoded)
    }

    private func handle(_ message: BridgeMessage) {
        switch message {
        case .ready:
            templateLoaded = true
            if let pending = pendingRender {
                pendingRender = nil
                render(source: pending)
            }
            // Load-bearing: a window opened after another window changed zoom
            // never received that .zoomDidChange broadcast, and a broadcast
            // that arrived before this page's JS was ready was a silent no-op.
            // Re-reading the persisted level here covers both cases.
            applyZoom()
            applySettings()
        case .outline(let items):
            outline = items
        case .error(let text):
            errorBanner = text
        case .taskToggle(let line, let checked):
            toggleTask(atLine: line, checked: checked)
        case .scrollSection(let id):
            if id != currentHeadingID { currentHeadingID = id }
        case .copyText(let text, let note):
            copyTextToPasteboard(text, note: note)
        case .docStats(let words, let minutes):
            docWords = words
            docMinutes = minutes
            showStatsPillBriefly()
        case .findResult(let current, let total):
            findCurrent = current
            findTotal = total
            findNotFound = (total == 0 && current == 0)
        case .navigate(let path, let fragment, let newWindow):
            handleNavigate(path: path, fragment: fragment, newWindow: newWindow)
        }
    }

    /// Flip a single `[ ]`/`[x]` bracket on the given 0-indexed line in the file.
    /// Re-reads the file first and bails if the line no longer looks like a task
    /// item (it drifted between click and write) — the only protection against
    /// clobbering a concurrent edit in another editor. Any bail re-renders from
    /// disk so the checkbox the click already flipped snaps back to the truth.
    private func toggleTask(atLine line: Int, checked: Bool) {
        // Write through symlinks: an atomic write to the link itself would
        // replace it with a regular file and leave the real target unchanged.
        let target = fileURL.resolvingSymlinksInPath()
        do {
            let decoded = try readDecodedFile(at: target)
            guard let newText = TaskToggle.toggledText(decoded.text, line: line, checked: checked),
                  let data = decoded.encode(newText) else {
                loadFromDisk(reason: "task-toggle-bail")
                return
            }
            try data.write(to: target, options: .atomic)
            if checked { UsageTracker.shared.recordBoxChecked() }
        } catch {
            loadFromDisk(reason: "task-toggle-failed")
            self.errorBanner = "Failed to toggle task: \(error.localizedDescription)"
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel); return
        }
        let decision = NavigationPolicy.decide(
            url: url,
            isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
            isLinkActivated: navigationAction.navigationType == .linkActivated)
        switch decision {
        case .allow:
            decisionHandler(.allow); return
        case .cancel:
            break
        case .openExternally(let external):
            NSWorkspace.shared.open(external)
        case .openWorkspaceFile(let path):
            openWorkspaceFile(path: path)
        case .blockedScheme(let scheme):
            self.errorBanner = "Blocked link with unsupported scheme: \(scheme)"
        }
        decisionHandler(.cancel)
    }

    /// A clicked link to a non-Markdown file inside the workspace: open viewable
    /// types in their default app, reveal anything else in Finder.
    private func openWorkspaceFile(path: String) {
        guard let target = resolveSandboxed(root: workspace.root, requestPath: path) else {
            errorBanner = "Link points outside the workspace folder."
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else {
            errorBanner = "File not found: \(target.lastPathComponent)"
            return
        }
        if isDir.boolValue { return }
        if NavigationPolicy.isSafeToOpen(target) {
            NSWorkspace.shared.open(target)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
    }

    /// The template is the only page the main frame may hold, so a commit of
    /// anything else means the policy above was bypassed: restore the preview.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let url = webView.url, !NavigationPolicy.isTemplate(url) else { return }
        reloadTemplateAndRerender()
    }

    /// WebContent crashed or was killed (memory pressure): the page is gone and
    /// later renders would silently no-op, so rebuild it — but a document that
    /// crashes it every time must not reload forever.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let now = Date()
        recentContentCrashes = recentContentCrashes.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard recentContentCrashes.count <= Self.maxContentCrashesPerMinute else {
            templateLoaded = false        // page is dead; ⌘R rebuilds it
            errorBanner = "The preview keeps crashing on \(fileURL.lastPathComponent). Press ⌘R to try again."
            return
        }
        reloadTemplateAndRerender()
    }
    private static let maxContentCrashesPerMinute = 3
    private var recentContentCrashes: [Date] = []

    private func reloadTemplateAndRerender() {
        templateLoaded = false
        pendingRender = lastGoodSource.isEmpty ? pendingRender : lastGoodSource
        loadTemplate()
    }

    // MARK: - In-window navigation

    private(set) var history: NavigationHistory
    private var pendingScrollTo: String = ""
    private var pendingNavigated: Bool = false

    /// Resolve a markee-doc path within the workspace root and either open a new
    /// window or navigate the current one. Out-of-root paths are rejected.
    private func handleNavigate(path rawPath: String, fragment: String, newWindow: Bool) {
        // JS sends `URL.pathname`, which is still percent-encoded.
        let path = rawPath.removingPercentEncoding ?? rawPath
        guard resolveSandboxed(root: workspace.root, requestPath: path) != nil else {
            errorBanner = "Link points outside the workspace folder."
            return
        }
        // Address the file through the (unresolved) workspace root rather than
        // the symlink-resolved sandbox result, so docBase, the file-tree
        // highlight and history dedupe keep matching when the root itself is
        // reached through a symlink.
        let target = workspace.root.appendingPathComponent(
            String(path.drop(while: { $0 == "/" }))).standardizedFileURL
        guard ["md", "markdown"].contains(target.pathExtension.lowercased()) else {
            openWorkspaceFile(path: path)
            return
        }
        guard FileManager.default.fileExists(atPath: target.path) else {
            errorBanner = "File not found: \(target.lastPathComponent)"
            return
        }
        if newWindow {
            NSDocumentController.shared.openDocument(
                withContentsOf: target, display: true, completionHandler: { _, _, _ in })
            return
        }
        pushAndNavigate(to: target, fragment: fragment)
    }

    /// A forward navigation (link, tree, search result): record it, then go.
    private func pushAndNavigate(to url: URL, fragment: String) {
        history.push(url)
        navigate(to: url, fragment: fragment)
    }

    /// Retarget the window's document identity to `url` and re-render. Used by
    /// link clicks (push) and the back/forward commands (no push).
    private func navigate(to url: URL, fragment: String) {
        self.fileURL = url
        self.pendingScrollTo = fragment
        self.pendingNavigated = true
        // Keep AppKit's window proxy honest with the navigated document.
        webView.window?.representedURL = url
        startWatching()                       // cancels old watcher, watches new file
        UsageTracker.shared.recordDocumentOpened(url)
        loadFromDisk(reason: "navigate")
        objectWillChange.send()               // refresh history-button enablement
    }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    func goBack() {
        guard let url = history.back() else { return }
        navigate(to: url, fragment: "")
    }
    func goForward() {
        guard let url = history.forward() else { return }
        navigate(to: url, fragment: "")
    }

    /// Scroll the WebView to a given heading id.
    func scrollToHeading(_ id: String) {
        callJS("scrollToHeading", id)
    }
}
