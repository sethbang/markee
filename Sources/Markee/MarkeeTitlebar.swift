import SwiftUI
import AppKit

struct MarkeeTitlebar: View {
    let fileName: String?
    let isOutlineVisible: Bool
    let onToggleOutline: () -> Void

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
                            .foregroundStyle(Color.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Toggle outline")
                    .accessibilityLabel(isOutlineVisible ? "Hide outline" : "Show outline")
                    .padding(.leading, 6)
                }
                Spacer()
                Color.clear.frame(width: rightGutter)
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
