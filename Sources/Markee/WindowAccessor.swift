import SwiftUI
import AppKit

/// SwiftUI helper that surfaces the hosting `NSWindow` once it's attached.
/// Use as a `.background(...)` modifier. The closure runs once per window
/// attachment.
struct WindowAccessor: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onAttach(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // If the view wasn't yet in a window during makeNSView, retry on update.
        DispatchQueue.main.async {
            if let window = nsView.window {
                onAttach(window)
            }
        }
    }
}
