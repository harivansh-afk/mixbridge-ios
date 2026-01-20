//
//  QueueBackgroundWorker.swift
//  mixbridge
//
//  Background helper for queue-related side effects (persistence + prefetch),
//  keeping @MainActor types from spawning detached tasks directly.
//

import Foundation

actor QueueBackgroundWorker {
    static let shared = QueueBackgroundWorker()

    private let queueSync = QueueSync.shared
    private var persistTask: Task<Void, Never>?

    private init() {}

    func schedulePersistQueueSnapshot(userId: String, items: [QueueItem], delay: Duration) {
        persistTask?.cancel()
        persistTask = Task(priority: .utility) { [queueSync] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            do {
                try await queueSync.persistQueueSnapshot(userId: userId, items: items)
            } catch {
                await MainActor.run { logWarning(.queue, "Failed to persist queue snapshot: \(error)") }
            }
        }
    }

    func prefetchQueue(items: [QueueItem], currentIndex: Int = 0) async {
        let tracks = items.map { $0.track }
        let spotifyUrls = items.reduce(into: [String: String]()) { dict, item in
            if let url = item.soundCloudTrack?.permalink_url, url.contains("spotify") {
                dict[item.track.id] = url
            }
        }
        await TrackPrefetcher.shared.prefetchForQueue(tracks, currentIndex: currentIndex)
        await StreamURLCache.shared.prefetchUpcoming(tracks: tracks, spotifyUrls: spotifyUrls, lookAhead: 5)
    }

    func syncQueueFromServer(userId: String) async throws -> [QueueItem] {
        try await queueSync.syncQueueFromServer(userId: userId)
    }
}

