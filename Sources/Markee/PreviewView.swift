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
    @ObservedObject private var support = SupportController.shared

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
                },
                canGoBack: controller.canGoBack,
                canGoForward: controller.canGoForward,
                onBack: { controller.goBack() },
                onForward: { controller.goForward() },
                showSupport: support.showSupportButton,
                drawer: AnyView(SupportDrawer(support: support, usage: UsageTracker.shared))
            )
            HStack(spacing: 0) {
                OutlineSidebar(controller: controller)
                    .frame(width: controller.showOutline ? 220 : 0)
                    .opacity(controller.showOutline ? 1 : 0)
                    .clipped()
                ZStack(alignment: .top) {
                    WebViewRepresentable(controller: controller)
                    if controller.showFindBar {
                        FindBar(controller: controller)
                            .padding(.top, 6).padding(.trailing, 12)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let msg = controller.errorBanner {
                        ErrorBanner(message: msg) {
                            controller.errorBanner = nil
                        }
                        .padding(.top, controller.showFindBar ? 44 : 6).padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if controller.statsPillVisible {
                        WordCountPill(words: controller.docWords, minutes: controller.docMinutes)
                            .padding(.trailing, 12)
                            .padding(.bottom, 10)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: controller.statsPillVisible)
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowAccessor { window in
            configureWindow(window)
        })
        .overlay {
            if controller.showSearchPalette {
                SearchPalette(controller: controller)
            }
        }
        .focusedSceneValue(\.pinState, controller.pinState)
    }

    private func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Only assign styleMask when it actually changes — reassigning it
        // forces an NSThemeFrame rebuild. This runs on every becomeKey.
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.isMovableByWindowBackground = false
        controller.applyInitialPinStateIfNeeded()
    }
}

private struct OutlineSidebar: View {
    @ObservedObject var controller: PreviewController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $controller.sidebarMode) {
                Text("Outline").tag(PreviewController.SidebarMode.outline)
                Text("Files").tag(PreviewController.SidebarMode.files)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if controller.sidebarMode == .outline {
                outlineContent
            } else {
                FileTreeView(controller: controller)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
        }
    }

    @ViewBuilder
    private var outlineContent: some View {
        if controller.outline.isEmpty {
            Text("No headings")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
                .padding(.horizontal, 16).padding(.top, 4)
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

private struct FileTreeView: View {
    @ObservedObject var controller: PreviewController
    @ObservedObject var workspace: WorkspaceModel

    init(controller: PreviewController) {
        self.controller = controller
        self.workspace = controller.workspace
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if workspace.fileTree.isEmpty {
                    Text("No Markdown files")
                        .foregroundStyle(.tertiary).font(.system(size: 12))
                        .padding(.horizontal, 16).padding(.top, 4)
                } else {
                    let currentPath = controller.fileURL.standardizedFileURL.path
                    ForEach(WorkspaceModel.visibleRows(workspace.fileTree, expanded: workspace.expandedFolders)) { item in
                        FileTreeRow(node: item.node, depth: item.depth,
                                    isExpanded: workspace.expandedFolders.contains(item.id),
                                    isCurrent: !item.node.isDirectory && item.node.url.path == currentPath,
                                    canBeRoot: item.node.isDirectory && controller.canSetWorkspaceRoot(item.node.url),
                                    controller: controller, workspace: workspace)
                            .equatable()
                    }
                }
            }
            .padding(.bottom, 8)
        }
        // Empty space below the rows; each row carries its own copy of the menu.
        .contextMenu { FileTreeMenu(folder: nil, canBeRoot: false, controller: controller) }
        .onAppear(perform: revealCurrentFile)
        .onChange(of: controller.fileURL) { _ in revealCurrentFile() }
        .onChange(of: workspace.root) { _ in revealCurrentFile() }
        .overlay(alignment: .bottom) {
            Button {
                NotificationCenter.default.post(name: .openFolder, object: nil)
            } label: {
                Label("Open Folder…", systemImage: "folder")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(.regularMaterial)
        }
    }

    /// Adds (never removes) the open file's folders, so navigating keeps any
    /// folders the user opened.
    private func revealCurrentFile() {
        workspace.expandedFolders.formUnion(WorkspaceModel.folderIDsRevealing(controller.fileURL, root: workspace.root))
    }
}

/// One flat row. Takes plain values rather than observing the controller, and
/// is Equatable on them, so SwiftUI skips the bodies of rows a change leaves
/// untouched (the parent still recomputes the cheap flat row list).
private struct FileTreeRow: View, Equatable {
    let node: FileNode
    let depth: Int
    let isExpanded: Bool
    let isCurrent: Bool
    /// Contains the open file. Must be a stored value: an Equatable row skips
    /// re-rendering, so its menu can't query the controller at render time
    /// (navigating left folder menus with a stale disabled state).
    let canBeRoot: Bool
    let controller: PreviewController
    let workspace: WorkspaceModel

    static func == (a: Self, b: Self) -> Bool {
        a.node.id == b.node.id && a.node.name == b.node.name && a.depth == b.depth
            && a.isExpanded == b.isExpanded && a.isCurrent == b.isCurrent && a.canBeRoot == b.canBeRoot
    }

    var body: some View {
        Button {
            if node.isDirectory {
                if isExpanded {
                    workspace.expandedFolders.remove(node.id)
                } else {
                    workspace.expandedFolders.insert(node.id)
                }
            } else {
                controller.openFromTree(node.url)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: node.isDirectory
                      ? (isExpanded ? "chevron.down" : "chevron.right")
                      : "doc.text")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(node.name)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(10 + depth * 12))
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isCurrent ? Color.primary.opacity(0.06) : Color.clear)
        .contextMenu {
            FileTreeMenu(folder: node.isDirectory ? node.url : nil, canBeRoot: canBeRoot, controller: controller)
        }
    }
}

/// The Files sidebar's right-click menu: re-rooting on a folder, plus
/// whole-tree expand/collapse anywhere in the panel.
private struct FileTreeMenu: View {
    let folder: URL?
    let canBeRoot: Bool
    let controller: PreviewController

    var body: some View {
        if let folder {
            // A root must contain the open document (its images and links
            // resolve through it), so other folders show the item disabled.
            Button("Set as Workspace Root") { _ = controller.setWorkspaceRoot(folder) }
                .disabled(!canBeRoot)
            Divider()
        }
        Button("Expand All") {
            controller.workspace.expandedFolders = WorkspaceModel.allFolderIDs(in: controller.workspace.fileTree)
        }
        Button("Collapse All") { controller.workspace.expandedFolders = [] }
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
        .contextMenu {
            Button("Open at this Heading in Editor") {
                controller.openInEditor(atLine: entry.line)
            }
            .disabled(entry.line == nil)
            Button("Open in Editor") {
                controller.openInEditor(atLine: nil)
            }
        }
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

private struct FindBar: View {
    @ObservedObject var controller: PreviewController
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Find", text: $controller.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 170)
                .focused($fieldFocused)
                .onSubmit { controller.findNext() }
                .onChange(of: controller.findQuery) { _ in controller.findNext() }
            if controller.findTotal > 0 {
                Text("\(controller.findCurrent) of \(controller.findTotal)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if controller.findNotFound {
                Text("Not found")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Divider().frame(height: 14)
            Button { controller.findPrevious() } label: {
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Previous match")
            Button { controller.findNext() } label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Next match")
            Button { controller.closeFind() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Close find bar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.tertiary.opacity(0.4)))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .onExitCommand { controller.closeFind() }
        .onAppear {
            DispatchQueue.main.async { fieldFocused = true }
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

private struct WordCountPill: View {
    let words: Int
    let minutes: Int

    private var label: String {
        let w = words.formatted(.number)
        let wLabel = words == 1 ? "word" : "words"
        return "\(w) \(wLabel) · \(minutes) min"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.tertiary.opacity(0.3)))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
            .help("\(words) words, about \(minutes) min read")
    }
}

private struct SearchPalette: View {
    @ObservedObject var controller: PreviewController
    @FocusState private var focused: Bool

    var body: some View {
        VStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search workspace…", text: $controller.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focused)
                        .onSubmit {
                            if let first = controller.searchResults.first {
                                controller.chooseSearchResult(first)
                            }
                        }
                }
                .padding(12)
                if !controller.searchResults.isEmpty {
                    Divider()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(controller.searchResults) { r in
                                Button { controller.chooseSearchResult(r) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name).font(.system(size: 13, weight: .medium))
                                        Text(r.snippet).font(.system(size: 11))
                                            .foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            .frame(width: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.tertiary.opacity(0.4)))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(.top, 80)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.001)
                .onTapGesture { controller.showSearchPalette = false }
        )
        .onExitCommand { controller.showSearchPalette = false }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
