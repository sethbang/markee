import Foundation
import WebKit

/// Serves files from the app bundle's Resources/web/ directory.
/// URLs look like: markee-app://app/template.html, markee-app://app/vendor/katex/katex.min.css
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "markee-app"
    private let webRoot: URL

    override init() {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        self.webRoot = resources.appendingPathComponent("web", isDirectory: true)
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        guard let candidate = resolveSandboxed(root: webRoot, requestPath: url.path) else {
            fail(task: urlSchemeTask, status: 403, message: "Forbidden"); return
        }
        serve(fileURL: candidate, task: urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

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
                    "Access-Control-Allow-Origin": "*",
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
            task.didReceive("Not found: \(fileURL.path)".data(using: .utf8) ?? Data())
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
        task.didReceive(message.data(using: .utf8) ?? Data())
        task.didFinish()
    }
}

/// Serves files from a specific document directory. One instance per WebView.
/// URLs look like: markee-doc://doc/image.png  → /path/to/doc-dir/image.png
final class DocSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "markee-doc"
    private(set) var docRoot: URL

    init(docRoot: URL) {
        self.docRoot = docRoot
        super.init()
    }

    func setDocRoot(_ url: URL) { self.docRoot = url }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
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

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

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
        task.didReceive(message.data(using: .utf8) ?? Data())
        task.didFinish()
    }
}

/// Resolve a request path against `root` and confirm the result stays inside.
/// Returns nil on any escape — `..`, percent-encoded `%2e%2e`, absolute paths,
/// symlinks pointing out, or boundary-attack siblings (`/notes_sibling`
/// against root `/notes`).
///
/// Path is URL-decoded once, then appended to root, then symlink-resolved on
/// both sides. The boundary check uses a trailing slash so the sibling-dir
/// attack is blocked. The exact-equal allowance covers the root-itself case
/// (rare but possible if a request asks for the root directory).
func resolveSandboxed(root: URL, requestPath: String) -> URL? {
    var path = requestPath
    while path.hasPrefix("/") { path.removeFirst() }
    let decoded = path.removingPercentEncoding ?? path
    let candidate = root.appendingPathComponent(decoded).resolvingSymlinksInPath()
    let rootResolvedPath = root.resolvingSymlinksInPath().path
    let boundary = rootResolvedPath + "/"
    if candidate.path == rootResolvedPath { return candidate }
    if candidate.path.hasPrefix(boundary) { return candidate }
    return nil
}

func mimeType(for ext: String) -> String {
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
