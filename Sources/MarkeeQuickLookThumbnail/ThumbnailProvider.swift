import Cocoa
import QuickLookThumbnailing
import WebKit
import MarkeeKit

/// Carries an `NSImage` across the `withTimeout` task boundary. `NSImage` is
/// not `Sendable`; this is safe because the snapshot is never mutated after
/// capture.
private struct SnapshotBox: @unchecked Sendable {
    let image: NSImage
}

/// Quick Look thumbnail principal class. Renders the file in an offscreen
/// WebView, snapshots the top of the page, and draws that onto a white
/// document card. A timeout falls back to the system's generic doc icon.
final class ThumbnailProvider: QLThumbnailProvider {
    /// US-letter-ish page proportions (width / height).
    private static let pageAspect: CGFloat = 8.5 / 11.0

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        Task {
            do {
                let snapshot = try await withTimeout(seconds: 2.5) { [fileURL = request.fileURL] in
                    try await Self.renderSnapshot(fileURL: fileURL)
                }
                let contextSize = thumbnailContextSize(
                    maximumSize: request.maximumSize,
                    pageAspect: Self.pageAspect)
                guard contextSize.width > 0, contextSize.height > 0 else {
                    handler(nil, nil); return
                }
                let reply = QLThumbnailReply(contextSize: contextSize) {
                    Self.drawCard(image: snapshot.image,
                                  in: CGRect(origin: .zero, size: contextSize))
                    return true
                }
                handler(reply, nil)
            } catch {
                // Timeout or render failure: no thumbnail → system shows DocIcon.
                handler(nil, nil)
            }
        }
    }

    /// Render the file in an offscreen WebView and snapshot the top of the page.
    @MainActor
    private static func renderSnapshot(fileURL: URL) async throws -> SnapshotBox {
        let pageWidth: CGFloat = 850
        let pageHeight: CGFloat = pageWidth / pageAspect
        let pageRect = NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = WebRenderer(docRoot: fileURL.deletingLastPathComponent())
        renderer.webView.frame = pageRect

        // WKWebView snapshots reliably only when hosted in a window.
        let window = NSWindow(contentRect: pageRect,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = renderer.webView
        // Thumbnails are drawn on a white card and cached by Finder across
        // appearance switches: always render the light theme.
        window.appearance = NSAppearance(named: .aqua)
        renderer.webView.appearance = NSAppearance(named: .aqua)

        try await renderer.loadTemplate()
        try await renderer.waitUntilReady()

        let source = try readFileWithFallback(at: fileURL)
        try await renderer.render(source: source,
                                  fileName: fileURL.lastPathComponent,
                                  readOnly: true)
        try Task.checkCancellation()

        // Fixed settle delay: render() resolves when the synchronous JS call
        // returns, but layout — and async Mermaid — may still be in flight.
        // A diagram-heavy document may therefore thumbnail with diagrams only
        // partially drawn; an accepted limitation within the 2.5s budget.
        try await Task.sleep(nanoseconds: 200_000_000)
        try Task.checkCancellation()

        let config = WKSnapshotConfiguration()
        config.rect = pageRect
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            renderer.webView.takeSnapshot(with: config) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? TimeoutError())
                }
            }
        }
        // Keep the offscreen window (which owns the webView's backing store)
        // alive until the async snapshot above has completed.
        withExtendedLifetime(window) {}
        return SnapshotBox(image: image)
    }

    /// Draw a white rounded "document card" with the rendered snapshot clipped
    /// to its top, scaled to fill the card width.
    private static func drawCard(image: NSImage, in rect: CGRect) {
        let radius = min(rect.width, rect.height) * 0.05
        let card = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.white.setFill()
        card.fill()

        card.addClip()
        // Scale the snapshot to the card width; pin it to the top of the card.
        let scale = rect.width / max(image.size.width, 1)
        let drawnHeight = image.size.height * scale
        let drawRect = CGRect(x: rect.minX,
                              y: rect.maxY - drawnHeight,
                              width: rect.width,
                              height: drawnHeight)
        image.draw(in: drawRect,
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1.0)

        NSColor(white: 0.0, alpha: 0.12).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()
    }
}
