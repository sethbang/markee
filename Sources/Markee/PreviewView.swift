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
}

private struct PreviewContent: View {
    @StateObject private var controller: PreviewController

    init(fileURL: URL) {
        _controller = StateObject(wrappedValue: PreviewController(fileURL: fileURL))
    }

    var body: some View {
        HSplitView {
            if controller.showOutline {
                OutlineSidebar(controller: controller)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 360)
            }
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
            .frame(minWidth: 320)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        controller.showOutline.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle outline")
            }
        }
        .navigationTitle(controller.fileURL.lastPathComponent)
    }
}

private struct OutlineSidebar: View {
    @ObservedObject var controller: PreviewController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Outline")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            if controller.outline.isEmpty {
                Text("No headings")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(controller.outline) { entry in
                            Button {
                                controller.scrollToHeading(entry.id)
                            } label: {
                                Text(entry.title)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                    .padding(.leading, CGFloat(max(0, entry.level - 1)) * 10 + 12)
                                    .padding(.vertical, 3)
                                    .padding(.trailing, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(.clear)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor.controlBackgroundColor))
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
