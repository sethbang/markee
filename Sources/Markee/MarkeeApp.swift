import SwiftUI
import UniformTypeIdentifiers

@main
struct MarkeeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            PreviewView(fileURL: configuration.fileURL)
                .frame(minWidth: 480, minHeight: 360)
        }
        .defaultSize(width: 1000, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                Button("Install Command Line Tool…") {
                    AppDelegate.installCLI()
                }
            }
            CommandGroup(after: .toolbar) {
                Button("Toggle Outline") {
                    NotificationCenter.default.post(name: .toggleOutline, object: nil)
                }
                .keyboardShortcut("\\", modifiers: [.command, .option])

                Divider()
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: [.command])
                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: [.command])
                Button("Actual Size") {
                    NotificationCenter.default.post(name: .zoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
            CommandGroup(after: .saveItem) {
                Button("Export Standalone HTML…") {
                    NotificationCenter.default.post(name: .exportHTML, object: nil)
                }
                .keyboardShortcut("E", modifiers: [.command])
                Button("Open in Editor at Current Heading") {
                    NotificationCenter.default.post(name: .openInEditor, object: nil)
                }
                .keyboardShortcut("E", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    NotificationCenter.default.post(name: .printPreview, object: nil)
                }
                .keyboardShortcut("P", modifiers: [.command])
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    NotificationCenter.default.post(name: .findInPreview, object: nil)
                }
                .keyboardShortcut("F", modifiers: [.command])
                Button("Find Next") {
                    NotificationCenter.default.post(name: .findNext, object: nil)
                }
                .keyboardShortcut("G", modifiers: [.command])
                Button("Find Previous") {
                    NotificationCenter.default.post(name: .findPrevious, object: nil)
                }
                .keyboardShortcut("G", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let toggleOutline = Notification.Name("MarkeeToggleOutline")
    static let exportHTML = Notification.Name("MarkeeExportHTML")
    static let openInEditor = Notification.Name("MarkeeOpenInEditor")
    static let findInPreview = Notification.Name("MarkeeFindInPreview")
    static let printPreview = Notification.Name("MarkeePrintPreview")
    static let zoomIn = Notification.Name("MarkeeZoomIn")
    static let zoomOut = Notification.Name("MarkeeZoomOut")
    static let zoomReset = Notification.Name("MarkeeZoomReset")
    static let zoomDidChange = Notification.Name("MarkeeZoomDidChange")
    static let findNext = Notification.Name("MarkeeFindNext")
    static let findPrevious = Notification.Name("MarkeeFindPrevious")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Stay alive when no windows: matches standard macOS doc-based-app convention
    // (TextEdit, Preview, etc.) and avoids quitting during the brief zero-window
    // transition when SwiftUI's File ▸ Open dialog dismisses before the new
    // document window appears.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    static func installCLI() {
        guard let bundleCLI = Bundle.main.url(forResource: "cli/markee", withExtension: nil) else {
            NSSound.beep(); return
        }
        let target = URL(fileURLWithPath: "/usr/local/bin/markee")
        let panel = NSAlert()
        panel.messageText = "Install 'markee' CLI"
        panel.informativeText = "Symlink \(bundleCLI.path) to \(target.path)?\n\nIf /usr/local/bin isn't writable, you'll be told to run the command in Terminal manually."
        panel.addButton(withTitle: "Install")
        panel.addButton(withTitle: "Cancel")
        guard panel.runModal() == .alertFirstButtonReturn else { return }
        do {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: bundleCLI)
            let ok = NSAlert(); ok.messageText = "Installed"; ok.informativeText = "You can now run 'markee <file>' from Terminal."; ok.runModal()
        } catch {
            let cmd = "sudo ln -sf \"\(bundleCLI.path)\" \"\(target.path)\""
            let a = NSAlert()
            a.messageText = "Could not write to /usr/local/bin"
            a.informativeText = "Run this in Terminal:\n\n\(cmd)"
            a.runModal()
        }
    }
}
