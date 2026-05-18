import XCTest
@testable import Markee

final class ZoomTests: XCTestCase {
    func test_zoomIn_steppsUpOneRung() {
        XCTAssertEqual(nextZoom(from: 1.0, direction: .in), 1.1, accuracy: 0.0001)
    }

    func test_zoomOut_stepsDownOneRung() {
        XCTAssertEqual(nextZoom(from: 1.0, direction: .out), 0.9, accuracy: 0.0001)
    }

    func test_zoomIn_clampsAtTop() {
        XCTAssertEqual(nextZoom(from: 3.0, direction: .in), 3.0, accuracy: 0.0001)
    }

    func test_zoomOut_clampsAtBottom() {
        XCTAssertEqual(nextZoom(from: 0.5, direction: .out), 0.5, accuracy: 0.0001)
    }

    func test_offLadderInput_snapsToNearestRungThenSteps() {
        // 1.04 is nearest to the 1.0 rung; stepping in lands on 1.1.
        XCTAssertEqual(nextZoom(from: 1.04, direction: .in), 1.1, accuracy: 0.0001)
        XCTAssertEqual(nextZoom(from: 1.04, direction: .out), 0.9, accuracy: 0.0001)
    }

    func test_steppingUpRepeatedlyReachesTop() {
        var level = 0.5
        for _ in 0..<20 { level = nextZoom(from: level, direction: .in) }
        XCTAssertEqual(level, 3.0, accuracy: 0.0001)
    }
}
