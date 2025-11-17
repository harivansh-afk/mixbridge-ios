//
//  BackgroundExecutor.swift
//  mixbridge
//
//  Created by Codex on 11/19/25.
//

import Foundation

enum BackgroundExecutor {
    static func run<T>(
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await Task.detached(priority: priority) {
            try await operation()
        }.value
    }

    static func run(
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () async -> Void
    ) async {
        await Task.detached(priority: priority) {
            await operation()
        }.value
    }
}
