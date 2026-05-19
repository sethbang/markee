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
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        // First task to finish wins; cancel the loser before returning.
        for try await result in group {
            group.cancelAll()
            return result
        }
        throw TimeoutError() // unreachable: the group always holds two tasks
    }
}
