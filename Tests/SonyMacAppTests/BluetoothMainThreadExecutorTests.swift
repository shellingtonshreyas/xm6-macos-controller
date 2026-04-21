import XCTest
@testable import SonyMacApp

final class BluetoothMainThreadExecutorTests: XCTestCase {
    func testRunExecutesWorkOnBluetoothExecutorThreadWhenCalledFromBackground() async throws {
        let executionContext = try await runFromBackground {
            BluetoothRunLoopExecutor.run {
                (BluetoothRunLoopExecutor.isCurrentExecutorThread, Thread.isMainThread)
            }
        }

        XCTAssertTrue(executionContext.0)
        XCTAssertFalse(executionContext.1)
    }

    func testRunThrowingPropagatesErrorFromExecutorWork() async {
        await XCTAssertThrowsErrorAsync(
            try await runFromBackground {
                try BluetoothRunLoopExecutor.runThrowing {
                    throw ExecutorTestError.forcedFailure
                }
            }
        ) { error in
            XCTAssertEqual(error as? ExecutorTestError, .forcedFailure)
        }
    }
}

private enum ExecutorTestError: Error, Equatable {
    case forcedFailure
}

private func runFromBackground<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                continuation.resume(returning: try work())
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw an error.", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
