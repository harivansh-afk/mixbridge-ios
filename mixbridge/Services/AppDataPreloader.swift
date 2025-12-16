//
//  AppDataPreloader.swift
//  mixbridge
//
//  Centralized preloading coordinator.
//  Fetches all app data in priority tiers during splash.
//

import Foundation

/// Coordinates all data preloading across the app
/// Fetches in priority tiers: Critical -> Secondary -> Speculative
actor AppDataPreloader {
    static let shared = AppDataPreloader()

    private let store = PreloadedDataStore.shared
    private let convex = ConvexService.shared
    private let imageCache = ImageCacheManager.shared

    private var isPreloading = false
    private var criticalDataReady = false

    private init() {}

    // MARK: - Public API

    /// Start preloading during splash screen
    /// Returns when critical data (Tier 1) is ready
    func startPreloading(userId: String) async {
        // Check if token is still valid before loading data
        await MainActor.run { AuthManager.shared.checkAuthStatus() }
        guard await MainActor.run(body: { AuthManager.shared.isAuthenticated }) else { return }

        guard !isPreloading else { return }
        isPreloading = true

        #if DEBUG
        print("🚀 AppDataPreloader: Starting preload for user \(userId)")
        let startTime = CFAbsoluteTimeGetCurrent()
        #endif

        // Tier 1: Critical data - load in parallel with high priority
        await loadTier1CriticalData(userId: userId)

        criticalDataReady = true

        #if DEBUG
        let tier1Time = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ AppDataPreloader: Tier 1 complete in \(String(format: "%.2f", tier1Time))s")
        #endif

        // Tier 2 & 3: Continue in background after splash
        Task(priority: .utility) {
            await self.loadTier2SecondaryData(userId: userId)
            await self.loadTier3SpeculativeData(userId: userId)

            #if DEBUG
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ AppDataPreloader: All tiers complete in \(String(format: "%.2f", totalTime))s")
            #endif
        }
    }

    /// Check if critical data is ready (for splash dismissal)
    func isCriticalDataReady() -> Bool {
        criticalDataReady
    }

    /// Refresh specific data in background (call when view appears)
    func refreshIfStale(userId: String, dataType: PreloadDataType) async {
        await MainActor.run { AuthManager.shared.checkAuthStatus() }
        guard await MainActor.run(body: { AuthManager.shared.isAuthenticated }) else { return }

        switch dataType {
        case .profile:
            if await MainActor.run(body: { store.isProfileStale() }) {
                await loadProfile(userId: userId)
            }
        case .playHistory:
            if await MainActor.run(body: { store.isPlayHistoryStale() }) {
                await loadPlayHistory(userId: userId)
            }
        case .playlists:
            if await MainActor.run(body: { store.isPlaylistsStale() }) {
                await loadPlaylists(userId: userId)
            }
        case .likedTracks:
            if await MainActor.run(body: { store.isLikedTracksStale() }) {
                await loadLikedTracks(userId: userId)
            }
        case .playlistTracks(let playlistId):
            if await MainActor.run(body: { store.isPlaylistTracksStale(playlistId) }) {
                await loadPlaylistTracks(userId: userId, playlistId: playlistId)
            }
        }
    }

    /// Force refresh play history (bypasses staleness check)
    /// Called after optimistic update to sync with Convex source of truth
    func forceRefreshPlayHistory(userId: String) async {
        await loadPlayHistory(userId: userId)
    }

    /// Preload a specific playlist's tracks (call when user shows intent)
    /// - Parameter forceRefresh: If true, bypasses cache and fetches fresh data
    func preloadPlaylistTracks(userId: String, playlistId: String, forceRefresh: Bool = false) async {
        // Skip if already loaded and fresh (unless force refresh requested)
        if !forceRefresh {
            let shouldSkip = await MainActor.run {
                store.playlistTracksState[playlistId]?.isLoaded == true &&
                !store.isPlaylistTracksStale(playlistId)
            }
            guard !shouldSkip else { return }
        }

        await loadPlaylistTracks(userId: userId, playlistId: playlistId)
    }

    /// Reset preloader state (call on logout)
    func reset() async {
        isPreloading = false
        criticalDataReady = false
        await MainActor.run {
            store.clearAll()
        }
    }

    // MARK: - Tier 1: Critical Data

    private func loadTier1CriticalData(userId: String) async {
        await withTaskGroup(of: Void.self) { group in
            // Profile + avatar
            group.addTask(priority: .userInitiated) {
                await self.loadProfile(userId: userId)
            }

            // Play history for HomeView
            group.addTask(priority: .userInitiated) {
                await self.loadPlayHistory(userId: userId)
            }

            // Playlists for LibraryView
            group.addTask(priority: .userInitiated) {
                await self.loadPlaylists(userId: userId)
            }
        }
    }

    // MARK: - Tier 2: Secondary Data

    private func loadTier2SecondaryData(userId: String) async {
        #if DEBUG
        print("📦 AppDataPreloader: Starting Tier 2 (Secondary)")
        #endif

        // Liked tracks
        await loadLikedTracks(userId: userId)

        // Top 5 playlist tracks (most likely to be tapped)
        let topPlaylists = await MainActor.run { Array(store.playlists.prefix(5)) }

        for playlist in topPlaylists {
            await loadPlaylistTracks(userId: userId, playlistId: playlist.id)
            // Small delay to avoid overwhelming the server
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }

    // MARK: - Tier 3: Speculative Data

    private func loadTier3SpeculativeData(userId: String) async {
        #if DEBUG
        print("📦 AppDataPreloader: Starting Tier 3 (Speculative)")
        #endif

        // Preload remaining playlist tracks (6-10)
        let remainingPlaylists = await MainActor.run {
            Array(store.playlists.dropFirst(5).prefix(5))
        }

        for playlist in remainingPlaylists {
            await loadPlaylistTracks(userId: userId, playlistId: playlist.id)
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Prefetch all visible artwork images
        await prefetchAllArtwork()
    }

    // MARK: - Individual Loaders

    private func loadProfile(userId: String) async {
        await MainActor.run { store.setProfileLoading() }

        do {
            let profile = try await convex.getUserProfile(userId: userId)

            await MainActor.run { store.updateProfile(profile) }

            // Prefetch avatar image
            if let avatarUrl = profile.avatar_url, let url = URL(string: avatarUrl) {
                _ = await imageCache.getImage(for: url)
            }

            #if DEBUG
            print("✅ Loaded profile: \(profile.username)")
            #endif
        } catch {
            await MainActor.run { store.setProfileFailed(error) }
            #if DEBUG
            print("❌ Failed to load profile: \(error)")
            #endif
        }
    }

    private func loadPlayHistory(userId: String) async {
        await MainActor.run { store.setPlayHistoryLoading() }

        do {
            let history = try await convex.getPlayHistory(userId: userId, limit: 50)

            // Deduplicate and convert to TrackItems
            var items: [TrackItem] = []
            var seen: [String: Int] = [:]

            for playItem in history {
                let key = "\(playItem.trackData.title.lowercased())|\(playItem.trackData.user.username.lowercased())"

                if let existingIndex = seen[key] {
                    items[existingIndex].playCount += 1
                } else {
                    let item = TrackItem(
                        soundCloudTrack: playItem.trackData,
                        playCount: 1,
                        lastPlayedPosition: playItem.playbackPosition ?? 0,
                        listenedPercentage: playItem.listenedPercentage ?? 0
                    )
                    seen[key] = items.count
                    items.append(item)
                }
            }

            await MainActor.run { store.updatePlayHistory(items) }

            // Prefetch artwork for first 20 tracks
            await prefetchTrackArtwork(Array(items.prefix(20)))

            #if DEBUG
            print("✅ Loaded play history: \(items.count) items")
            #endif
        } catch {
            await MainActor.run { store.setPlayHistoryFailed(error) }
            #if DEBUG
            print("❌ Failed to load play history: \(error)")
            #endif
        }
    }

    private func loadPlaylists(userId: String) async {
        await MainActor.run { store.setPlaylistsLoading() }

        do {
            let scPlaylists = try await convex.getPlaylists(userId: userId)

            let playlists = scPlaylists.map { scPlaylist in
                Playlist(
                    id: String(scPlaylist.id),
                    name: scPlaylist.title,
                    creator: scPlaylist.user.username,
                    artwork: scPlaylist.primaryArtworkUrl,
                    tracks: [],
                    lastUpdated: Date()
                )
            }

            await MainActor.run { store.updatePlaylists(playlists) }

            // Prefetch artwork for all playlists
            await prefetchPlaylistArtwork(playlists)

            #if DEBUG
            print("✅ Loaded playlists: \(playlists.count) items")
            #endif
        } catch {
            await MainActor.run { store.setPlaylistsFailed(error) }
            #if DEBUG
            print("❌ Failed to load playlists: \(error)")
            #endif
        }
    }

    private func loadLikedTracks(userId: String) async {
        await MainActor.run { store.setLikedTracksLoading() }

        do {
            let tracks = try await convex.getLikedTracks(userId: userId)

            let items = tracks.toTrackItems()
            await MainActor.run { store.updateLikedTracks(items) }

            // Prefetch artwork for first 30 tracks
            await prefetchTrackArtwork(Array(items.prefix(30)))

            #if DEBUG
            print("✅ Loaded liked tracks: \(items.count) items")
            #endif
        } catch {
            await MainActor.run { store.setLikedTracksFailed(error) }
            #if DEBUG
            print("❌ Failed to load liked tracks: \(error)")
            #endif
        }
    }

    private func loadPlaylistTracks(userId: String, playlistId: String) async {
        await MainActor.run { store.setPlaylistTracksLoading(playlistId) }

        do {
            let tracks = try await convex.getPlaylistTracks(userId: userId, playlistId: playlistId)

            let items = tracks.toTrackItems()
            await MainActor.run { store.updatePlaylistTracks(playlistId: playlistId, items: items) }

            // Prefetch artwork for first 20 tracks
            await prefetchTrackArtwork(Array(items.prefix(20)))

            #if DEBUG
            print("✅ Loaded playlist \(playlistId) tracks: \(items.count) items")
            #endif
        } catch {
            await MainActor.run { store.setPlaylistTracksFailed(playlistId, error) }
            #if DEBUG
            print("❌ Failed to load playlist \(playlistId) tracks: \(error)")
            #endif
        }
    }

    // MARK: - Artwork Prefetching

    private func prefetchTrackArtwork(_ items: [TrackItem]) async {
        for item in items {
            if item.track.artwork.starts(with: "http"),
               let url = URL(string: item.track.artwork) {
                _ = await imageCache.getImage(for: url)
            }
        }
    }

    private func prefetchPlaylistArtwork(_ playlists: [Playlist]) async {
        for playlist in playlists {
            if playlist.artwork.starts(with: "http"),
               let url = URL(string: playlist.artwork) {
                _ = await imageCache.getImage(for: url)
            }
        }
    }

    private func prefetchAllArtwork() async {
        // Prefetch any remaining artwork from all loaded data
        let allPlaylists = await MainActor.run { store.playlists }
        let allHistory = await MainActor.run { store.playHistory }
        let allLiked = await MainActor.run { store.likedTracks }

        // Batch prefetch with lower priority
        await withTaskGroup(of: Void.self) { group in
            for playlist in allPlaylists {
                group.addTask(priority: .background) {
                    if playlist.artwork.starts(with: "http"),
                       let url = URL(string: playlist.artwork) {
                        _ = await self.imageCache.getImage(for: url)
                    }
                }
            }

            for item in allHistory.prefix(50) {
                group.addTask(priority: .background) {
                    if item.track.artwork.starts(with: "http"),
                       let url = URL(string: item.track.artwork) {
                        _ = await self.imageCache.getImage(for: url)
                    }
                }
            }

            for item in allLiked.prefix(50) {
                group.addTask(priority: .background) {
                    if item.track.artwork.starts(with: "http"),
                       let url = URL(string: item.track.artwork) {
                        _ = await self.imageCache.getImage(for: url)
                    }
                }
            }
        }
    }
}

// MARK: - Data Types Enum

enum PreloadDataType {
    case profile
    case playHistory
    case playlists
    case likedTracks
    case playlistTracks(playlistId: String)
}
