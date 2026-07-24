import AppKit

/// Per-window pinning settings and their pure mappings to AppKit window
/// properties. Pure and value-typed so the mappings are unit-testable with no
/// `NSWindow`.
struct WindowPinState: Equatable {
    enum SpaceMode: Equatable { case normal, allSpaces, followActive }

    var floatOnTop = false
    var spaceMode: SpaceMode = .normal
    var ghostMode = false

    var windowLevel: NSWindow.Level { floatOnTop ? .floating : .normal }

    /// Merge the pin behavior into the window's original collection behavior,
    /// replacing any existing Space-assignment bits (`.canJoinAllSpaces`,
    /// `.moveToActiveSpace`) with the current pin setting and preserving all
    /// other bits. Starting from the captured original each time means toggling
    /// any mode back off restores native behavior exactly.
    func collectionBehavior(
        startingFrom original: NSWindow.CollectionBehavior
    ) -> NSWindow.CollectionBehavior {
        var b = original
        b.remove([.canJoinAllSpaces, .moveToActiveSpace])
        switch spaceMode {
        case .normal:       break
        case .allSpaces:    b.insert(.canJoinAllSpaces)
        case .followActive: b.insert(.moveToActiveSpace)
        }
        return b
    }

    func targetAlpha(isKey: Bool, isHovering: Bool) -> CGFloat {
        (ghostMode && floatOnTop && !isKey && !isHovering) ? 0.75 : 1.0
    }

    // MARK: - Mutators (menu commands route through these)

    /// Ghost mode is only meaningful while floating, so unpinning clears it —
    /// otherwise the menu item would render checked-but-disabled.
    mutating func toggleFloatOnTop() {
        floatOnTop.toggle()
        if !floatOnTop { ghostMode = false }
    }
    mutating func toggleGhostMode() { ghostMode.toggle() }

    /// The two Space toggles share one enum, so enabling one structurally
    /// disables the other; re-toggling the active mode returns to `.normal`.
    mutating func toggleAllSpaces() {
        spaceMode = (spaceMode == .allSpaces) ? .normal : .allSpaces
    }
    mutating func toggleFollowActive() {
        spaceMode = (spaceMode == .followActive) ? .normal : .followActive
    }
}
