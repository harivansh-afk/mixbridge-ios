import XCTest

/// Extension providing async testing utilities for XCTestCase
extension XCTestCase {

    // MARK: - Async Expectations

    /// Waits for an async operation with a timeout
    /// - Parameters:
    ///   - timeout: Maximum time to wait in seconds
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    func waitForAsync<T>(
        timeout: TimeInterval = 5.0,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withTimeout(timeout) {
            try await operation()
        }
    }

    /// Runs an async operation with a timeout, throwing if exceeded
    private func withTimeout<T>(
        _ timeout: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AsyncTestError.timeout(timeout)
            }

            guard let result = try await group.next() else {
                throw AsyncTestError.noResult
            }

            group.cancelAll()
            return result
        }
    }

    // MARK: - Async Assertions

    /// Asserts that an async operation throws a specific error
    func assertThrowsAsync<T, E: Error & Equatable>(
        _ expectedError: E,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected error \(expectedError) but operation succeeded", file: file, line: line)
        } catch let error as E {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        } catch {
            XCTFail("Expected error \(expectedError) but got \(error)", file: file, line: line)
        }
    }

    /// Asserts that an async operation throws any error
    func assertThrowsAnyAsync<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected error but operation succeeded", file: file, line: line)
        } catch {
            // Success - error was thrown
        }
    }

    /// Asserts that an async operation completes without error
    func assertNoThrowAsync<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping () async throws -> T
    ) async -> T? {
        do {
            return try await operation()
        } catch {
            XCTFail("Expected no error but got \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - MainActor Testing

    /// Runs a test on the main actor with proper isolation
    @MainActor
    func runOnMainActor<T>(
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        try await operation()
    }

    // MARK: - Eventually Assertions

    /// Waits for a condition to become true within a timeout
    func waitUntil(
        timeout: TimeInterval = 5.0,
        pollInterval: TimeInterval = 0.1,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () async -> Bool
    ) async {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        XCTFail("Condition not met within \(timeout) seconds", file: file, line: line)
    }

    /// Asserts that a value eventually equals the expected value
    func assertEventually<T: Equatable>(
        _ expected: T,
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        getValue: @escaping () async -> T
    ) async {
        await waitUntil(timeout: timeout, file: file, line: line) {
            await getValue() == expected
        }
    }
}

// MARK: - Async Test Errors

enum AsyncTestError: Error, LocalizedError {
    case timeout(TimeInterval)
    case noResult

    var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "Async operation timed out after \(seconds) seconds"
        case .noResult:
            return "Async operation returned no result"
        }
    }
}

// MARK: - Test Expectation Helpers

extension XCTestCase {

    /// Creates a named expectation and returns it
    func asyncExpectation(description: String) -> XCTestExpectation {
        expectation(description: description)
    }

    /// Fulfills an expectation on the main thread safely
    func fulfillOnMain(_ expectation: XCTestExpectation) {
        DispatchQueue.main.async {
            expectation.fulfill()
        }
    }
}
