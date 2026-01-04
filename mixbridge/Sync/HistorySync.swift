//
//  HistorySync.swift
//  mixbridge
//
//  Synchronizes play history between Convex backend and local GRDB database.
//  Supports optimistic updates for immediate UI feedback.
//

import Foundation
import MixBridgeDB

final class HistorySync: Sendable {
    private let db = MixBridgeDB.shared
    private let convex = ConvexService.shared
    private let operationQueue = SyncOperationQueue()

    static let shared = HistorySync()
    private init() {}

    // MARK: - Sync History from Backend

    /// Fetch play history from Convex and save to local database
    func syncHistory(userId: String, limit: Int = 100) async throws {
        try await operationQueue.run { [self] in
            // 1. Fetch from API
            let history = try await convex.getPlayHistory(userId: userId, limit: limit)

            // 2. Save to DB
            try await db.writer.write { db in
                for playItem in history {
                    // Save track
                    var track = PersistedTrack(from: playItem.trackData)
                    try track.upsert(db)

                    // Calculate listened percentage
                    let percentage: Double
                    if let position = playItem.playbackPosition, let duration = playItem.duration, duration > 0 {
                        percentage = min(position / duration, 1.0)
                    } else {
                        percentage = playItem.listenedPercentage ?? 0
                    }

                    // Create/update history record
                    let trackId = String(playItem.trackData.id)
                    var historyRecord: PlayHistory

                    if let existing = try PlayHistory.fetchOne(db, key: trackId) {
                        // Update existing record
                        historyRecord = existing
                        historyRecord.playCount += 1
                        historyRecord.lastPlayedPosition = playItem.playbackPosition ?? existing.lastPlayedPosition
                        historyRecord.listenedPercentage = max(percentage, existing.listenedPercentage)
                        historyRecord.updatedAt = Date(timeIntervalSince1970: playItem.playedAt / 1000)
                    } else {
                        // Create new record
                        let playedAt = Date(timeIntervalSince1970: playItem.playedAt / 1000)
                        historyRecord = PlayHistory(
                            trackId: trackId,
                            playCount: 1,
                            lastPlayedPosition: playItem.playbackPosition ?? 0,
                            listenedPercentage: percentage,
                            createdAt: playedAt,
                            updatedAt: playedAt
                        )
                    }

                    try historyRecord.upsert(db)
                }
            }

            logInfo(.sync, "Synced \(history.count) history items")
        }
    }

    // MARK: - Optimistic Add to History

    /// Add a track to history with optimistic update
    /// Updates local DB immediately, syncs to backend in background
    func addToHistory(_ scTrack: SoundCloudTrack, userId: String, sessionId: String, queueIndex: Int?) async throws {
        let trackId = String(scTrack.id)
        let now = Date()

        // 1. Optimistic update to local DB
        try await db.writer.write { db in
            // Save track
            var track = PersistedTrack(from: scTrack)
            try track.upsert(db)

            // Update or create history record
            var history: PlayHistory
            if let existing = try PlayHistory.fetchOne(db, key: trackId) {
                history = existing
                history.playCount += 1
                history.updatedAt = now
            } else {
                history = PlayHistory(
                    trackId: trackId,
                    playCount: 1,
                    lastPlayedPosition: 0,
                    listenedPercentage: 0,
                    createdAt: now,
                    updatedAt: now
                )
            }
            try history.upsert(db)
        }

        // 2. Sync to backend in background (fire and forget)
        Task(priority: .utility) { [convex] in
            do {
                try await convex.addPlay(
                    userId: userId,
                    track: scTrack,
                    sessionId: sessionId,
                    queueIndex: queueIndex
                )
            } catch {
                logError(.sync, "Failed to sync play to backend: \(error)")
                // Optimistic update stays - no rollback needed for history
            }
        }
    }

    // MARK: - Update Play Position

    /// Update playback position for a track
    func updatePlayPosition(trackId: String, position: Double, percentage: Double) async throws {
        try await db.writer.write { db in
            if var history = try PlayHistory.fetchOne(db, key: trackId) {
                history.lastPlayedPosition = position
                history.listenedPercentage = max(percentage, history.listenedPercentage)
                history.updatedAt = Date()
                try history.update(db)
            }
        }
    }

    // MARK: - Local Queries

    /// Get play history from local database, ordered by most recent
    func getLocalHistory(limit: Int = 100) async throws -> [PlayHistoryWithTrack] {
        try await db.reader.read { db in
            try PlayHistory
                .including(required: PlayHistory.track)
                .order(PlayHistory.Columns.updatedAt.desc)
                .limit(limit)
                .asRequest(of: PlayHistoryWithTrack.self)
                .fetchAll(db)
        }
    }
}
