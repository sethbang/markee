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
    let bundleHandler = BundleSchemeHandler()
    let docHandler: DocSchemeHandler

    @Published private(set) var fileURL: URL
    let workspace: WorkspaceModel
    private var watcher: FileWatcher?
    private var lastGoodSource: String = ""
    private var templateLoaded = false
    private var pendingRender: String?
    private var saveExportPanel: NSSavePanel?
    private var didApplyInitialPin = false
    private var indexPopulated = false
    // Applies pinState to the NSWindow; mutate pinState first, then call update.
    private lazy var pinController = WindowPinController(
        windowProvider: { [weak self] in self?.webView.window })

    init(fileURL: URL) {
        self.fileURL = fileURL
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
        self.history = NavigationHistory(initial: fileURL)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToggleOutline),
            name: .toggleOutline, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleExportHTML),
            name: .exportHTML, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleExportPDF),
            name: .exportPDF, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenInEditor),
            name: .openInEditor, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFind),
            name: .findInPreview, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePrint),
            name: .printPreview, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleZoomIn),
            name: .zoomIn, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleZoomOut),
            name: .zoomOut, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleZoomReset),
            name: .zoomReset, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleZoomDidChange),
            name: .zoomDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFindNext),
            name: .findNext, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFindPrevious),
            name: .findPrevious, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleReload),
            name: .reloadFile, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCopyMarkdownSource),
            name: .copyMarkdownSource, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCopyReflowedMarkdown),
            name: .copyReflowedMarkdown, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCopyRenderedText),
            name: .copyRenderedText, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRevealInFinder),
            name: .revealInFinder, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToggleFloatOnTop),
            name: .toggleFloatOnTop, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToggleAllSpaces),
            name: .toggleAllSpaces, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToggleFollowActive),
            name: .toggleFollowActive, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToggleGhostMode),
            name: .toggleGhostMode, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSettingsDidChange),
            name: .settingsDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleGoBack), name: .navigateBack, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleGoForward), name: .navigateForward, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenFolder), name: .openFolder, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSearchPalette), name: .searchPalette, object: nil)
        UsageTracker.shared.recordDocumentOpened(fileURL)
    }

    /// Navigate the current window to a file picked in the tree.
    func openFromTree(_ url: URL) {
        handleTreeNavigate(to: url)
    }
    private func handleTreeNavigate(to url: URL) {
        if history == nil { history = NavigationHistory(initial: fileURL) }
        history.push(url)
        navigate(to: url, fragment: "")
    }

    @objc private func handleOpenFolder() {
        guard webView.window?.isKeyWindow == true else { return }
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

    @objc private func handleSearchPalette() {
        guard webView.window?.isKeyWindow == true else { return }
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
        if history == nil { history = NavigationHistory(initial: fileURL) }
        history.push(result.url)
        navigate(to: result.url, fragment: "")
    }

    deinit {
        watcher?.cancel()
        NotificationCenter.default.removeObserver(self)
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
        let source: String
        do {
            source = try readFileWithFallback(at: fileURL)
            self.errorBanner = nil
        } catch {
            self.errorBanner = "Couldn't read \(fileURL.lastPathComponent): \(error.localizedDescription)"
            return
        }
        self.lastGoodSource = source
        render(source: source)
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
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        let js = "window.markee && window.markee.render(\(json));"
        webView.evaluateJavaScript(js) { [weak self] _, err in
            if let err {
                self?.errorBanner = "Render error: \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Outline toggle / export

    @objc private func handleToggleOutline() {
        guard webView.window?.isKeyWindow == true else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showOutline.toggle()
        }
    }

    @objc private func handleOpenInEditor() {
        guard webView.window?.isKeyWindow == true else { return }
        let line = currentHeadingLine()
        openInEditor(atLine: line)
    }

    /// Reveal the in-app find bar. macOS WKWebView has no built-in find UI, so
    /// the FindBar drives the JS find engine (window.markee.find) via
    /// evaluateJavaScript; matches are painted with the CSS Custom Highlight API
    /// and the match counter comes back over the message bridge.
    @objc private func handleFind() {
        guard webView.window?.isKeyWindow == true else { return }
        showFindBar = true
    }

    /// ⌘G — if there is no query yet, just reveal the find bar (same as ⌘F);
    /// otherwise search forward with the last query, bar visible or not.
    @objc private func handleFindNext() {
        guard webView.window?.isKeyWindow == true else { return }
        if findQuery.isEmpty {
            showFindBar = true
        } else {
            findNext()
        }
    }

    /// ⌘R — manually re-read and re-render the file. Same path the file
    /// watcher drives; a fallback for the rare save the watcher misses.
    @objc private func handleReload() {
        guard webView.window?.isKeyWindow == true else { return }
        loadFromDisk(reason: "manual")
    }

    /// Write arbitrary text to the general pasteboard and confirm via the
    /// in-page toast. Backs the code-block copy button and heading copy-link
    /// (JS posts {kind: "copyText", text, note}).
    func copyTextToPasteboard(_ text: String, note: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        webView.evaluateJavaScript(
            "window.markee && window.markee.toast && window.markee.toast(\(jsString(note)));",
            completionHandler: nil
        )
    }

    /// JSON-encode a Swift string into a JS string literal (quotes included).
    private func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())
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
        let source: String
        do {
            source = try readFileWithFallback(at: fileURL)
        } catch {
            self.errorBanner = "Couldn't read \(fileURL.lastPathComponent): \(error.localizedDescription)"
            return
        }
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
        let source: String
        do {
            source = try readFileWithFallback(at: fileURL)
        } catch {
            self.errorBanner = "Couldn't read \(fileURL.lastPathComponent): \(error.localizedDescription)"
            return
        }
        let js = "window.markee && window.markee.reflow ? window.markee.reflow(\(jsString(source))) : null;"
        webView.evaluateJavaScript(js) { [weak self] result, error in
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
        let js = "window.markee && window.markee.renderedText ? window.markee.renderedText() : null;"
        webView.evaluateJavaScript(js) { [weak self] result, error in
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

    @objc private func handleCopyMarkdownSource() {
        guard webView.window?.isKeyWindow == true else { return }
        copyMarkdownSource()
    }

    @objc private func handleCopyReflowedMarkdown() {
        guard webView.window?.isKeyWindow == true else { return }
        copyReflowedMarkdown()
    }

    @objc private func handleCopyRenderedText() {
        guard webView.window?.isKeyWindow == true else { return }
        copyRenderedText()
    }

    @objc private func handleRevealInFinder() {
        guard webView.window?.isKeyWindow == true else { return }
        revealInFinder()
    }

    /// ⌘⇧G — mirror of handleFindNext, searching backward.
    @objc private func handleFindPrevious() {
        guard webView.window?.isKeyWindow == true else { return }
        if findQuery.isEmpty {
            showFindBar = true
        } else {
            findPrevious()
        }
    }

    func findNext() { runFind(backwards: false) }
    func findPrevious() { runFind(backwards: true) }

    func closeFind() {
        showFindBar = false
        findNotFound = false
        findCurrent = 0
        findTotal = 0
        webView.evaluateJavaScript("window.markee && window.markee.clearFind && window.markee.clearFind();", completionHandler: nil)
    }

    private func runFind(backwards: Bool) {
        guard !findQuery.isEmpty else {
            findNotFound = false; findCurrent = 0; findTotal = 0
            webView.evaluateJavaScript("window.markee && window.markee.clearFind && window.markee.clearFind();", completionHandler: nil)
            return
        }
        let payload: [String: Any] = ["backwards": backwards]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let opts = String(data: data, encoding: .utf8) else { return }
        let q = jsString(findQuery)
        webView.evaluateJavaScript(
            "window.markee && window.markee.find && window.markee.find(\(q), \(opts));",
            completionHandler: nil
        )
    }

    /// Open the system print panel for the rendered preview. The panel's PDF
    /// menu ("Save as PDF") gives print-to-PDF for free.
    @objc private func handlePrint() {
        guard webView.window?.isKeyWindow == true, let window = webView.window else { return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.topMargin = Self.printMargin
        info.bottomMargin = Self.printMargin
        info.leftMargin = Self.printMargin
        info.rightMargin = Self.printMargin
        let op = webView.printOperation(with: info)
        op.view?.frame = webView.bounds
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc private func handleExportPDF() {
        guard webView.window?.isKeyWindow == true, let window = webView.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = fileURL.deletingPathExtension().lastPathComponent + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let op = webView.printOperation(with: Self.pdfPrintInfo(savingTo: url))
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        // Sheet-modal run (not op.run): WKWebView printing finalizes
        // asynchronously, so the operation must spin the run loop — which the
        // sheet variant does — or it writes a truncated PDF. It returns *before*
        // the write completes, so success is reported in the didRun callback.
        op.runModal(for: window, delegate: self,
                    didRun: #selector(pdfExportDidRun(_:success:contextInfo:)),
                    contextInfo: nil)
    }

    @objc private func pdfExportDidRun(_ op: NSPrintOperation, success: Bool,
                                       contextInfo: UnsafeMutableRawPointer?) {
        if !success { errorBanner = "PDF export failed." }
    }

    /// Shared print margin (0.75in). Margins are owned by the print system, not
    /// CSS `@page`, so print and PDF stay consistent and un-doubled.
    static let printMargin: CGFloat = 54   // 0.75in * 72pt

    /// Build an NSPrintInfo that writes the print operation to a PDF file at
    /// `url` instead of sending it to a printer.
    static func pdfPrintInfo(savingTo url: URL) -> NSPrintInfo {
        let info = NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = url
        info.horizontalPagination = .automatic
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = printMargin
        info.bottomMargin = printMargin
        info.leftMargin = printMargin
        info.rightMargin = printMargin
        return info
    }

    // MARK: - Zoom

    /// UserDefaults key for the single, global zoom level (shared across all
    /// windows and remembered across launches).
    private static let zoomDefaultsKey = "MarkeeZoomLevel"

    private static var storedZoom: Double {
        get { UserDefaults.standard.object(forKey: zoomDefaultsKey) as? Double ?? 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: zoomDefaultsKey) }
    }

    @objc private func handleZoomIn() {
        changeZoom { nextZoom(from: $0, direction: .in) }
    }

    @objc private func handleZoomOut() {
        changeZoom { nextZoom(from: $0, direction: .out) }
    }

    @objc private func handleZoomReset() {
        changeZoom { _ in 1.0 }
    }

    /// Compute + persist a new zoom level, then broadcast so every open
    /// window re-applies it. Only the key window's controller acts.
    private func changeZoom(_ transform: (Double) -> Double) {
        guard webView.window?.isKeyWindow == true else { return }
        Self.storedZoom = transform(Self.storedZoom)
        NotificationCenter.default.post(name: .zoomDidChange, object: nil)
    }

    @objc private func handleZoomDidChange() {
        applyZoom()
    }

    /// Push the stored zoom level into this window's WebView.
    private func applyZoom() {
        webView.evaluateJavaScript(
            "window.markee && window.markee.setZoom(\(Self.storedZoom));",
            completionHandler: nil)
    }

    @objc private func handleSettingsDidChange() { applySettings() }

    /// Push current settings into this window's WebView. Mirrors applyZoom():
    /// a no-op until JS is ready, and re-run from the `ready` handler so a window
    /// opened after a change still receives it.
    private func applySettings() {
        let payload = SettingsStore.shared.payload()
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript(
            "window.markee && window.markee.applySettings(\(json));",
            completionHandler: nil)
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

    @objc private func handleToggleFloatOnTop() {
        guard webView.window?.isKeyWindow == true else { return }
        pinState.toggleFloatOnTop()
        pinController.update(pinState)
    }

    @objc private func handleToggleAllSpaces() {
        guard webView.window?.isKeyWindow == true else { return }
        pinState.toggleAllSpaces()
        pinController.update(pinState)
    }

    @objc private func handleToggleFollowActive() {
        guard webView.window?.isKeyWindow == true else { return }
        pinState.toggleFollowActive()
        pinController.update(pinState)
    }

    @objc private func handleToggleGhostMode() {
        guard webView.window?.isKeyWindow == true else { return }
        pinState.toggleGhostMode()
        pinController.update(pinState)
    }

    /// Looks up the source line of the currently-active heading, if any.
    private func currentHeadingLine() -> Int? {
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

    @objc private func handleExportHTML() {
        guard webView.window?.isKeyWindow == true else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = fileURL.deletingPathExtension().lastPathComponent + ".html"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            // exportStandalone is async (it fetches+inlines images), so it
            // returns a Promise. evaluateJavaScript can't await one — it hands
            // back the Promise object, which WKWebView can't bridge to Swift
            // ("unsupported type"). callAsyncJavaScript awaits it for us.
            Task { @MainActor in
                let value: Any?
                do {
                    value = try await self.webView.callAsyncJavaScript(
                        "return window.markee ? await window.markee.exportStandalone() : null;",
                        contentWorld: .page
                    )
                } catch {
                    self.errorBanner = "Export failed: \(error.localizedDescription)"
                    return
                }
                guard let html = value as? String, !html.isEmpty else {
                    self.errorBanner = "Export returned no content"
                    return
                }
                do {
                    try html.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    self.errorBanner = "Export write failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Only the template's own main frame may drive the bridge (task
        // write-back, clipboard, navigation) — never an iframe or a foreign page.
        guard message.name == "markee",
              message.frameInfo.isMainFrame,
              message.frameInfo.request.url.map(NavigationPolicy.isTemplate) == true,
              let body = message.body as? [String: Any] else { return }
        let kind = body["kind"] as? String ?? ""
        switch kind {
        case "ready":
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
        case "outline":
            if let items = body["items"] as? [[String: Any]] {
                self.outline = items.compactMap { d in
                    guard let id = d["id"] as? String,
                          let level = d["level"] as? Int,
                          let title = d["title"] as? String else { return nil }
                    let line = d["line"] as? Int
                    return OutlineEntry(id: id, level: level, title: title, line: line)
                }
            }
        case "error":
            self.errorBanner = body["message"] as? String
        case "taskToggle":
            if let line = body["line"] as? Int, let checked = body["checked"] as? Bool {
                toggleTask(atLine: line, checked: checked)
            }
        case "scrollSection":
            let id = body["id"] as? String
            if id != self.currentHeadingID {
                self.currentHeadingID = id
            }
        case "copyText":
            if let text = body["text"] as? String {
                let note = body["note"] as? String ?? "Copied"
                copyTextToPasteboard(text, note: note)
            }
        case "docStats":
            let words = body["words"] as? Int ?? 0
            let minutes = body["minutes"] as? Int ?? 1
            self.docWords = words
            self.docMinutes = minutes
            showStatsPillBriefly()
        case "findResult":
            let current = body["current"] as? Int ?? 0
            let total = body["total"] as? Int ?? 0
            self.findCurrent = current
            self.findTotal = total
            self.findNotFound = (total == 0 && current == 0)
        case "navigate":
            guard let path = body["path"] as? String else { break }
            let fragment = body["fragment"] as? String ?? ""
            let newWindow = body["newWindow"] as? Bool ?? false
            handleNavigate(path: path, fragment: fragment, newWindow: newWindow)
        default:
            break
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
    /// later renders would silently no-op, so rebuild it.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reloadTemplateAndRerender()
    }

    private func reloadTemplateAndRerender() {
        templateLoaded = false
        pendingRender = lastGoodSource.isEmpty ? pendingRender : lastGoodSource
        loadTemplate()
    }

    // MARK: - In-window navigation

    private(set) var history: NavigationHistory!
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
        if history == nil { history = NavigationHistory(initial: fileURL) }
        history.push(target)
        navigate(to: target, fragment: fragment)
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

    var canGoBack: Bool { history?.canGoBack ?? false }
    var canGoForward: Bool { history?.canGoForward ?? false }

    func goBack() {
        guard let url = history?.back() else { return }
        navigate(to: url, fragment: "")
    }
    func goForward() {
        guard let url = history?.forward() else { return }
        navigate(to: url, fragment: "")
    }

    @objc private func handleGoBack() {
        guard webView.window?.isKeyWindow == true else { return }
        goBack()
    }
    @objc private func handleGoForward() {
        guard webView.window?.isKeyWindow == true else { return }
        goForward()
    }

    /// Scroll the WebView to a given heading id.
    func scrollToHeading(_ id: String) {
        let js = "window.markee && window.markee.scrollToHeading(\(jsString(id)));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
