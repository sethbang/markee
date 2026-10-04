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
            _ = try await withTimeout(seconds: 0.2) {
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

    /// An operation that ignores cancellation must not hold the caller past
    /// the deadline (the thumbnail extension's 2.5 s budget depends on it).
    func test_returnsAtDeadline_evenIfOperationIgnoresCancellation() async {
        let start = Date()
        do {
            _ = try await withTimeout(seconds: 0.2) { () async throws -> Int in
                usleep(2_000_000)   // non-cooperative: blocks, never checks cancellation
                return 1
            }
            XCTFail("expected a timeout error")
        } catch {
            XCTAssertTrue(error is TimeoutError)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func test_propagatesOperationError() async {
        struct Boom: Error {}
        do {
            _ = try await withTimeout(seconds: 1) { () async throws -> Int in throw Boom() }
            XCTFail("expected Boom")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    func test_callerCancellationThrows() async {
        let task = Task {
            try await withTimeout(seconds: 5) { () async throws -> Int in
                try await Task.sleep(for: .seconds(5)); return 1
            }
        }
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get())
    }
}
