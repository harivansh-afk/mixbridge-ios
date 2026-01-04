//
//  OperationQueue.swift
//  mixbridge
//
//  Serial async operation queue for sync operations.
//  Ensures operations are executed in order, preventing race conditions.
//  Pattern adapted from Phia.
//

import Foundation

/// Actor that serializes async operations
/// Operations are chained so each waits for the previous to complete
actor SyncOperationQueue {
    private var tail: Task<Void, Never>?

    /// Run an operation serially, waiting for any previous operation to complete
    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail

        // Detach so caller cancellation doesn't cancel queued work
        let current = Task.detached { () throws -> T in
            // Wait for previous operation to finish
            _ = await previous?.value
            return try await operation()
        }

        // Advance tail to wait for current to finish
        tail = Task.detached {
            _ = try? await current.value
        }

        return try await current.value
    }

    /// Run an operation that doesn't throw
    func run<T: Sendable>(_ operation: @escaping @Sendable () async -> T) async -> T {
        let previous = tail

        let current = Task.detached { () -> T in
            _ = await previous?.value
            return await operation()
        }

        tail = Task.detached {
            _ = await current.value
        }

        return await current.value
    }
}
