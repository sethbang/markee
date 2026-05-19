import Foundation

/// Thrown by `withTimeout` when the operation does not finish in time.
public struct TimeoutError: Error {
    public init() {}
}

/// Run `operation`, racing it against a deadline. If `operation` finishes
/// first its value is returned; if the deadline wins, the operation task is
/// cancelled and `TimeoutError` is thrown.
public func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
