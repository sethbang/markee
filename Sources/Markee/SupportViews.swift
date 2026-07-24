import AppKit
import SwiftUI

struct SupportDrawer: View {
    @ObservedObject var support: SupportController
    @ObservedObject var usage: UsageTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You and Markee")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 6) {
                statRow(UsageStats.grouped(usage.stats.documentsPreviewed), "documents previewed")
                statRow(UsageStats.grouped(usage.stats.rerendersWatched), "re-renders watched")
                statRow(UsageStats.grouped(usage.stats.activeDays), "days with Markee")
                statRow(UsageStats.grouped(usage.stats.boxesChecked), "boxes checked")
            }

            Text("Markee's been handy. If you'd like to keep it going:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Support Markee") { support.openCheckout() }
                Button("Enter Key…") { support.presentLicenseEntry() }
            }
            .font(.system(size: 12))

            HStack(spacing: 5) {
                Image(systemName: "lock.fill").font(.system(size: 9))
                Text("These numbers never leave your Mac.")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 260)
    }

    private func statRow(_ value: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .frame(width: 64, alignment: .trailing)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

struct SupportCommands: Commands {
    // Menu labels track isSupporter via this ObservedObject (verified to flip
    // live on activation in sandbox e2e). The About box additionally reads
    // isSupporter at click-time inside its closure, so it stays correct even if
    // a future SwiftUI build stops re-evaluating Commands.body on publish.
    @ObservedObject var controller = SupportController.shared

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Markee") {
                var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
                if controller.isSupporter {
                    options[.credits] = NSAttributedString(
                        string: "❤️ Thanks for supporting Markee",
                        attributes: [.font: NSFont.systemFont(ofSize: 11)])
                }
                NSApp.orderFrontStandardAboutPanel(options: options)
            }
        }
        CommandGroup(after: .appInfo) {
            if controller.isSupporter {
                Button("❤️ You're a Supporter") {}.disabled(true)
            } else if controller.nudgesActive {
                Button("Support Markee…") { controller.openCheckout() }
                Button("Enter License Key…") { controller.presentLicenseEntry() }
            }
        }
    }
}
