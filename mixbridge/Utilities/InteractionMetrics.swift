//
//  InteractionMetrics.swift
//  mixbridge
//
//  Lightweight timing utilities for “tap -> UI update” and “tap -> playing”.
//

import Foundation
import OSLog

enum InteractionMetrics {
    struct Token: Sendable {
        let id: UUID
        let name: StaticString
        let startUptimeNs: UInt64
        let context: String
    }

    private static let logger = Logger(subsystem: "mixbridge", category: "perf")

    static func begin(_ name: StaticString, context: String = "") -> Token {
        Token(
            id: UUID(),
            name: name,
            startUptimeNs: DispatchTime.now().uptimeNanoseconds,
            context: context
        )
    }

    static func end(_ token: Token, result: String = "") {
        let endNs = DispatchTime.now().uptimeNanoseconds
        let elapsedMs = Double(endNs &- token.startUptimeNs) / 1_000_000.0
        let ctx = token.context.isEmpty ? "" : " [\(token.context)]"
        let res = result.isEmpty ? "" : " -> \(result)"
        logger.info("\(String(describing: token.name))\(ctx): \(elapsedMs, format: .fixed(precision: 1))ms\(res)")
    }
}
