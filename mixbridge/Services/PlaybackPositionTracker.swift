//
//  PlaybackPositionTracker.swift
//  mixbridge
//
//  Batched position tracking - flushes to Convex every 10 seconds
//  Follows Netflix/Spotify pattern: batch writes, not per-second
//

import Foundation

/// Tracks playback position and flushes to Convex every 10 seconds
@MainActor
final class PlaybackPositionTracker {
    static let shared = PlaybackPositionTracker()

    private let convexService = ConvexService.shared
    private let flushInterval: TimeInterval = 10.0

    private var currentSessionId: String?
    private var currentTrackId: String?
    private var currentQueueIndex: Int?
    private var lastPosition: Double = 0
    private var lastDuration: Double = 0
    private var lastFlushTime: Date = Date()

    private init() {}

    /// Start tracking a new play session
    /// Returns a unique session ID for this play event
    func startSession(trackId: String, queueIndex: Int?, duration: Double) -> String {
        // End any existing session first
        if currentSessionId != nil {
            flush()
        }

        let sessionId = UUID().uuidString
        currentSessionId = sessionId
        currentTrackId = trackId
        currentQueueIndex = queueIndex
        lastPosition = 0
        lastDuration = duration
        lastFlushTime = Date()

        #if DEBUG
        print("📍 Position tracking started: session=\(sessionId.prefix(8)), track=\(trackId), queueIndex=\(queueIndex ?? -1)")
        #endif

        return sessionId
    }

    /// Update position (called frequently from time observer ~0.5s)
    /// Only flushes to server every 10 seconds
    func updatePosition(_ position: Double, duration: Double) {
        guard currentSessionId != nil else { return }

        lastPosition = position
        lastDuration = duration

        // Check if we should flush (every 10 seconds)
        if Date().timeIntervalSince(lastFlushTime) >= flushInterval {
            flush()
        }
    }

    /// Force flush current position to Convex (call on pause/stop)
    func flush() {
        guard let sessionId = currentSessionId,
              let userId = AuthManager.shared.currentUserId,
              lastPosition > 0 else {
            return
        }

        lastFlushTime = Date()
        let position = lastPosition
        let duration = lastDuration

        #if DEBUG
        let percentage = duration > 0 ? (position / duration) * 100 : 0
        print("💾 Flushing position: \(String(format: "%.1f", position))s / \(String(format: "%.1f", duration))s (\(String(format: "%.0f", percentage))%)")
        #endif

        Task {
            try? await convexService.updatePlayPosition(
                sessionId: sessionId,
                userId: userId,
                playbackPosition: position,
                duration: duration
            )
        }
    }

    /// End current session (flushes final position)
    func endSession() {
        guard currentSessionId != nil else { return }

        #if DEBUG
        print("📍 Position tracking ended: session=\(currentSessionId?.prefix(8) ?? "none")")
        #endif

        flush()
        currentSessionId = nil
        currentTrackId = nil
        currentQueueIndex = nil
        lastPosition = 0
        lastDuration = 0
    }

    /// Get current session ID (for logging initial play)
    var sessionId: String? { currentSessionId }
    var queueIndex: Int? { currentQueueIndex }
}
