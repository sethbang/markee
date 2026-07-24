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

    @State private var showStats = false
    @State private var beat: CGFloat = 1.0
    // Timer publisher + onReceive ties the heartbeat to the view's lifetime
    // (auto-cancels on disappear); a hand-rolled Timer in onAppear would leak
    // past the window closing and need manual invalidation.
    private let heartbeat = Timer.publish(every: 40, on: .main, in: .common).autoconnect()

    // Reserved gutter widths around the traffic-light cluster so the centered
    // filename stays visually centered in the window.
    private let leftGutter: CGFloat = 78
    private let rightGutter: CGFloat = 78

    var body: some View {
        ZStack {
            // Centered filename
            if let name = fileName, !name.isEmpty {
                Text(name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(titlebarTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 110) // clears the sidebar toggle on the left
            }

            // Left: spacer for traffic lights + sidebar toggle
            HStack(spacing: 0) {
                Color.clear.frame(width: leftGutter)
                if fileName != nil {
                    Button(action: onToggleOutline) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(toggleIconColor)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Toggle outline")
                    .accessibilityLabel(isOutlineVisible ? "Hide outline" : "Show outline")
                    .padding(.leading, 6)
                }
                if fileName != nil {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(canGoBack ? toggleIconColor : toggleIconColor.opacity(0.35))
                            .frame(width: 22, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!canGoBack).help("Back")
                    Button(action: onForward) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(canGoForward ? toggleIconColor : toggleIconColor.opacity(0.35))
                            .frame(width: 22, height: 24)
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
                            Image(systemName: "heart")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(toggleIconColor)
                                .scaleEffect(beat)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Support Markee")
                        .accessibilityLabel("Support Markee")
                        .padding(.trailing, 10)
                        .popover(isPresented: $showStats, arrowEdge: .bottom) { drawer }
                        .onReceive(heartbeat) { _ in
                            if !showStats { pulse() }
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

    // A subtle, occasional double-beat (lub-dub) so the heart catches the eye
    // without nagging. Paused while the popover is open.
    private func pulse() {
        withAnimation(.easeOut(duration: 0.16)) { beat = 1.16 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeIn(duration: 0.16)) { beat = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.easeOut(duration: 0.14)) { beat = 1.10 }
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
