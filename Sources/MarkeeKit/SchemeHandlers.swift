import Foundation
import WebKit

/// Serves files from the app bundle's Resources/web/ directory.
/// URLs look like: markee-app://app/template.html, markee-app://app/vendor/katex/katex.min.css
public final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated public static let scheme = "markee-app"
    private let webRoot: URL

    public override init() {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        self.webRoot = resources.appendingPathComponent("web", isDirectory: true)
        super.init()
    }

    /// Serve from an explicit directory (tests point this at `Resources/web`).
    public init(webRoot: URL) {
        self.webRoot = webRoot
        super.init()
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        guard let candidate = resolveSandboxed(root: webRoot, requestPath: url.path) else {
            fail(task: urlSchemeTask, status: 403, message: "Forbidden"); return
        }
        serve(fileURL: candidate, task: urlSchemeTask)
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func serve(fileURL: URL, task: WKURLSchemeTask) {
        guard let requestURL = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let mime = mimeType(for: fileURL.pathExtension)
            guard let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mime,
                    "Content-Length": String(data.count),
                ]
            ) else {
                task.didFailWithError(URLError(.cannotParseResponse)); return
            }
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch {
            guard let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            ) else {
                task.didFailWithError(URLError(.cannotParseResponse)); return
            }
            task.didReceive(response)
            task.didReceive(Data("Not found".utf8))
            task.didFinish()
        }
    }

    private func fail(task: WKURLSchemeTask, status: Int, message: String) {
        guard let requestURL = task.request.url,
              let response = HTTPURLResponse(
                  url: requestURL,
                  statusCode: status,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "text/plain"]
              ) else {
            task.didFailWithError(URLError(.cannotParseResponse)); return
        }
        task.didReceive(response)
        task.didReceive(Data(message.utf8))
        task.didFinish()
    }
}

/// Serves files from its configured `docRoot` (mutable via `setDocRoot`). In the
/// app this is the WORKSPACE ROOT, so every `.md` sibling / image under the
/// workspace resolves; per-document relative resolution is handled by each file's
/// `<base href>` (docBase), not by this root. In the Quick Look extensions there
/// is no workspace, so `docRoot` is the previewed file's own directory.
/// URLs look like: markee-doc://doc/image.png  → <docRoot>/image.png
public final class DocSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated public static let scheme = "markee-doc"
    public private(set) var docRoot: URL

    public init(docRoot: URL) {
        self.docRoot = docRoot
        super.init()
    }

    public func setDocRoot(_ url: URL) { self.docRoot = url }

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        guard let candidate = resolveSandboxed(root: docRoot, requestPath: url.path) else {
            fail(task: urlSchemeTask, status: 403, message: "Forbidden"); return
        }
        do {
            let data = try Data(contentsOf: candidate)
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mimeType(for: candidate.pathExtension),
                    "Content-Length": String(data.count),
                ]
            ) else {
                urlSchemeTask.didFailWithError(URLError(.cannotParseResponse)); return
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            fail(task: urlSchemeTask, status: 404, message: "Not found")
        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fail(task: WKURLSchemeTask, status: Int, message: String) {
        guard let requestURL = task.request.url,
              let response = HTTPURLResponse(
                  url: requestURL,
                  statusCode: status,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "text/plain"]
              ) else {
            task.didFailWithError(URLError(.cannotParseResponse)); return
        }
        task.didReceive(response)
        task.didReceive(Data(message.utf8))
        task.didFinish()
    }
}

/// Resolve a request path against `root` and confirm the result stays inside.
/// Returns nil on any escape — `..`, symlinks pointing out, or boundary-attack
/// siblings (`/notes_sibling` against root `/notes`). Leading slashes are
/// stripped, so a leading-slash path is treated as relative to root (it does
/// not escape; a non-existent target simply 404s downstream).
///
/// `requestPath` must already be percent-DECODED (as `URL.path` is). It is not
/// decoded again: a second decode made a file literally named `100%25.png`
/// unreachable. Encoded traversal (`%2e%2e`) is still blocked because `URL.path`
/// decodes it to `..`, which symlink-resolution then collapses before the
/// boundary check. The check uses a trailing slash so the sibling-dir attack is
/// blocked; the exact-equal allowance covers a request for the root itself.
public func resolveSandboxed(root: URL, requestPath: String) -> URL? {
    var path = requestPath
    while path.hasPrefix("/") { path.removeFirst() }
    let candidate = root.appendingPathComponent(path).resolvingSymlinksInPath()
    let rootResolvedPath = root.resolvingSymlinksInPath().path
    let boundary = rootResolvedPath + "/"
    if candidate.path == rootResolvedPath { return candidate }
    if candidate.path.hasPrefix(boundary) { return candidate }
    return nil
}

public func mimeType(for ext: String) -> String {
    switch ext.lowercased() {
    case "html", "htm": return "text/html; charset=utf-8"
    case "js", "mjs": return "application/javascript; charset=utf-8"
    case "css": return "text/css; charset=utf-8"
    case "json": return "application/json; charset=utf-8"
    case "svg": return "image/svg+xml"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    case "ttf": return "font/ttf"
    case "otf": return "font/otf"
    case "md", "markdown": return "text/markdown; charset=utf-8"
    case "txt": return "text/plain; charset=utf-8"
    default: return "application/octet-stream"
    }
}
