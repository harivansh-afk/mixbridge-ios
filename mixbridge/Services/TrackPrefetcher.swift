//
//  TrackPrefetcher.swift
//  mixbridge
//
//  Comprehensive background service to preload everything for smooth playback
//

import Foundation
import UIKit

actor TrackPrefetcher {
    static let shared = TrackPrefetcher()

    private let imageCache = ImageCacheManager.shared
    private let lookahead = 5
    private var currentPrefetchTask: Task<Void, Never>?
    private var prefetchedTrackIds = Set<String>()

    private init() {}

    func prefetchForQueue(_ tracks: [Track], currentIndex: Int) {
        currentPrefetchTask?.cancel()

        currentPrefetchTask = Task(priority: .utility) {
            await prefetchTracks(tracks: tracks, currentIndex: currentIndex)
        }
    }

    private func prefetchTracks(tracks: [Track], currentIndex: Int) async {
        let startIndex = max(0, currentIndex)
        let endIndex = min(currentIndex + lookahead + 1, tracks.count)

        guard startIndex < tracks.count else { return }

        for i in startIndex..<endIndex {
            guard !Task.isCancelled else { break }

            let track = tracks[i]
            guard !prefetchedTrackIds.contains(track.id) else { continue }

            await prefetchTrack(track, priority: i == currentIndex ? .high : .utility)
            prefetchedTrackIds.insert(track.id)

            if i != currentIndex {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func prefetchTrack(_ track: Track, priority: TaskPriority) async {
        if track.artwork.starts(with: "http"), let url = URL(string: track.artwork) {
            await Task(priority: priority) {
                _ = await imageCache.getImage(for: url)
            }.value
        }
    }

    func preloadTrackImmediately(_ track: Track) async {
        guard track.artwork.starts(with: "http"),
              let url = URL(string: track.artwork) else {
            return
        }

        _ = await imageCache.getImage(for: url)
        prefetchedTrackIds.insert(track.id)
    }

    func reset() {
        currentPrefetchTask?.cancel()
        prefetchedTrackIds.removeAll()
    }

    func cancelAll() {
        currentPrefetchTask?.cancel()
    }
}
