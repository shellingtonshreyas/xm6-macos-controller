import Foundation

enum BluetoothMainThreadExecutor {
    private final class ResultBox<T>: @unchecked Sendable {
        var result: Result<T, Error>?
    }

    static func run<T>(_ work: @escaping @Sendable () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()

        DispatchQueue.main.async {
            box.result = .success(work())
            semaphore.signal()
        }

        semaphore.wait()
        switch box.result {
        case let .success(value):
            return value
        case .failure, .none:
            preconditionFailure("Main-thread executor received an unexpected failure for a nonthrowing closure.")
        }
    }

    static func runThrowing<T>(_ work: @escaping @Sendable () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try work()
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()

        DispatchQueue.main.async {
            box.result = Result { try work() }
            semaphore.signal()
        }

        semaphore.wait()
        guard let result = box.result else {
            preconditionFailure("Main-thread executor did not receive a result.")
        }

        return try result.get()
    }
}
