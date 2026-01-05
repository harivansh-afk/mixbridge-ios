//
//  QueueSync.swift
//  mixbridge
//
//  Local-first queue sync:
//  - Persists queue state to local GRDB for instant UI + offline continuity
//  - Syncs to Convex/REST in background
//  - Mirrors Convex queue/queueTracks fields (see mixbridge-web/convex/schema.ts)
//

import Foundation
import MixBridgeDB

final class QueueSync: Sendable {
    static let shared = QueueSync()

    private let db = MixBridgeDB.shared
    private let convex = ConvexService.shared
    private let operationQueue = SyncOperationQueue()

    /// Convex search cache TTL is 10 minutes; queue has no TTL, but we keep local state indefinitely.
    private init() {}

    // MARK: - Local Persistence

    func loadLocalQueueItems(userId: String) async throws -> [QueueItem] {
        let rows: [PersistedQueueTrack] = try await db.reader.read { db in
            let rows = try PersistedQueueTrack
                .filter(PersistedQueueTrack.Columns.queueUserId == userId)
                .order(PersistedQueueTrack.Columns.position)
                .fetchAll(db)
            return rows
        }

        // SoundCloud models may be main-actor isolated in this project; decode on MainActor.
        return await MainActor.run {
            rows.compactMap { row in
                guard let scTrack = try? JSONDecoder().decode(SoundCloudTrack.self, from: row.trackData) else { return nil }
                return QueueItem(
                    id: row.id,
                    serverId: row.serverId,
                    trackId: row.trackId,
                    track: scTrack.toTrack(),
                    soundCloudTrack: scTrack
                )
            }
        }
    }

    func persistQueueSnapshot(userId: String, items: [QueueItem], convexQueueId: String? = nil) async throws {
        let now = Date()

        // Precompute DB rows outside the write transaction (and on MainActor if needed).
        let prepared: [PersistedQueueTrack] = await MainActor.run {
            items.enumerated().compactMap { index, item in
                guard let scTrack = item.soundCloudTrack else { return nil }
                guard let encoded = try? JSONEncoder().encode(scTrack) else { return nil }

                return PersistedQueueTrack(
                    id: item.id,
                    serverId: item.serverId,
                    queueUserId: userId,
                    trackId: item.trackId,
                    source: "soundcloud",
                    title: item.track.title,
                    artist: item.track.artist,
                    duration: Double(scTrack.duration),
                    artworkUrl: scTrack.artwork_url ?? scTrack.user.avatar_url,
                    trackData: encoded,
                    position: index,
                    createdAt: now,
                    updatedAt: now
                )
            }
        }

        try await db.writer.write { db in
            // Ensure queue row exists (one per user)
            var queueRow = (try PersistedQueue.fetchOne(db, key: userId)) ?? PersistedQueue(id: userId)
            if let convexQueueId { queueRow.convexQueueId = convexQueueId }
            queueRow.updatedAt = now
            try queueRow.upsert(db)

            // Replace queue tracks for this user in one transaction
            try PersistedQueueTrack
                .filter(PersistedQueueTrack.Columns.queueUserId == userId)
                .deleteAll(db)

            for row in prepared {
                try row.insert(db)
            }
        }
    }

    // MARK: - Remote Sync (Convex → Local)

    func syncQueueFromServer(userId: String) async throws -> [QueueItem] {
        try await operationQueue.run { [self] in
            let localBefore = (try? await loadLocalQueueItems(userId: userId)) ?? []
            let localPending = localBefore.filter { $0.serverId == nil }

            let queue = try await convex.getQueueWithTracks(userId: userId)
            guard let queue else {
                // No server queue yet; keep local (including pending).
                return localBefore
            }

            let ordered = queue.tracks.sorted { $0.position < $1.position }
            var serverItems: [QueueItem] = await MainActor.run {
                ordered.map { qt in
                    QueueItem(
                        id: qt._id,
                        serverId: qt._id,
                        trackId: qt.trackId,
                        track: qt.trackData.toTrack(),
                        soundCloudTrack: qt.trackData
                    )
                }
            }

            // Preserve any optimistic local additions that haven't synced yet.
            // Avoid duplicates by trackId.
            let serverTrackIds = Set(serverItems.map(\.trackId))
            let pendingToKeep = localPending.filter { !serverTrackIds.contains($0.trackId) }
            serverItems.append(contentsOf: pendingToKeep)

            try await persistQueueSnapshot(userId: userId, items: serverItems, convexQueueId: queue._id)
            return serverItems
        }
    }

    // MARK: - Remote Sync (Local → Convex)

    /// Syncs a single optimistic insert by calling the REST add endpoint.
    /// - Note: This does not reorder the server; callers should handle reordering separately if needed.
    func syncAddedTrack(userId: String, itemId: String) async -> String? {
        await operationQueue.run { [self] in
            do {
                // Re-read from local DB to ensure the item still exists and isn't already synced.
                let row = try await db.reader.read { db in
                    try PersistedQueueTrack.fetchOne(db, key: itemId)
                }

                guard let row, row.serverId == nil else {
                    return nil
                }

                let scTrack: SoundCloudTrack = try await MainActor.run {
                    try JSONDecoder().decode(SoundCloudTrack.self, from: row.trackData)
                }

                let serverId = try await convex.addTrackToQueue(track: scTrack)

                try await db.writer.write { db in
                    var updated = row
                    updated.serverId = serverId
                    updated.updatedAt = Date()
                    try updated.update(db)
                }

                return serverId
            } catch ConvexError.alreadyInQueue {
                // If server already has it, remove the optimistic local row and refresh from server.
                _ = try? await db.writer.write { db in
                    try PersistedQueueTrack.deleteOne(db, key: itemId)
                }
                _ = try? await syncQueueFromServer(userId: userId)
                return nil
            } catch {
                await MainActor.run {
                    logWarning(.queue, "Queue add sync failed: \(error)")
                }
                // Keep optimistic row; we'll reconcile on next sync.
                return nil
            }
        }
    }

    /// Sets the *entire* server queue to match the provided local order.
    /// Used as a correctness fallback when local order changes include unsynced items.
    func syncFullQueueToServer(userId: String, items: [QueueItem]) async {
        await operationQueue.run { [self] in
            do {
                let tracks = await MainActor.run { items.compactMap(\.soundCloudTrack) }
                let results = try await convex.setQueue(tracks: tracks)
                let mapping = Dictionary(uniqueKeysWithValues: results.map { ($0.trackId, $0._id) })

                // Update local DB serverIds to match the new Convex document IDs.
                try await db.writer.write { db in
                    let now = Date()
                    let rows = try PersistedQueueTrack
                        .filter(PersistedQueueTrack.Columns.queueUserId == userId)
                        .fetchAll(db)

                    var rowsByTrackId: [String: PersistedQueueTrack] = [:]
                    for row in rows {
                        rowsByTrackId[row.trackId] = row
                    }

                    for (index, item) in items.enumerated() {
                        guard var row = rowsByTrackId[item.trackId] else { continue }
                        row.serverId = mapping[item.trackId]
                        row.position = index
                        row.updatedAt = now
                        try row.update(db)
                    }
                }

                // Pull fresh state so local DB matches server ordering/ids exactly.
                _ = try await syncQueueFromServer(userId: userId)
            } catch {
                await MainActor.run {
                    logWarning(.queue, "Queue full sync failed: \(error)")
                }
            }
        }
    }
}
