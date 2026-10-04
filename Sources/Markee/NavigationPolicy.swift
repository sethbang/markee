import Foundation
import UniformTypeIdentifiers
import MarkeeKit

/// What the preview WebView may navigate to. The main frame only ever holds
/// `template.html` — every document change is an in-place re-render — so any
/// other main-frame load would replace the preview (and hand the `markee`
/// bridge to whatever page arrived).
enum NavigationDecision: Equatable {
    case allow
    case cancel
    /// User clicked an external link: hand it to the default browser/mail app.
    case openExternally(URL)
    /// User clicked a non-Markdown workspace file (`markee-doc://` path).
    case openWorkspaceFile(path: String)
    /// User clicked a link with a scheme we refuse to hand off.
    case blockedScheme(String)
}

enum NavigationPolicy {
    static let externalSchemes: Set<String> = ["http", "https", "mailto"]

    static func isTemplate(_ url: URL) -> Bool {
        url.scheme == BundleSchemeHandler.scheme && url.host == "app" && url.path == "/template.html"
    }

    /// - Parameters:
    ///   - isMainFrame: false only for subframe navigations; a nil target frame
    ///     (`target=_blank`) counts as main-frame.
    ///   - isLinkActivated: the navigation came from a user click.
    static func decide(url: URL, isMainFrame: Bool, isLinkActivated: Bool) -> NavigationDecision {
        let scheme = url.scheme?.lowercased() ?? ""
        if !isMainFrame {
            return scheme == "about" ? .allow : .cancel
        }
        if isTemplate(url) { return isLinkActivated ? .cancel : .allow }
        guard isLinkActivated else { return .cancel }
        if scheme == DocSchemeHandler.scheme {
            // .md clicks are intercepted in JS (in-window nav); one that slips
            // through must not load raw Markdown into the main frame.
            if ["md", "markdown"].contains(url.pathExtension.lowercased()) { return .cancel }
            return .openWorkspaceFile(path: url.path)
        }
        if externalSchemes.contains(scheme) { return .openExternally(url) }
        return .blockedScheme(scheme.isEmpty ? "?" : scheme)
    }

    /// Workspace files a click may open in their default app. Anything else
    /// (scripts, `.command`, app bundles…) is revealed in Finder instead, so a
    /// document link can never launch an executable.
    static func isSafeToOpen(_ fileURL: URL) -> Bool {
        guard let type = UTType(filenameExtension: fileURL.pathExtension) else { return false }
        let safe: [UTType] = [.image, .pdf, .audiovisualContent, .plainText]
        return safe.contains { type.conforms(to: $0) }
            && !type.conforms(to: .sourceCode)
            && !type.conforms(to: .executable)
    }
}
