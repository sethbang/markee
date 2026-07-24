import XCTest
import AppKit
@testable import Markee

@MainActor
final class WindowPinControllerTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        w.collectionBehavior = [.fullScreenPrimary]
        return w
    }

    func test_floatOnTop_setsFloatingLevel() {
        let window = makeWindow()
        let pin = WindowPinController(windowProvider: { window })
        var s = WindowPinState(); s.floatOnTop = true
        pin.update(s)
        XCTAssertEqual(window.level, .floating)
    }

    func test_unpin_restoresNormalLevel() {
        let window = makeWindow()
        let pin = WindowPinController(windowProvider: { window })
        var s = WindowPinState(); s.floatOnTop = true
        pin.update(s)
        s.floatOnTop = false
        pin.update(s)
        XCTAssertEqual(window.level, .normal)
    }

    func test_allSpaces_addsBehaviorPreservingOriginal() {
        let window = makeWindow()
        let pin = WindowPinController(windowProvider: { window })
        var s = WindowPinState(); s.spaceMode = .allSpaces
        pin.update(s)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
    }

    func test_clearingSpaceMode_restoresOriginalBehavior() {
        let window = makeWindow()
        let original = window.collectionBehavior
        let pin = WindowPinController(windowProvider: { window })
        var s = WindowPinState(); s.spaceMode = .allSpaces
        pin.update(s)
        s.spaceMode = .normal
        pin.update(s)
        XCTAssertEqual(window.collectionBehavior, original)
    }

    func test_ghostMode_dimsWhenFloatingAndNotKey() {
        let window = makeWindow()   // not ordered front, so not key
        let pin = WindowPinController(windowProvider: { window })
        var s = WindowPinState(); s.floatOnTop = true; s.ghostMode = true
        pin.update(s)
        XCTAssertEqual(window.alphaValue, 0.75, accuracy: 0.001)
    }

    func test_ghostMode_fullAlphaWhenDisabled() {
        let window = makeWindow()
        let pin = WindowPinController(windowProvider: { window })
        var s = WindowPinState(); s.floatOnTop = true; s.ghostMode = true
        pin.update(s)
        s.ghostMode = false
        pin.update(s)
        XCTAssertEqual(window.alphaValue, 1.0, accuracy: 0.001)
    }

    func test_ghostMode_fullAlphaWhenFloatOnTopDisabled() {
        let window = makeWindow()
        let pin = WindowPinController(windowProvider: { window })
        var s = WindowPinState(); s.floatOnTop = true; s.ghostMode = true
        pin.update(s)
        s.floatOnTop = false        // unpin while ghostMode flag remains set
        pin.update(s)
        XCTAssertEqual(window.alphaValue, 1.0, accuracy: 0.001)
    }
}
