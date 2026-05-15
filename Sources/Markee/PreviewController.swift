import SwiftUI
import WebKit

struct OutlineEntry: Identifiable, Hashable {
    let id: String        // heading slug / anchor
    let level: Int        // 1..6
    let title: String
    let line: Int?        // 0-indexed source line; nil if JS didn't supply one
}

@MainActor
final class PreviewController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published var outline: [OutlineEntry] = []
    @Published var errorBanner: String? = nil
    @Published var showOutline: Bool = false
    @Published var currentHeadingID: String? = nil
    @Published var showFindBar: Bool = false
    @Published var findQuery: String = ""
    @Published var findNotFound: Bool = false

    let webView: WKWebView
    let bundleHandler = BundleSchemeHandler()
    let docHandler: DocSchemeHandler

    private(set) var fileURL: URL
    private var watcher: FileWatcher?
    private var lastGoodSource: String = ""
    private var templateLoaded = false
    private var pendingRender: String?
    private var saveExportPanel: NSSavePanel?

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.docHandler = DocSchemeHandler(docRoot: fileURL.deletingLastPathComponent())

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

        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        userContent.add(self, name: "markee")
        self.webView.navigationDelegate = self
        self.webView.allowsBackForwardNavigationGestures = false

        loadTemplate()
        startWatching()
        loadFromDisk(reason: "initial")

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleToggleOutline),
            name: .toggleOutline, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleExportHTML),
            name: .exportHTML, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenInEditor),
            name: .openInEditor, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFind),
            name: .findInPreview, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePrint),
            name: .printPreview, object: nil)
    }

    deinit {
        watcher?.cancel()
        NotificationCenter.default.removeObserver(self)
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
        watcher = FileWatcher(url: fileURL) { [weak self] in
            self?.loadFromDisk(reason: "fs-change")
        }
    }

    private func loadFromDisk(reason: String) {
        let source: String
        do {
            source = try Self.readFileWithFallback(at: fileURL)
            self.errorBanner = nil
        } catch {
            self.errorBanner = "Couldn't read \(fileURL.lastPathComponent): \(error.localizedDescription)"
            return
        }
        self.lastGoodSource = source
        render(source: source)
    }

    static func readFileWithFallback(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) { return s }
        // Try utf16 with BOM detection
        if let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return ""
    }

    // MARK: - Render

    private func render(source: String) {
        if !templateLoaded {
            pendingRender = source
            return
        }
        let payload: [String: Any] = [
            "source": source,
            "fileName": fileURL.lastPathComponent,
            "docBase": "\(DocSchemeHandler.scheme)://doc/"
        ]
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
        // Only act on the front-most window's controller — we listen via NotificationCenter
        // and SwiftUI binds one controller per window. Each window's controller will toggle;
        // the visual switch only matters for the key window since others aren't visible-key.
        if NSApp.keyWindow?.contentViewController?.view.window === webView.window?.windowController?.window
            || webView.window?.isKeyWindow == true {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                showOutline.toggle()
            }
        }
    }

    @objc private func handleOpenInEditor() {
        guard webView.window?.isKeyWindow == true else { return }
        let line = currentHeadingLine()
        openInEditor(atLine: line)
    }

    /// Reveal the in-app find bar. macOS WKWebView has no built-in find UI, so
    /// PreviewView's FindBar drives webView.find(_:configuration:) directly.
    @objc private func handleFind() {
        guard webView.window?.isKeyWindow == true else { return }
        showFindBar = true
    }

    func findNext() { runFind(backwards: false) }
    func findPrevious() { runFind(backwards: true) }

    func closeFind() {
        showFindBar = false
        findNotFound = false
    }

    private func runFind(backwards: Bool) {
        guard !findQuery.isEmpty else { findNotFound = false; return }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        config.caseSensitive = false
        webView.find(findQuery, configuration: config) { [weak self] result in
            self?.findNotFound = !result.matchFound
        }
    }

    /// Open the system print panel for the rendered preview. The panel's PDF
    /// menu ("Save as PDF") gives print-to-PDF for free.
    @objc private func handlePrint() {
        guard webView.window?.isKeyWindow == true, let window = webView.window else { return }
        let op = webView.printOperation(with: NSPrintInfo.shared)
        op.view?.frame = webView.bounds
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// Looks up the source line of the currently-active heading, if any.
    private func currentHeadingLine() -> Int? {
        guard let id = currentHeadingID else { return nil }
        return outline.first(where: { $0.id == id })?.line
    }

    /// Launch the user's external editor at `line` (0-indexed) in the current file.
    /// Pass `nil` to open without a line target.
    func openInEditor(atLine line: Int?) {
        switch EditorLauncher.open(file: fileURL, line: line) {
        case .success:
            break
        case .failure(let err):
            self.errorBanner = err.message
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
        guard message.name == "markee", let body = message.body as? [String: Any] else { return }
        let kind = body["kind"] as? String ?? ""
        switch kind {
        case "ready":
            templateLoaded = true
            if let pending = pendingRender {
                pendingRender = nil
                render(source: pending)
            }
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
        default:
            break
        }
    }

    /// Flip a single `[ ]`/`[x]` bracket on the given 0-indexed line in the file,
    /// then write atomically. Bails silently if the line no longer looks like a
    /// task-list item (file drifted between click and write) — the next render
    /// reconciles.
    private func toggleTask(atLine line: Int, checked: Bool) {
        do {
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                self.errorBanner = "Cannot decode \(fileURL.lastPathComponent) as UTF-8"
                return
            }
            var lines = text.components(separatedBy: "\n")
            guard line >= 0, line < lines.count else { return }

            let original = lines[line]
            let hadCR = original.hasSuffix("\r")
            let body = hadCR ? String(original.dropLast()) : original

            let pattern = "^(\\s*(?:[-+*]|\\d+\\.)\\s+\\[)([ xX])(\\].*)$"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body))
            else {
                return
            }
            let nsBody = body as NSString
            let prefix = nsBody.substring(with: match.range(at: 1))
            let suffix = nsBody.substring(with: match.range(at: 3))
            let mark = checked ? "x" : " "
            lines[line] = prefix + mark + suffix + (hadCR ? "\r" : "")
            let newText = lines.joined(separator: "\n")
            try newText.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            self.errorBanner = "Failed to toggle task: \(error.localizedDescription)"
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        // Allow initial load of our template & our scheme handlers
        if url.scheme == BundleSchemeHandler.scheme || url.scheme == DocSchemeHandler.scheme {
            decisionHandler(.allow); return
        }
        // In-page anchor navigation
        if url.scheme == "about" {
            decisionHandler(.allow); return
        }
        if navigationAction.navigationType == .linkActivated {
            // Allowlist only safe schemes. `javascript:`, `file://`, `vscode://`,
            // and other custom schemes can leak data or trigger unintended
            // actions in handler apps; cancel and ignore.
            let allowed: Set<String> = ["http", "https", "mailto"]
            if let scheme = url.scheme?.lowercased(), allowed.contains(scheme) {
                NSWorkspace.shared.open(url)
            } else {
                self.errorBanner = "Blocked link with unsupported scheme: \(url.scheme ?? "?")"
            }
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    /// Scroll the WebView to a given heading id.
    func scrollToHeading(_ id: String) {
        let safe = id.replacingOccurrences(of: "\"", with: "\\\"")
        let js = "window.markee && window.markee.scrollToHeading(\"\(safe)\");"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
