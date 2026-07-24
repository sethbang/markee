import XCTest
import AppKit
@testable import Markee

final class WindowPinStateTests: XCTestCase {
    func test_windowLevel_floatsOnlyWhenFloatOnTop() {
        var s = WindowPinState()
        XCTAssertEqual(s.windowLevel, .normal)
        s.floatOnTop = true
        XCTAssertEqual(s.windowLevel, .floating)
    }

    func test_collectionBehavior_normalPreservesOriginal() {
        let s = WindowPinState()
        let result = s.collectionBehavior(startingFrom: [.fullScreenPrimary])
        XCTAssertEqual(result, [.fullScreenPrimary])
    }

    func test_collectionBehavior_allSpacesAddsCanJoinAllSpaces() {
        var s = WindowPinState()
        s.spaceMode = .allSpaces
        let result = s.collectionBehavior(startingFrom: [.fullScreenPrimary])
        XCTAssertTrue(result.contains(.canJoinAllSpaces))
        XCTAssertFalse(result.contains(.moveToActiveSpace))
        XCTAssertTrue(result.contains(.fullScreenPrimary))
    }

    func test_collectionBehavior_followActiveAddsMoveToActiveSpace() {
        var s = WindowPinState()
        s.spaceMode = .followActive
        let result = s.collectionBehavior(startingFrom: [])
        XCTAssertTrue(result.contains(.moveToActiveSpace))
        XCTAssertFalse(result.contains(.canJoinAllSpaces))
    }

    func test_targetAlpha_dimsOnlyWhenGhostFloatingUnfocusedAndNotHovered() {
        var s = WindowPinState()
        s.ghostMode = true
        s.floatOnTop = true
        XCTAssertEqual(s.targetAlpha(isKey: false, isHovering: false), 0.75)
        XCTAssertEqual(s.targetAlpha(isKey: true, isHovering: false), 1.0)
        XCTAssertEqual(s.targetAlpha(isKey: false, isHovering: true), 1.0)
    }

    func test_targetAlpha_fullWhenGhostOffOrNotFloating() {
        var s = WindowPinState()
        s.ghostMode = false
        s.floatOnTop = true
        XCTAssertEqual(s.targetAlpha(isKey: false, isHovering: false), 1.0)
        s.ghostMode = true
        s.floatOnTop = false
        XCTAssertEqual(s.targetAlpha(isKey: false, isHovering: false), 1.0)
    }

    func test_toggleSpaceModes_areMutuallyExclusive() {
        var s = WindowPinState()
        s.toggleAllSpaces()
        XCTAssertEqual(s.spaceMode, .allSpaces)
        s.toggleAllSpaces()
        XCTAssertEqual(s.spaceMode, .normal)         // re-toggle clears allSpaces
        s.toggleFollowActive()
        XCTAssertEqual(s.spaceMode, .followActive)
        s.toggleAllSpaces()
        XCTAssertEqual(s.spaceMode, .allSpaces)      // switching modes is exclusive
        s.toggleFollowActive()
        XCTAssertEqual(s.spaceMode, .followActive)   // not both
        s.toggleFollowActive()
        XCTAssertEqual(s.spaceMode, .normal)         // re-toggle clears followActive
    }

    func test_toggleFloatOnTop_flips() {
        var s = WindowPinState()
        s.toggleFloatOnTop()
        XCTAssertTrue(s.floatOnTop)
        s.toggleFloatOnTop()
        XCTAssertFalse(s.floatOnTop)
    }

    func test_toggleFloatOnTop_clearsGhostModeWhenUnpinning() {
        var s = WindowPinState()
        s.toggleFloatOnTop()
        s.toggleGhostMode()
        XCTAssertTrue(s.ghostMode)
        s.toggleFloatOnTop()                  // unpin
        XCTAssertFalse(s.ghostMode)
    }
}
