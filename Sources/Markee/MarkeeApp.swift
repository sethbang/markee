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
            SupportCommands()
            DebugCommands()
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Updater.shared.checkForUpdatesMenuAction()
                }
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Install Command Line Tool…") {
                    AppDelegate.installCLI()
                }
                Button("Open Folder as Workspace…") {
                    NotificationCenter.default.post(name: .openFolder, object: nil)
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
                // Second Zoom In binding: ⌘= (no Shift). The button above is
                // bound to "+" (⌘⇧= on US layouts); this alias matches the
                // browser-standard ⌘= so users need not hold Shift.
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("=", modifiers: [.command])
                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: [.command])
                Button("Actual Size") {
                    NotificationCenter.default.post(name: .zoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command])

                Divider()
                Button("Reload") {
                    NotificationCenter.default.post(name: .reloadFile, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()
                Button("Back") {
                    NotificationCenter.default.post(name: .navigateBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command])
                Button("Forward") {
                    NotificationCenter.default.post(name: .navigateForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command])
            }
            CommandGroup(after: .saveItem) {
                Button("Export Standalone HTML…") {
                    NotificationCenter.default.post(name: .exportHTML, object: nil)
                }
                .keyboardShortcut("E", modifiers: [.command])
                Button("Export PDF…") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])
                Button("Open in Editor at Current Heading") {
                    NotificationCenter.default.post(name: .openInEditor, object: nil)
                }
                .keyboardShortcut("E", modifiers: [.command, .option])
                Divider()
                Button("Copy Markdown Source") {
                    NotificationCenter.default.post(name: .copyMarkdownSource, object: nil)
                }
                .keyboardShortcut("C", modifiers: [.command, .shift])
                Button("Copy Reflowed Markdown") {
                    NotificationCenter.default.post(name: .copyReflowedMarkdown, object: nil)
                }
                .keyboardShortcut("C", modifiers: [.command, .option])
                Button("Copy as Rendered Text") {
                    NotificationCenter.default.post(name: .copyRenderedText, object: nil)
                }
                .keyboardShortcut("C", modifiers: [.command, .option, .shift])
                Button("Reveal in Finder") {
                    NotificationCenter.default.post(name: .revealInFinder, object: nil)
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
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
                Button("Search Workspace…") {
                    NotificationCenter.default.post(name: .searchPalette, object: nil)
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])
            }
            WindowPinCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let toggleOutline = Notification.Name("MarkeeToggleOutline")
    static let exportHTML = Notification.Name("MarkeeExportHTML")
    static let exportPDF = Notification.Name("MarkeeExportPDF")
    static let openInEditor = Notification.Name("MarkeeOpenInEditor")
    static let findInPreview = Notification.Name("MarkeeFindInPreview")
    static let printPreview = Notification.Name("MarkeePrintPreview")
    static let zoomIn = Notification.Name("MarkeeZoomIn")
    static let zoomOut = Notification.Name("MarkeeZoomOut")
    static let zoomReset = Notification.Name("MarkeeZoomReset")
    static let zoomDidChange = Notification.Name("MarkeeZoomDidChange")
    static let findNext = Notification.Name("MarkeeFindNext")
    static let findPrevious = Notification.Name("MarkeeFindPrevious")
    static let reloadFile = Notification.Name("MarkeeReloadFile")
    static let copyMarkdownSource = Notification.Name("MarkeeCopyMarkdownSource")
    static let copyReflowedMarkdown = Notification.Name("MarkeeCopyReflowedMarkdown")
    static let copyRenderedText = Notification.Name("MarkeeCopyRenderedText")
    static let revealInFinder = Notification.Name("MarkeeRevealInFinder")
    static let toggleFloatOnTop = Notification.Name("MarkeeToggleFloatOnTop")
    static let toggleAllSpaces = Notification.Name("MarkeeToggleAllSpaces")
    static let toggleFollowActive = Notification.Name("MarkeeToggleFollowActive")
    static let toggleGhostMode = Notification.Name("MarkeeToggleGhostMode")
    static let navigateBack = Notification.Name("MarkeeNavigateBack")
    static let navigateForward = Notification.Name("MarkeeNavigateForward")
    static let openFolder = Notification.Name("MarkeeOpenFolder")
    static let searchPalette = Notification.Name("MarkeeSearchPalette")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Stay alive when no windows: matches standard macOS doc-based-app convention
    // (TextEdit, Preview, etc.) and avoids quitting during the brief zero-window
    // transition when SwiftUI's File ▸ Open dialog dismisses before the new
    // document window appears.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Updater.shared.checkOnLaunch()
        EditorLauncher.warmCache()
        SupportController.shared.registerLaunch()
        UsageTracker.shared.recordActiveDay()
        // Resolve the bundled doc before consuming the trigger: consume stamps
        // the 30-day clock, so ordering it first would "spend" the month in any
        // context where the resource is absent (e.g. swift run, no app bundle).
        guard let doc = Bundle.main.url(forResource: "Support Markee", withExtension: "md"),
              SupportController.shared.consumeSupportDocTrigger()
        else { return }
        // Delayed so restored document windows settle first; the support doc
        // opens after them instead of racing window restoration.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSDocumentController.shared.openDocument(
                withContentsOf: doc, display: true, completionHandler: { _, _, _ in })
        }
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
