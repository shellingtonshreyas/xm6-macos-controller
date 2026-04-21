import XCTest
@testable import SonyMacApp

final class BluetoothMainThreadExecutorTests: XCTestCase {
    func testRunExecutesWorkOnMainThreadWhenCalledFromBackground() async throws {
        let isMainThread = try await runFromBackground {
            BluetoothMainThreadExecutor.run {
                Thread.isMainThread
            }
        }

        XCTAssertTrue(isMainThread)
    }

    func testRunThrowingPropagatesErrorFromMainThreadWork() async {
        await XCTAssertThrowsErrorAsync(
            try await runFromBackground {
                try BluetoothMainThreadExecutor.runThrowing {
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
