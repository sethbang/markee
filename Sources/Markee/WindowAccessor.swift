import SwiftUI
import AppKit

/// SwiftUI helper that surfaces the hosting `NSWindow` and keeps the
/// integrated-titlebar configuration applied to it.
///
/// `onAttach` sets `titlebarAppearsTransparent`, `titleVisibility`, and
/// `.fullSizeContentView`. AppKit resets `titlebarAppearsTransparent` back to
/// `false` as part of window reactivation — and does so a beat *after* the
/// `didBecomeKey` / `didBecomeMain` notifications fire, so re-applying on
/// those notifications is clobbered milliseconds later. Instead, the
/// coordinator observes `titlebarAppearsTransparent` directly with KVO and
/// re-runs `onAttach` whenever the property is knocked back to `false`. KVO
/// change callbacks are synchronous, so the property is corrected within the
/// same runloop turn — before the window draws — leaving no visible flicker.
struct WindowAccessor: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window, onAttach: onAttach)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // If the view wasn't yet in a window during makeNSView, retry on update.
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window, onAttach: onAttach)
        }
    }

    /// Owns the KVO guard that keeps the titlebar configuration durable across
    /// window reactivation. Internal (not private) so it can be unit-tested.
    @MainActor
    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private var transparencyGuard: NSKeyValueObservation?

        /// Apply `onAttach` to `window` now, and re-apply it whenever AppKit
        /// resets `titlebarAppearsTransparent` back to `false`.
        func attach(to window: NSWindow?, onAttach: @escaping (NSWindow) -> Void) {
            guard let window else { return }
            onAttach(window)

            guard observedWindow !== window else { return }
            observedWindow = window
            // Assigning a new observation releases (and invalidates) any
            // previous one, so re-attaching to a different window is safe.
            // The guard captures this call's `onAttach`; for Markee that
            // closure only writes window chrome, so holding the first one is
            // equivalent to holding any later one.
            transparencyGuard = window.observe(
                \.titlebarAppearsTransparent, options: [.new]
            ) { observed, change in
                // React only to AppKit knocking it false; our own re-apply
                // sets it true, which re-fires KVO and stops here.
                guard change.newValue == false else { return }
                onAttach(observed)
            }
        }
    }
}
