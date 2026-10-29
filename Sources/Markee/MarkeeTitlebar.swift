import SwiftUI
import AppKit

struct MarkeeTitlebar: View {
    let fileName: String?
    let isOutlineVisible: Bool
    let onToggleOutline: () -> Void
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var showSupport: Bool = false
    var drawer: AnyView? = nil
    var celebrate: Bool = false
    var isCelebrationPending: () -> Bool = { false }
    var isKeyWindow: () -> Bool = { false }
    var onDrawerShown: () -> Void = {}
    var onDrawerClosed: () -> Void = {}

    @State private var showStats = false
    @State private var beat: CGFloat = 1.0
    @State private var heartFilled = false
    @State private var autoDismiss: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Timer publisher + onReceive ties the heartbeat to the view's lifetime
    // (auto-cancels on disappear); a hand-rolled Timer in onAppear would leak
    // past the window closing and need manual invalidation.
    private let heartbeat = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    // Reserved gutter widths around the traffic-light cluster so the centered
    // filename stays visually centered in the window.
    private let leftGutter: CGFloat = 78
    private let rightGutter: CGFloat = 78
    // Left cluster after the gutter: 6pt lead + sidebar toggle (24) + back and
    // forward chevrons (22 each). Keep in sync with the frames below.
    private let toggleLead: CGFloat = 6
    private let toggleWidth: CGFloat = 24
    private let chevronWidth: CGFloat = 22
    /// Symmetric inset for the centered filename so it never draws under the
    /// left cluster (gutter + toggle + chevrons) or, mirrored, the right side.
    private var titleInset: CGFloat { leftGutter + toggleLead + toggleWidth + 2 * chevronWidth + 4 }

    var body: some View {
        ZStack {
            // Centered filename
            if let name = fileName, !name.isEmpty {
                Text(name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(titlebarTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, titleInset)
            }

            // Left: spacer for traffic lights + sidebar toggle
            HStack(spacing: 0) {
                Color.clear.frame(width: leftGutter)
                if fileName != nil {
                    Button(action: onToggleOutline) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(toggleIconColor)
                            .frame(width: toggleWidth, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Toggle outline")
                    .accessibilityLabel(isOutlineVisible ? "Hide outline" : "Show outline")
                    .padding(.leading, toggleLead)
                }
                if fileName != nil {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(canGoBack ? toggleIconColor : toggleIconColor.opacity(0.35))
                            .frame(width: chevronWidth, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!canGoBack).help("Back")
                    Button(action: onForward) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(canGoForward ? toggleIconColor : toggleIconColor.opacity(0.35))
                            .frame(width: chevronWidth, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!canGoForward).help("Forward")
                }
                Spacer()
                // Support affordance lives inside the reserved right gutter so
                // the centered filename stays centered.
                ZStack(alignment: .trailing) {
                    Color.clear.frame(width: rightGutter)
                    if showSupport, let drawer {
                        Button {
                            showStats.toggle()
                        } label: {
                            Image(systemName: heartFilled ? "heart.fill" : "heart")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.pink.opacity(heartFilled ? 1 : 0.8))
                                .scaleEffect(beat)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Support Markee")
                        .accessibilityLabel("Support Markee")
                        .padding(.trailing, 10)
                        .popover(isPresented: $showStats, arrowEdge: .bottom) {
                            drawer.onHover { if $0 { cancelAutoDismiss() } }
                        }
                        .onReceive(heartbeat) { _ in
                            if !showStats { pulse() }
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { pulse() }
                            openForCelebration()
                        }
                        .onChange(of: celebrate) { _ in openForCelebration() }
                        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                            openForCelebration()
                        }
                        .onChange(of: showStats) { open in
                            if open {
                                onDrawerShown()
                            } else {
                                cancelAutoDismiss()
                                onDrawerClosed()
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 44)
        .background(titlebarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
    }

    // Only the key window opens on a milestone, so one crossing never stacks a
    // popover in every open window. Key-ness comes from the NSWindow, not
    // controlActiveState, which didn't report .key here when a menu item set
    // the milestone. Deferred a turn so a menu that triggered it has finished
    // dismissing before the popover presents. Pending-ness is read through a
    // closure because these callbacks hold a stale copy of this struct, whose
    // `celebrate` was still false when the menu item set it.
    private func openForCelebration() {
        DispatchQueue.main.async {
            guard isCelebrationPending(), isKeyWindow(), !showStats else { return }
            showStats = true
            scheduleAutoDismiss()
        }
    }

    // A milestone opened on its own closes on its own, so it never costs a
    // click; pointing at it (which any click inside starts with) keeps it.
    // A drawer opened from the heart is left alone.
    private static let autoDismissDelay: TimeInterval = 8

    private func scheduleAutoDismiss() {
        cancelAutoDismiss()
        let work = DispatchWorkItem { showStats = false }
        autoDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay, execute: work)
    }

    private func cancelAutoDismiss() {
        autoDismiss?.cancel()
        autoDismiss = nil
    }

    // A rare but unmistakable double-beat (lub-dub): when the window opens,
    // then every few minutes. Paused while the popover is open; with Reduce
    // Motion the heart only fills briefly instead of scaling.
    private func pulse() {
        guard !showStats else { return }
        withAnimation(.easeInOut(duration: 0.2)) { heartFilled = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 0.4)) { heartFilled = false }
        }
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.16)) { beat = 1.35 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeIn(duration: 0.16)) { beat = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.easeOut(duration: 0.14)) { beat = 1.2 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.easeIn(duration: 0.16)) { beat = 1.0 }
                }
            }
        }
    }

    private var titlebarBackground: some View {
        LinearGradient(
            stops: [
                .init(color: titlebarTopColor, location: 0.0),
                .init(color: titlebarBottomColor, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var titlebarTextColor: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil {
                return NSColor(red: 0xcf/255.0, green: 0xd0/255.0, blue: 0xd6/255.0, alpha: 1)
            } else {
                return NSColor(red: 0x3a/255.0, green: 0x3c/255.0, blue: 0x44/255.0, alpha: 1)
            }
        })
    }

    /// Explicit appearance-aware color for the outline-toggle icon, matching
    /// the titlebar's own `NSColor`-backed color treatment.
    private var toggleIconColor: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil {
                return NSColor(red: 0x8c/255.0, green: 0x8e/255.0, blue: 0x97/255.0, alpha: 1)
            } else {
                return NSColor(red: 0x6a/255.0, green: 0x6c/255.0, blue: 0x74/255.0, alpha: 1)
            }
        })
    }

    private var titlebarTopColor: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil {
                return NSColor(red: 0x26/255.0, green: 0x27/255.0, blue: 0x2d/255.0, alpha: 1)
            } else {
                return NSColor(red: 0xee/255.0, green: 0xf0/255.0, blue: 0xf3/255.0, alpha: 1)
            }
        })
    }

    private var titlebarBottomColor: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil {
                return NSColor(red: 0x1f/255.0, green: 0x20/255.0, blue: 0x25/255.0, alpha: 1)
            } else {
                return NSColor.white
            }
        })
    }
}
