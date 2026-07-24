import SwiftUI

/// Surfaces the focused document window's pin state to the app-global Window
/// menu so checkmarks/enablement reflect the right window. `nil` when no Markee
/// document window is focused (incl. the placeholder window) — which disables
/// the items for free. Actions still route via NotificationCenter.
private struct PinStateKey: FocusedValueKey {
    typealias Value = WindowPinState
}

extension FocusedValues {
    var pinState: WindowPinState? {
        get { self[PinStateKey.self] }
        set { self[PinStateKey.self] = newValue }
    }
}

struct WindowPinCommands: Commands {
    @FocusedValue(\.pinState) private var pinState: WindowPinState?

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Divider()

            Toggle("Float on Top", isOn: command(.toggleFloatOnTop) { $0.floatOnTop })
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(pinState == nil)

            Toggle("Visible on All Spaces",
                   isOn: command(.toggleAllSpaces) { $0.spaceMode == .allSpaces })
                .disabled(pinState == nil)

            Toggle("Move to Active Space",
                   isOn: command(.toggleFollowActive) { $0.spaceMode == .followActive })
                .disabled(pinState == nil)

            Divider()

            Toggle("Ghost Mode",
                   isOn: command(.toggleGhostMode) { $0.ghostMode })
                .disabled(!(pinState?.floatOnTop ?? false))
        }
    }

    /// A checkbox binding whose value is read from the focused window's state
    /// and whose toggle posts a NotificationCenter command (the key window's
    /// PreviewController performs the actual mutation).
    private func command(
        _ name: Notification.Name,
        read: @escaping (WindowPinState) -> Bool
    ) -> Binding<Bool> {
        Binding(
            get: { pinState.map(read) ?? false },
            set: { _ in NotificationCenter.default.post(name: name, object: nil) }
        )
    }
}
