import Foundation

/// Thrown by `withTimeout` when the operation does not finish in time.
public struct TimeoutError: Error {
    public init() {}
}

/// Run `operation`, racing it against a deadline. If `operation` finishes
/// first its value is returned; if the deadline wins, `TimeoutError` is thrown
/// *at the deadline* and the operation is cancelled.
///
/// Not a task group: a group can't return until every child finishes, so an
/// operation that ignores cancellation (blocking work, a WebKit callback that
/// never fires) held the caller far past its budget — a 0.2 s timeout returned
/// after 2 s. Here the operation runs in an unstructured task and the caller is
/// resumed by whichever side finishes first; a straggler's result is dropped.
public func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = TimeoutRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.install(continuation)
            let op = Task {
                do { race.finish(.success(try await operation())) } catch { race.finish(.failure(error)) }
            }
            let timer = Task {
                try? await Task.sleep(for: .seconds(seconds))
                race.finish(.failure(TimeoutError()))
            }
            race.onFinish { op.cancel(); timer.cancel() }
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

/// Resume-once state shared by the operation, the timer and cancellation.
private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var result: Result<T, Error>?
    private var cleanup: (() -> Void)?
    private var done = false

    func install(_ c: CheckedContinuation<T, Error>) {
        lock.lock()
        if let result {           // cancelled before the continuation existed
            lock.unlock()
            c.resume(with: result)
            return
        }
        continuation = c
        lock.unlock()
    }

    func onFinish(_ body: @escaping () -> Void) {
        lock.lock()
        if done { lock.unlock(); body(); return }
        cleanup = body
        lock.unlock()
    }

    func finish(_ r: Result<T, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = r
        done = true
        let c = continuation
        let body = cleanup
        continuation = nil
        cleanup = nil
        lock.unlock()
        c?.resume(with: r)
        body?()
    }
}
