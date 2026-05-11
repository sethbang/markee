import SwiftUI
import WebKit

struct PreviewView: View {
    let fileURL: URL?

    var body: some View {
        Group {
            if let url = fileURL {
                PreviewContent(fileURL: url)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 0) {
            MarkeeTitlebar(
                fileName: nil,
                isOutlineVisible: false,
                onToggleOutline: {}
            )
            VStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No file open").font(.title3).foregroundStyle(.secondary)
                Text("Use File ▸ Open… or drop a Markdown file on the Dock icon.")
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowAccessor { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        })
    }
}

private struct PreviewContent: View {
    @StateObject private var controller: PreviewController

    init(fileURL: URL) {
        _controller = StateObject(wrappedValue: PreviewController(fileURL: fileURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            MarkeeTitlebar(
                fileName: controller.fileURL.lastPathComponent,
                isOutlineVisible: controller.showOutline,
                onToggleOutline: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        controller.showOutline.toggle()
                    }
                }
            )
            HStack(spacing: 0) {
                OutlineSidebar(controller: controller)
                    .frame(width: controller.showOutline ? 220 : 0)
                    .opacity(controller.showOutline ? 1 : 0)
                    .clipped()
                ZStack(alignment: .top) {
                    WebViewRepresentable(controller: controller)
                    if let msg = controller.errorBanner {
                        ErrorBanner(message: msg) {
                            controller.errorBanner = nil
                        }
                        .padding(.top, 6).padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowAccessor { window in
            configureWindow(window)
        })
    }

    private func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
    }
}

private struct OutlineSidebar: View {
    @ObservedObject var controller: PreviewController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No header label — sidebar's existence + filename in titlebar is enough.
            Color.clear.frame(height: 10)

            if controller.outline.isEmpty {
                Text("No headings")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.outline) { entry in
                            OutlineRow(entry: entry, controller: controller)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)
        }
    }

    private var sidebarBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil {
                return NSColor(red: 0x16/255.0, green: 0x17/255.0, blue: 0x1b/255.0, alpha: 1)
            } else {
                return NSColor(red: 0xf1/255.0, green: 0xf2/255.0, blue: 0xf5/255.0, alpha: 1)
            }
        })
    }
}

private struct OutlineRow: View {
    let entry: OutlineEntry
    @ObservedObject var controller: PreviewController
    @State private var isHovered: Bool = false

    private var isActive: Bool {
        controller.currentHeadingID == entry.id
    }

    var body: some View {
        Button {
            controller.scrollToHeading(entry.id)
        } label: {
            Text(entry.title)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, leadingIndent)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 2)
            }
        }
        .onHover { isHovered = $0 }
        .help(entry.title)
    }

    private var leadingIndent: CGFloat {
        switch entry.level {
        case 1: return 16
        case 2: return 28
        default: return 40
        }
    }

    private var fontSize: CGFloat {
        entry.level >= 3 ? 12 : 12.5
    }

    private var fontWeight: Font.Weight {
        entry.level == 1 ? .medium : .regular
    }

    private var textColor: Color {
        if isActive {
            // Active rows brighten to the H1 color regardless of level.
            return Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
                    ? NSColor(red: 0xf4/255, green: 0xf5/255, blue: 0xf8/255, alpha: 1)
                    : NSColor(red: 0x0f/255, green: 0x10/255, blue: 0x14/255, alpha: 1)
            })
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
            switch entry.level {
            case 1:
                return isDark
                    ? NSColor(red: 0xcf/255, green: 0xd0/255, blue: 0xd6/255, alpha: 1)
                    : NSColor(red: 0x2b/255, green: 0x2d/255, blue: 0x34/255, alpha: 1)
            case 2:
                return isDark
                    ? NSColor(red: 0x9c/255, green: 0x9e/255, blue: 0xa7/255, alpha: 1)
                    : NSColor(red: 0x5a/255, green: 0x5c/255, blue: 0x64/255, alpha: 1)
            default:
                return isDark
                    ? NSColor(red: 0x7d/255, green: 0x7f/255, blue: 0x87/255, alpha: 1)
                    : NSColor(red: 0x7a/255, green: 0x7d/255, blue: 0x86/255, alpha: 1)
            }
        })
    }

    private var accentColor: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
                ? NSColor(red: 0xf3/255, green: 0xa2/255, blue: 0x6e/255, alpha: 1)
                : NSColor(red: 0xa8/255, green: 0x54/255, blue: 0x28/255, alpha: 1)
        })
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isActive {
            // Whisper-faint tinted background using the accent color
            accentColor.opacity(0.06)
        } else if isHovered {
            Color.primary.opacity(0.03)
        } else {
            Color.clear
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.tertiary.opacity(0.4)))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }
}

private struct WebViewRepresentable: NSViewRepresentable {
    let controller: PreviewController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
