import AppKit

/// Applies a `WindowPinState` to a hosting `NSWindow`. Extracted from
/// `PreviewController` so the pin logic is testable in isolation.
@MainActor
final class WindowPinController: NSObject {
    private let windowProvider: () -> NSWindow?
    private(set) var state = WindowPinState()

    /// The window's collection behavior captured before we ever touched it, so
    /// unpinning restores it exactly.
    private var originalBehavior: NSWindow.CollectionBehavior?

    private var hoverView: HoverTrackingView?
    private var isHovering = false
    private var keyObserversInstalled = false

    init(windowProvider: @escaping () -> NSWindow?) {
        self.windowProvider = windowProvider
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(_ newState: WindowPinState) {
        state = newState
        apply()
    }

    func apply() {
        guard let window = windowProvider() else { return }
        if originalBehavior == nil { originalBehavior = window.collectionBehavior }
        window.level = state.windowLevel
        window.collectionBehavior =
            state.collectionBehavior(startingFrom: originalBehavior ?? [])

        if state.ghostMode && state.floatOnTop {
            enableGhostTracking(in: window)
        } else {
            disableGhostTracking()
        }
        recomputeAlpha()
    }

    private func recomputeAlpha() {
        guard let window = windowProvider() else { return }
        window.alphaValue = state.targetAlpha(
            isKey: window.isKeyWindow, isHovering: isHovering)
    }

    private func enableGhostTracking(in window: NSWindow) {
        if hoverView == nil, let content = window.contentView {
            let view = HoverTrackingView(frame: content.bounds)
            view.autoresizingMask = [.width, .height]
            view.onHoverChange = { [weak self] hovering in
                guard let self else { return }
                self.isHovering = hovering
                self.recomputeAlpha()
            }
            content.addSubview(view)
            hoverView = view
        }
        if !keyObserversInstalled {
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(keyStateChanged),
                           name: NSWindow.didBecomeKeyNotification, object: window)
            nc.addObserver(self, selector: #selector(keyStateChanged),
                           name: NSWindow.didResignKeyNotification, object: window)
            keyObserversInstalled = true
        }
    }

    private func disableGhostTracking() {
        hoverView?.removeFromSuperview()
        hoverView = nil
        if keyObserversInstalled {
            let nc = NotificationCenter.default
            nc.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            nc.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
            keyObserversInstalled = false
        }
        isHovering = false
    }

    @objc private func keyStateChanged() { recomputeAlpha() }
}

/// A transparent overlay that reports mouse enter/exit without intercepting
/// clicks (`hitTest` returns nil). Used only while ghost mode is active so the
/// pinned window restores full opacity on hover.
private final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
