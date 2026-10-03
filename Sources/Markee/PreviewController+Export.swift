import AppKit
import WebKit

/// Print, Export PDF and Export Standalone HTML. Reached through the
/// key-window command table in `PreviewController.registerCommands`.
extension PreviewController {
    /// Open the system print panel for the rendered preview. The panel's PDF
    /// menu ("Save as PDF") gives print-to-PDF for free.
    func printPreview() {
        guard let window = webView.window else { return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.topMargin = Self.printMargin
        info.bottomMargin = Self.printMargin
        info.leftMargin = Self.printMargin
        info.rightMargin = Self.printMargin
        let op = webView.printOperation(with: info)
        op.view?.frame = webView.bounds
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func exportPDF() {
        guard let window = webView.window else { return }
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

    @objc func pdfExportDidRun(_ op: NSPrintOperation, success: Bool,
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

    func exportHTML() {
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
}
