import AppKit

/// Stands in as the window's delegate to veto a close, forwarding every
/// delegate call to the delegate it displaced (SwiftUI's), which keeps working
/// as before. `NSWindow.delegate` is weak: the owner must keep this alive.
@MainActor
final class WindowCloseGuard: NSObject, NSWindowDelegate {
    private let shouldClose: () -> Bool
    private weak var original: NSWindowDelegate?

    init(shouldClose: @escaping () -> Bool) {
        self.shouldClose = shouldClose
    }

    /// Idempotent; re-installs over whatever delegate replaced it since.
    func install(on window: NSWindow) {
        guard window.delegate !== self else { return }
        original = window.delegate
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shouldClose() else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || original?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original?.responds(to: aSelector) == true ? original : super.forwardingTarget(for: aSelector)
    }
}
