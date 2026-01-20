//
//  QueueManager.swift
//  mixbridge
//
//  Centralized queue state management.
//  Single source of truth for queue operations across the entire app.
//
//  Core invariant: The currently playing track is NEVER in the queue.
//  Next track is always queue.peek() - no index arithmetic needed.
//

import Foundation
import SwiftUI

/// Centralized queue state management
/// Single source of truth for queue operations across the entire app
@Observable
@MainActor
class QueueManager {
    static let shared = QueueManager()

    // MARK: - State

    /// The upcoming tracks queue
    let queue = PlaybackQueue()

    /// SoundCloud metadata cache (trackId -> SoundCloudTrack)
    private var soundCloudTracks: [String: SoundCloudTrack] = [:]

    private let queueSync = QueueSync.shared
    private var activeUserId: String?

    private(set) var isLoading = false
    private var prefetchTask: Task<Void, Never>?
    private var queueRevision: Int = 0

    /// Check if queue has any tracks
    var hasQueue: Bool { !queue.isEmpty }

    /// Direct access to queue items for UI binding
    var queueTracks: [Track] {
        queue.items.map { $0.track }
    }

    /// Direct access to queue items (includes SoundCloudTrack for Spotify URL lookup)
    var queueItems: [QueueItem] {
        queue.items
    }

    private init() {
        logInfo(.queue, "QueueManager initialized")
    }

    // MARK: - Lifecycle / Local-First Bootstrap

    /// Call this once after authentication to load the persisted queue instantly and start a background refresh.
    func start(userId: String) async {
        activeUserId = userId

        do {
            let localItems = try await queueSync.loadLocalQueueItems(userId: userId)
            applyQueueSnapshot(localItems, context: "start(loadLocal)")
        } catch {
            logWarning(.queue, "Failed to load local queue: \(error)")
        }

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let merged = try await QueueBackgroundWorker.shared.syncQueueFromServer(userId: userId)
                self.applyQueueSnapshot(merged, context: "start(syncFromServer)")
            } catch {
                logWarning(.queue, "Failed to sync queue from server: \(error)")
            }
        }
    }

    // MARK: - Queue Change Notification

    /// Called internally after queue mutations to notify playback system
    private func notifyQueueChanged() {
        logDebug(.queue, "notifyQueueChanged: count=\(queue.count), peek=\(queue.peek()?.track.title ?? "nil")")
        prefetchTask?.cancel()
        let snapshotItems = queueItems
        prefetchTask = Task { [snapshotItems] in
            try? await Task.sleep(for: .milliseconds(100))  // Debounce rapid changes
            guard !Task.isCancelled else { return }
            logDebug(.queue, "notifyQueueChanged: triggering handleQueueChanged + prefetch")
            PlaybackCoordinator.shared.handleQueueChanged()

            Task(priority: .utility) {
                await QueueBackgroundWorker.shared.prefetchQueue(items: snapshotItems, currentIndex: 0)
            }
            PlaybackCoordinator.shared.prefetchQueue()
        }
    }

    /// Log current queue state for debugging
    private func logQueueState(_ context: String) {
        let titles = queue.items.prefix(5).map { $0.track.title }
        let more = queue.count > 5 ? "... +\(queue.count - 5) more" : ""
        logDebug(.queue, "\(context) | count=\(queue.count) | items=[\(titles.joined(separator: ", "))\(more)]")
    }

    private func requireUserId() throws -> String {
        if let activeUserId { return activeUserId }
        if let userId = KeychainManager.shared.getUserId() { return userId }
        throw ConvexError.unauthorized
    }

    private func applyQueueSnapshot(_ items: [QueueItem], context: String) {
        queueRevision &+= 1
        queue.replaceAll(items)
        soundCloudTracks = items.reduce(into: [:]) { dict, item in
            if let scTrack = item.soundCloudTrack {
                dict[item.trackId] = scTrack
            }
        }
        logQueueState(context)
        notifyQueueChanged()
    }

    private func schedulePersistSnapshot(delay: Duration = .milliseconds(200)) {
        guard let userId = try? requireUserId() else { return }
        let items = queue.items
        Task {
            await QueueBackgroundWorker.shared.schedulePersistQueueSnapshot(userId: userId, items: items, delay: delay)
        }
    }

    // MARK: - Query Operations

    /// Check if a track is in the queue
    func isInQueue(_ trackId: String) -> Bool {
        queue.contains(trackId: trackId)
    }

    /// Get SoundCloud track data for a track ID
    func soundCloudTrack(for trackId: String) -> SoundCloudTrack? {
        soundCloudTracks[trackId]
    }

    /// Get index of track in queue
    func indexOfTrack(withId trackId: String) -> Int? {
        queue.index(ofTrackId: trackId)
    }

    /// Get next track after given index
    func nextTrack(after index: Int) -> (track: Track, index: Int)? {
        let nextIndex = index + 1
        guard let track = queue.track(at: nextIndex) else { return nil }
        return (track, nextIndex)
    }

    /// Get previous track before given index
    func previousTrack(before index: Int) -> (track: Track, index: Int)? {
        let previousIndex = index - 1
        guard let track = queue.track(at: previousIndex) else { return nil }
        return (track, previousIndex)
    }

    /// Check if track at given index can navigate forward
    func canPlayNext(from index: Int) -> Bool {
        queue.track(at: index + 1) != nil
    }

    /// Check if track at given index can navigate backward
    func canPlayPrevious(from index: Int) -> Bool {
        queue.track(at: index - 1) != nil
    }

    /// Get queue position info for a track
    func queuePosition(for trackId: String) -> (index: Int, hasNext: Bool, hasPrevious: Bool)? {
        guard let index = queue.index(ofTrackId: trackId) else { return nil }
        return (
            index: index,
            hasNext: index < queue.count - 1,
            hasPrevious: index > 0
        )
    }

    // MARK: - Pop Operation (for playback)

    /// Pop the next track from queue (called when track starts playing)
    /// Returns the item that was removed, or nil if queue empty
    @discardableResult
    func popNext() -> QueueItem? {
        logQueueState("popNext BEFORE")

        guard let item = queue.pop() else {
            logWarning(.queue, "popNext: queue was EMPTY, returning nil")
            return nil
        }
        queueRevision &+= 1

        logInfo(.queue, "popNext: popped '\(item.track.title)' (id=\(item.id), serverId=\(item.serverId ?? "nil"), trackId=\(item.trackId))")
        logQueueState("popNext AFTER")
        notifyQueueChanged()
        schedulePersistSnapshot()

        // Sync removal to backend (fire-and-forget with logging)
        Task(priority: .utility) { [serverId = item.serverId] in
            do {
                guard let serverId else { return }
                logDebug(.queue, "popNext: syncing removal to Convex for serverId=\(serverId)")
                try await BackgroundExecutor.run {
                    try await ConvexService.shared.removeTrackFromQueue(queueTrackId: serverId)
                }
                logDebug(.queue, "popNext: Convex removal SUCCESS for serverId=\(serverId)")
            } catch {
                logWarning(.queue, "popNext: Convex removal FAILED: \(error)")
                // Don't rollback - track already played
            }
        }

        return item
    }

    // MARK: - Add Operations

    /// Add track to queue
    func addTrack(_ track: Track, soundCloudTrack: SoundCloudTrack) async throws {
        let userId = try requireUserId()
        logInfo(.queue, "addTrack(local-first): '\(track.title)' (trackId=\(track.id), userId=\(userId))")

        if isInQueue(track.id) {
            logWarning(.queue, "addTrack: track already in queue, throwing alreadyInQueue")
            throw ConvexError.alreadyInQueue
        }

        // 1) Optimistic local insert (instant UI)
        let localId = UUID().uuidString
        let item = QueueItem(
            id: localId,
            serverId: nil,
            trackId: track.id,
            track: track,
            soundCloudTrack: soundCloudTrack
        )

        queue.append(item)
        queueRevision &+= 1
        soundCloudTracks[track.id] = soundCloudTrack
        logQueueState("addTrack AFTER local")
        notifyQueueChanged()
        schedulePersistSnapshot()
        HapticManager.success()

        // 2) Background sync to server + reconcile serverId back into local state
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let serverId = await self.queueSync.syncAddedTrack(userId: userId, itemId: localId)
            guard let serverId else { return }

            self.queue.updateItem(withId: localId) { old in
                QueueItem(
                    id: old.id,
                    serverId: serverId,
                    trackId: old.trackId,
                    track: old.track,
                    soundCloudTrack: old.soundCloudTrack
                )
            }
            self.logQueueState("addTrack AFTER reconcile")
            self.notifyQueueChanged()
            self.schedulePersistSnapshot()
        }
    }

    /// Add track to queue with immediate local mutation (no async hop).
    /// Use this from UI actions where “tap -> UI update” must be instantaneous.
    func addTrackLocalFirst(_ track: Track, soundCloudTrack: SoundCloudTrack) throws {
        let userId = try requireUserId()
        logInfo(.queue, "addTrackLocalFirst: '\(track.title)' (trackId=\(track.id), userId=\(userId))")

        if isInQueue(track.id) {
            throw ConvexError.alreadyInQueue
        }

        let localId = UUID().uuidString
        let item = QueueItem(
            id: localId,
            serverId: nil,
            trackId: track.id,
            track: track,
            soundCloudTrack: soundCloudTrack
        )

        queue.append(item)
        queueRevision &+= 1
        soundCloudTracks[track.id] = soundCloudTrack
        notifyQueueChanged()
        schedulePersistSnapshot(delay: .milliseconds(0))
        HapticManager.success()

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let serverId = await self.queueSync.syncAddedTrack(userId: userId, itemId: localId)
            guard let serverId else { return }

            self.queue.updateItem(withId: localId) { old in
                QueueItem(
                    id: old.id,
                    serverId: serverId,
                    trackId: old.trackId,
                    track: old.track,
                    soundCloudTrack: old.soundCloudTrack
                )
            }
            self.notifyQueueChanged()
            self.schedulePersistSnapshot()
        }
    }

    /// Insert track as "next up" (right after currently playing)
    func insertTrackNext(_ track: Track, soundCloudTrack: SoundCloudTrack) async throws {
        let userId = try requireUserId()
        logInfo(.queue, "insertTrackNext(local-first): '\(track.title)' (trackId=\(track.id))")
        logQueueState("insertTrackNext BEFORE")

        let snapshotBefore = queue.items

        if let existingItem = queue.item(forTrackId: track.id) {
            // Track already in queue - move it to front
            guard queue.index(ofTrackId: track.id) != 0 else {
                logDebug(.queue, "insertTrackNext: track already at front, no-op")
                HapticManager.success()
                return
            }

            let fromIndex = queue.index(ofTrackId: track.id)!
            queue.remove(trackId: track.id)
            queue.insertNext(existingItem)
            queueRevision &+= 1
            logQueueState("insertTrackNext AFTER local move")
            notifyQueueChanged()
            schedulePersistSnapshot()
            HapticManager.success()

            Task(priority: .utility) { [weak self] in
                guard let self else { return }

                // If we have any pending (unsynced) items, fall back to a full sync for correctness.
                if self.queue.items.contains(where: { $0.serverId == nil }) {
                    await self.queueSync.syncFullQueueToServer(userId: userId, items: self.queue.items)
                    if let refreshed = try? await self.queueSync.loadLocalQueueItems(userId: userId) {
                        await MainActor.run { self.applyQueueSnapshot(refreshed, context: "insertTrackNext(fullSync)") }
                    }
                    return
                }

                do {
                    try await BackgroundExecutor.run {
                        try await ConvexService.shared.reorderQueue(fromIndex: fromIndex, toIndex: 0)
                    }
                } catch {
                    logError(.queue, "insertTrackNext: backend reorder FAILED, rolling back: \(error)")
                    await MainActor.run { self.applyQueueSnapshot(snapshotBefore, context: "insertTrackNext(rollback)") }
                    await MainActor.run { self.schedulePersistSnapshot() }
                }
            }
        } else {
            // Track not in queue - insert locally at front, then reconcile server to match.
            let localId = UUID().uuidString
            let item = QueueItem(
                id: localId,
                serverId: nil,
                trackId: track.id,
                track: track,
                soundCloudTrack: soundCloudTrack
            )

            queue.insertNext(item)
            queueRevision &+= 1
            soundCloudTracks[track.id] = soundCloudTrack
            logQueueState("insertTrackNext AFTER local insert")
            notifyQueueChanged()
            schedulePersistSnapshot()
            HapticManager.success()

            Task(priority: .utility) { [weak self] in
                guard let self else { return }
                let itemsSnapshot = self.queue.items
                await self.queueSync.syncFullQueueToServer(userId: userId, items: itemsSnapshot)
                if let refreshed = try? await self.queueSync.loadLocalQueueItems(userId: userId) {
                    self.applyQueueSnapshot(refreshed, context: "insertTrackNext(fullSync)")
                }
            }
        }
    }

    /// Insert as “next up” with immediate local mutation (no async hop).
    func insertTrackNextLocalFirst(_ track: Track, soundCloudTrack: SoundCloudTrack) throws {
        let userId = try requireUserId()
        logInfo(.queue, "insertTrackNextLocalFirst: '\(track.title)' (trackId=\(track.id))")

        let snapshotBefore = queue.items

        if let existingItem = queue.item(forTrackId: track.id) {
            guard queue.index(ofTrackId: track.id) != 0 else {
                HapticManager.success()
                return
            }

            let fromIndex = queue.index(ofTrackId: track.id)!
            queue.remove(trackId: track.id)
            queue.insertNext(existingItem)
            queueRevision &+= 1
            notifyQueueChanged()
            schedulePersistSnapshot(delay: .milliseconds(0))
            HapticManager.success()

            Task(priority: .utility) { [weak self] in
                guard let self else { return }

                let itemsSnapshot = self.queue.items
                if itemsSnapshot.contains(where: { $0.serverId == nil }) {
                    await self.queueSync.syncFullQueueToServer(userId: userId, items: itemsSnapshot)
                    if let refreshed = try? await self.queueSync.loadLocalQueueItems(userId: userId) {
                        self.applyQueueSnapshot(refreshed, context: "insertTrackNextLocalFirst(fullSync)")
                    }
                    return
                }

                do {
                    try await BackgroundExecutor.run {
                        try await ConvexService.shared.reorderQueue(fromIndex: fromIndex, toIndex: 0)
                    }
                } catch {
                    self.applyQueueSnapshot(snapshotBefore, context: "insertTrackNextLocalFirst(rollback)")
                    self.schedulePersistSnapshot()
                }
            }
        } else {
            let localId = UUID().uuidString
            let item = QueueItem(
                id: localId,
                serverId: nil,
                trackId: track.id,
                track: track,
                soundCloudTrack: soundCloudTrack
            )

            queue.insertNext(item)
            queueRevision &+= 1
            soundCloudTracks[track.id] = soundCloudTrack
            notifyQueueChanged()
            schedulePersistSnapshot(delay: .milliseconds(0))
            HapticManager.success()

            Task(priority: .utility) { [weak self] in
                guard let self else { return }
                let itemsSnapshot = self.queue.items
                await self.queueSync.syncFullQueueToServer(userId: userId, items: itemsSnapshot)
                if let refreshed = try? await self.queueSync.loadLocalQueueItems(userId: userId) {
                    self.applyQueueSnapshot(refreshed, context: "insertTrackNextLocalFirst(fullSync)")
                }
            }
        }
    }

    // MARK: - Remove Operations

    /// Remove track from queue with optimistic update
    func removeTrack(_ track: Track, silent: Bool = false) async throws {
        logInfo(.queue, "removeTrack: '\(track.title)' (trackId=\(track.id), silent=\(silent))")
        logQueueState("removeTrack BEFORE")

        guard let item = queue.item(forTrackId: track.id) else {
            logWarning(.queue, "removeTrack: track NOT FOUND in queue")
            throw ConvexError.notFound
        }

        let originalIndex = queue.index(ofTrackId: track.id)!
        let removedItem = queue.remove(trackId: track.id)!
        queueRevision &+= 1
        logInfo(.queue, "removeTrack: removed from index \(originalIndex), id=\(item.id)")
        logQueueState("removeTrack AFTER")
        notifyQueueChanged()
        schedulePersistSnapshot()

        if !silent {
            HapticManager.warning()
        }

        do {
            guard let serverId = item.serverId else {
                // Local-only item (not yet synced); nothing to do remotely.
                return
            }
            logDebug(.queue, "removeTrack: syncing to Convex serverId=\(serverId)")
            try await BackgroundExecutor.run {
                try await ConvexService.shared.removeTrackFromQueue(queueTrackId: serverId)
            }
            logDebug(.queue, "removeTrack: Convex SUCCESS")
        } catch {
            // Rollback on failure
            logError(.queue, "removeTrack: Convex FAILED, rolling back: \(error)")
            queue.reinsert(removedItem, at: originalIndex)
            queueRevision &+= 1
            notifyQueueChanged()
            schedulePersistSnapshot()
            throw error
        }
    }

    /// Remove item at index - synchronous local mutation for instant UI feedback
    /// Returns the removed item for rollback, or nil if index invalid
    @discardableResult
    func removeAtLocal(index: Int, silent: Bool = false) -> QueueItem? {
        logInfo(.queue, "removeAtLocal: index=\(index), silent=\(silent)")
        logQueueState("removeAtLocal BEFORE")

        guard queue.items[safe: index] != nil else {
            logWarning(.queue, "removeAtLocal: index \(index) OUT OF BOUNDS")
            return nil
        }

        let removedItem = queue.remove(at: index)
        queueRevision &+= 1
        logInfo(.queue, "removeAtLocal: removed '\(removedItem?.track.title ?? "nil")' from index \(index)")
        logQueueState("removeAtLocal AFTER")
        notifyQueueChanged()
        schedulePersistSnapshot()

        if !silent {
            HapticManager.warning()
        }

        return removedItem
    }

    /// Sync a remove operation to backend (call after removeAtLocal)
    func syncRemoveToBackend(item: QueueItem, originalIndex: Int) async {
        guard let serverId = item.serverId else { return }
        logDebug(.queue, "syncRemoveToBackend: syncing to Convex serverId=\(serverId)")
        do {
            try await BackgroundExecutor.run {
                try await ConvexService.shared.removeTrackFromQueue(queueTrackId: serverId)
            }
            logDebug(.queue, "syncRemoveToBackend: Convex SUCCESS")
        } catch {
            // Rollback on failure
            logError(.queue, "syncRemoveToBackend: Convex FAILED, rolling back: \(error)")
            queue.reinsert(item, at: originalIndex)
            queueRevision &+= 1
            notifyQueueChanged()
            await MainActor.run { self.schedulePersistSnapshot() }
            HapticManager.error()
        }
    }

    /// Remove item by QueueItem - synchronous local mutation
    @discardableResult
    func removeItemLocal(_ item: QueueItem, silent: Bool = false) -> Int? {
        logInfo(.queue, "removeItemLocal: item=\(item.track.title), silent=\(silent)")
        guard let index = queue.items.firstIndex(where: { $0.id == item.id }) else {
            logWarning(.queue, "removeItemLocal: item not found in queue")
            return nil
        }

        queue.remove(id: item.id)
        queueRevision &+= 1
        logInfo(.queue, "removeItemLocal: removed from index \(index)")
        notifyQueueChanged()
        schedulePersistSnapshot()

        if !silent {
            HapticManager.warning()
        }

        return index
    }

    // MARK: - Reorder Operations

    /// Move item in queue - synchronous local mutation for instant UI feedback
    /// Call syncMoveToBackend() after to persist
    func moveItemLocal(from sourceIndex: Int, to destinationIndex: Int) {
        guard queue.items.indices.contains(sourceIndex) else { return }
        guard sourceIndex != destinationIndex else { return }

        queue.move(from: sourceIndex, to: destinationIndex)
        queueRevision &+= 1
        notifyQueueChanged()
        schedulePersistSnapshot()
    }

    /// Sync a move operation to backend (call after moveItemLocal)
    func syncMoveToBackend(from sourceIndex: Int, to destinationIndex: Int) async {
        let userId: String
        do {
            userId = try requireUserId()
        } catch {
            return
        }

        // If there are pending optimistic inserts, use a full sync to guarantee server order matches local.
        if queue.items.contains(where: { $0.serverId == nil }) {
            await queueSync.syncFullQueueToServer(userId: userId, items: queue.items)
            if let refreshed = try? await queueSync.loadLocalQueueItems(userId: userId) {
                applyQueueSnapshot(refreshed, context: "syncMoveToBackend(fullSync)")
            }
            return
        }

        // Calculate actual destination for Convex (List.onMove destination adjusts)
        let toIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex

        do {
            try await BackgroundExecutor.run {
                try await ConvexService.shared.reorderQueue(fromIndex: sourceIndex, toIndex: toIndex)
            }
        } catch {
            logError(.queue, "Failed to sync move to backend: \(error)")
            // Rollback - move back
            let actualDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
            queue.move(from: actualDestination, to: sourceIndex)
            queueRevision &+= 1
            notifyQueueChanged()
            schedulePersistSnapshot()
            HapticManager.error()
        }
    }

    // MARK: - Batch Operations

    /// Replace entire queue with new tracks
    func setQueue(items: [TrackItem], startIndex: Int = 0) {
        logInfo(.queue, "setQueue(local-first): \(items.count) items, startIndex=\(startIndex)")
        guard !items.isEmpty else { return }

        // Invariant: the *currently playing* track is not in the queue.
        // So for a list playback, we store tracks AFTER startIndex.
        let upcomingStart = min(startIndex + 1, items.count)
        let tracksToSet = upcomingStart < items.count ? Array(items.suffix(from: upcomingStart)) : []

        let localQueueItems: [QueueItem] = tracksToSet.map { trackItem in
            QueueItem(
                id: UUID().uuidString,
                serverId: nil,
                trackId: trackItem.track.id,
                track: trackItem.track,
                soundCloudTrack: trackItem.soundCloudTrack
            )
        }

        applyQueueSnapshot(localQueueItems, context: "setQueue AFTER local")
        schedulePersistSnapshot(delay: .milliseconds(50))
        HapticManager.success()

        let expectedRevision = queueRevision
        let serverTracks = tracksToSet.map(\.soundCloudTrack)

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let userId = try? self.requireUserId() else { return }
            do {
                if serverTracks.isEmpty {
                    try await BackgroundExecutor.run {
                        try await ConvexService.shared.clearQueue()
                    }
                    return
                }

                let results = try await BackgroundExecutor.run {
                    try await ConvexService.shared.setQueue(tracks: serverTracks)
                }
                let mapping = Dictionary(uniqueKeysWithValues: results.map { ($0.trackId, $0._id) })

                guard self.queueRevision == expectedRevision else { return }

                for item in self.queue.items where item.serverId == nil {
                    if let serverId = mapping[item.trackId] {
                        self.queue.updateItem(withId: item.id) { old in
                            QueueItem(
                                id: old.id,
                                serverId: serverId,
                                trackId: old.trackId,
                                track: old.track,
                                soundCloudTrack: old.soundCloudTrack
                            )
                        }
                    }
                }
                self.logQueueState("setQueue AFTER reconcile")
                self.notifyQueueChanged()
                self.schedulePersistSnapshot()
            } catch {
                logError(.queue, "setQueue: server sync FAILED (userId=\(userId)): \(error)")
            }
        }
    }

    /// Append multiple tracks to end of queue
    func appendTracks(_ items: [TrackItem]) async throws {
        _ = try requireUserId()
        logInfo(.queue, "appendTracks(local-first): \(items.count) items")
        logQueueState("appendTracks BEFORE")

        guard !items.isEmpty else { return }

        // Filter out tracks already in queue
        let newItems = items.filter { !isInQueue($0.track.id) }
        guard !newItems.isEmpty else { return }

        // 1) Optimistic local append
        for trackItem in newItems {
            let item = QueueItem(
                id: UUID().uuidString,
                serverId: nil,
                trackId: trackItem.track.id,
                track: trackItem.track,
                soundCloudTrack: trackItem.soundCloudTrack
            )
            queue.append(item)
            soundCloudTracks[trackItem.track.id] = trackItem.soundCloudTrack
        }
        queueRevision &+= 1

        logQueueState("appendTracks AFTER local")
        notifyQueueChanged()
        schedulePersistSnapshot()
        HapticManager.success()

        // 2) Background: append on server + reconcile server IDs for the newly appended tracks
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let tracks = newItems.map(\.soundCloudTrack)
                let results = try await BackgroundExecutor.run {
                    try await ConvexService.shared.addTracksToQueueBatch(tracks: tracks)
                }
                let mapping = Dictionary(uniqueKeysWithValues: results.map { ($0.trackId, $0._id) })

                for item in self.queue.items where item.serverId == nil {
                    if let serverId = mapping[item.trackId] {
                        self.queue.updateItem(withId: item.id) { old in
                            QueueItem(
                                id: old.id,
                                serverId: serverId,
                                trackId: old.trackId,
                                track: old.track,
                                soundCloudTrack: old.soundCloudTrack
                            )
                        }
                    }
                }
                self.logQueueState("appendTracks AFTER reconcile")
                self.notifyQueueChanged()

                self.schedulePersistSnapshot()
            } catch {
                logError(.queue, "appendTracks: server sync FAILED: \(error)")
                // Leave optimistic items; they'll reconcile on next refresh.
            }
        }
    }

    // MARK: - Load & Clear

    /// Load queue from server
    func loadQueue(userId: String) async throws {
        logInfo(.queue, "loadQueue(sync-engine): userId=\(userId)")
        activeUserId = userId
        isLoading = true
        defer { isLoading = false }

        let merged = try await queueSync.syncQueueFromServer(userId: userId)
        applyQueueSnapshot(merged, context: "loadQueue COMPLETE")
    }

    /// Clear entire queue (local only)
    func clearQueue() {
        logInfo(.queue, "clearQueue (local only)")
        logQueueState("clearQueue BEFORE")
        queue.clear()
        queueRevision &+= 1
        soundCloudTracks.removeAll()
        logInfo(.queue, "clearQueue: queue cleared locally")
        notifyQueueChanged()
        schedulePersistSnapshot()
    }

    /// Clear entire queue with backend sync
    func clearQueueWithSync() async throws {
        logInfo(.queue, "clearQueueWithSync")
        logQueueState("clearQueueWithSync BEFORE")

        let snapshotBefore = queue.items

        // Optimistic local clear
        queue.clear()
        queueRevision &+= 1
        soundCloudTracks.removeAll()
        notifyQueueChanged()
        schedulePersistSnapshot()

        do {
            logDebug(.queue, "clearQueueWithSync: calling Convex clearQueue")
            try await BackgroundExecutor.run {
                try await ConvexService.shared.clearQueue()
            }
            logDebug(.queue, "clearQueueWithSync: Convex SUCCESS")
            HapticManager.warning()
        } catch {
            logError(.queue, "clearQueueWithSync: Convex FAILED, rolling back: \(error)")
            applyQueueSnapshot(snapshotBefore, context: "clearQueueWithSync(rollback)")
            schedulePersistSnapshot()
            throw error
        }
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
