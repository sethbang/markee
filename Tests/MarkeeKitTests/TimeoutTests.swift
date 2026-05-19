import XCTest
@testable import MarkeeKit

final class TimeoutTests: XCTestCase {
    func test_returnsValue_whenOperationFinishesInTime() async throws {
        let value = try await withTimeout(seconds: 1.0) {
            try await Task.sleep(nanoseconds: 10_000_000) // 10 ms
            return 42
        }
        XCTAssertEqual(value, 42)
    }

    func test_throwsTimeoutError_whenOperationIsTooSlow() async {
        do {
            _ = try await withTimeout(seconds: 0.05) {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 s
                return 1
            }
            XCTFail("expected a timeout error")
        } catch is TimeoutError {
            // expected
        } catch {
            XCTFail("expected TimeoutError, got \(error)")
        }
    }
}
