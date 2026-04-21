import Foundation

enum BluetoothRunLoopExecutor {
    private static let threadMarkerKey = "SonyMacApp.BluetoothRunLoopExecutor"

    private class TaskBox: NSObject {
        fileprivate func execute() {}
    }

    private final class ThrowingTaskBox<T>: TaskBox {
        private let work: @Sendable () throws -> T
        private let semaphore = DispatchSemaphore(value: 0)
        private var result: Result<T, Error>?

        init(work: @escaping @Sendable () throws -> T) {
            self.work = work
        }

        override func execute() {
            result = Result { try work() }
            semaphore.signal()
        }

        func waitForResult() throws -> T {
            semaphore.wait()
            guard let result else {
                preconditionFailure("Bluetooth run-loop executor did not produce a result.")
            }

            return try result.get()
        }
    }

    private final class Runner: NSObject, @unchecked Sendable {
        @objc func executeTask(_ task: TaskBox) {
            task.execute()
        }
    }

    private final class ExecutorThread: Thread, @unchecked Sendable {
        let readySemaphore = DispatchSemaphore(value: 0)

        override func main() {
            Thread.current.threadDictionary[threadMarkerKey] = true

            let runLoop = RunLoop.current
            let keepAlivePort = Port()
            runLoop.add(keepAlivePort, forMode: .default)
            readySemaphore.signal()

            while !isCancelled {
                _ = autoreleasepool {
                    runLoop.run(mode: .default, before: .distantFuture)
                }
            }
        }
    }

    private static let runner = Runner()

    private static let thread: ExecutorThread = {
        let thread = ExecutorThread()
        thread.name = "SonyMacApp.BluetoothRunLoop"
        thread.qualityOfService = .userInitiated
        thread.start()
        thread.readySemaphore.wait()
        return thread
    }()

    static func run<T>(_ work: @escaping @Sendable () -> T) -> T {
        if isCurrentExecutorThread {
            return work()
        }

        let task = ThrowingTaskBox<T> { work() }
        submit(task)
        do {
            return try task.waitForResult()
        } catch {
            preconditionFailure("Bluetooth run-loop executor received an unexpected failure for a nonthrowing closure.")
        }
    }

    static func runThrowing<T>(_ work: @escaping @Sendable () throws -> T) throws -> T {
        if isCurrentExecutorThread {
            return try work()
        }

        let task = ThrowingTaskBox(work: work)
        submit(task)
        return try task.waitForResult()
    }

    static var isCurrentExecutorThread: Bool {
        Thread.current.threadDictionary[threadMarkerKey] as? Bool == true
    }

    private static func submit(_ task: TaskBox) {
        runner.perform(#selector(Runner.executeTask(_:)), on: thread, with: task, waitUntilDone: false)
    }
}
