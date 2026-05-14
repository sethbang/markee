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
        }
    }
}

extension Notification.Name {
    static let toggleOutline = Notification.Name("MarkeeToggleOutline")
    static let exportHTML = Notification.Name("MarkeeExportHTML")
    static let openInEditor = Notification.Name("MarkeeOpenInEditor")
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
