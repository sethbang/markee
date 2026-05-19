import XCTest
import CoreGraphics
@testable import MarkeeKit

final class ThumbnailLayoutTests: XCTestCase {
    // pageAspect = width / height. A US-letter-ish page is 0.773 (8.5/11).
    func test_fitsPageInsideASquareBudget_heightIsLimiting() {
        let size = thumbnailContextSize(maximumSize: CGSize(width: 100, height: 100),
                                        pageAspect: 0.773)
        // Tall page: height pins to 100, width follows aspect.
        XCTAssertEqual(size.height, 100, accuracy: 0.001)
        XCTAssertEqual(size.width, 77.3, accuracy: 0.1)
    }

    func test_fitsPageInsideAWideBudget_widthIsLimiting() {
        let size = thumbnailContextSize(maximumSize: CGSize(width: 40, height: 100),
                                        pageAspect: 0.773)
        // Narrow budget: width pins to 40, height follows aspect.
        XCTAssertEqual(size.width, 40, accuracy: 0.001)
        XCTAssertEqual(size.height, 51.74, accuracy: 0.1)
    }

    func test_neverExceedsTheBudgetInEitherDimension() {
        let size = thumbnailContextSize(maximumSize: CGSize(width: 256, height: 256),
                                        pageAspect: 0.773)
        XCTAssertLessThanOrEqual(size.width, 256)
        XCTAssertLessThanOrEqual(size.height, 256)
    }

    func test_zeroBudgetReturnsZero() {
        let size = thumbnailContextSize(maximumSize: .zero, pageAspect: 0.773)
        XCTAssertEqual(size.width, 0, accuracy: 0.001)
        XCTAssertEqual(size.height, 0, accuracy: 0.001)
    }
}
