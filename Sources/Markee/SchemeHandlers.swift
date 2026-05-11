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
        // Strip leading slash and host
        var path = url.path
        while path.hasPrefix("/") { path.removeFirst() }
        let fileURL = webRoot.appendingPathComponent(path)
        serve(fileURL: fileURL, task: urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func serve(fileURL: URL, task: WKURLSchemeTask) {
        do {
            let data = try Data(contentsOf: fileURL)
            let mime = mimeType(for: fileURL.pathExtension)
            let response = HTTPURLResponse(
                url: task.request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mime,
                    "Content-Length": String(data.count),
                    "Access-Control-Allow-Origin": "*",
                ]
            )!
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch {
            let response = HTTPURLResponse(
                url: task.request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            )!
            task.didReceive(response)
            task.didReceive("Not found: \(fileURL.path)".data(using: .utf8) ?? Data())
            task.didFinish()
        }
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
        var path = url.path
        while path.hasPrefix("/") { path.removeFirst() }
        let decoded = path.removingPercentEncoding ?? path
        let candidate = docRoot.appendingPathComponent(decoded).standardizedFileURL
        // Sandbox: only serve paths inside docRoot
        let rootPath = docRoot.standardizedFileURL.path
        guard candidate.path.hasPrefix(rootPath) else {
            fail(task: urlSchemeTask, status: 403, message: "Forbidden"); return
        }
        do {
            let data = try Data(contentsOf: candidate)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mimeType(for: candidate.pathExtension),
                    "Content-Length": String(data.count),
                ]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            fail(task: urlSchemeTask, status: 404, message: "Not found")
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fail(task: WKURLSchemeTask, status: Int, message: String) {
        let response = HTTPURLResponse(
            url: task.request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!
        task.didReceive(response)
        task.didReceive(message.data(using: .utf8) ?? Data())
        task.didFinish()
    }
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
