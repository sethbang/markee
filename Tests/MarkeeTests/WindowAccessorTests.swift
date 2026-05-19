import XCTest
import AppKit
@testable import Markee

@MainActor
final class WindowAccessorTests: XCTestCase {
    func test_attachAppliesConfigurationImmediately() {
        let window = NSWindow()
        let coordinator = WindowAccessor.Coordinator()
        var applyCount = 0
        coordinator.attach(to: window) { _ in applyCount += 1 }
        XCTAssertEqual(applyCount, 1)
    }

    func test_restoresTitlebarTransparencyWhenAppKitClobbersIt() {
        let window = NSWindow()
        window.titlebarAppearsTransparent = true
        let coordinator = WindowAccessor.Coordinator()
        var applyCount = 0
        coordinator.attach(to: window) { w in
            w.titlebarAppearsTransparent = true
            applyCount += 1
        }
        XCTAssertEqual(applyCount, 1)

        // Reproduce the bug: AppKit resets this during window reactivation.
        window.titlebarAppearsTransparent = false

        XCTAssertTrue(window.titlebarAppearsTransparent,
                      "the KVO guard must restore titlebar transparency")
        XCTAssertEqual(applyCount, 2, "onAttach must re-run when transparency is clobbered")
    }

    func test_ignoresTransparencyChangesOnOtherWindows() {
        let window = NSWindow()
        let other = NSWindow()
        other.titlebarAppearsTransparent = true
        let coordinator = WindowAccessor.Coordinator()
        var applyCount = 0
        coordinator.attach(to: window) { w in
            w.titlebarAppearsTransparent = true
            applyCount += 1
        }

        other.titlebarAppearsTransparent = false
        XCTAssertEqual(applyCount, 1, "another window's change must not trigger re-apply")
    }
}
