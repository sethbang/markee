import AppKit
import SwiftUI

/// Developer-only menu, revealed by MARKEE_DEV_TOOLS=1. Only Deactivate This Mac
/// contacts Polar, so routine testing consumes none of the 3 activation slots.
struct DebugCommands: Commands {
    @ObservedObject var controller = SupportController.shared

    // The gate wraps CommandMenu itself, not its contents: a conditional
    // *inside* the menu would still add an empty "Debug" title to the menu bar
    // in a normal build.
    var body: some Commands {
        if SupportConfig.devTools {
            CommandMenu("Debug") {
                Button(controller.isSupporter ? "✓ Supporter Status" : "Supporter Status") {
                    controller.setSupporter(!controller.isSupporter)
                }
                Button("Reset Nudge Timers") {
                    controller.resetNudgeTimers()
                    Self.info("Nudge Timers Reset",
                              "First-launch date, launch count, last-shown dates, and celebrated milestones cleared.")
                }
                Button("Preview Milestone Celebration") {
                    controller.debugCelebrate(UsageTracker.shared.stats)
                }
                Divider()
                Button("License State…") {
                    Self.info("License State", controller.debugStateSummary())
                }
                Button("Deactivate This Mac") {
                    Task {
                        let message = await controller.deactivateThisMac()
                        Self.info("Deactivate This Mac", message)
                    }
                }
            }
        }
    }

    private static func info(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.runModal()
    }
}
