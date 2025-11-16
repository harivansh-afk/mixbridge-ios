//
//  LikedView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LikedView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var likedTracks: [Track] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Liked")
                .onAppear {
                    if !hasLoaded {
                        Task {
                            await loadLikedTracks()
                        }
                    }
                }
        }
    }

    private func loadLikedTracks() async {
        guard let userId = authManager.currentUserId else {
            print("❌ [LikedView] No userId")
            return
        }

        guard !isLoading else {
            print("⏭️ [LikedView] Already loading, skipping")
            return
        }

        isLoading = true
        print("🔄 [LikedView] Starting load...")

        // Try Convex cache first
        print("📡 [LikedView] Fetching liked tracks from Convex for userId: \(userId)")
        do {
            let cached = try await ConvexService.shared.getLikedTracks(userId: userId)

            if let cached = cached {
                self.likedTracks = convertToTracks(cached.tracks)
                print("✅ [LikedView] Loaded \(likedTracks.count) liked tracks from Convex cache!")
                hasLoaded = true
                isLoading = false
                return
            }
        } catch ConvexError.noData {
            print("⚠️ [LikedView] No cache, will try backend")
        } catch {
            print("❌ [LikedView] Convex error: \(error)")
        }

        // Fallback: Fetch from backend (fresh from SoundCloud)
        print("📡 [LikedView] Fetching from backend API...")
        do {
            let response = try await BackendAPI.shared.getLikedTracks(limit: 50)
            self.likedTracks = convertToTracks(response.tracks)
            print("✅ [LikedView] Loaded \(likedTracks.count) liked tracks from backend!")
        } catch {
            print("❌ [LikedView] Backend error: \(error)")
        }

        hasLoaded = true
        isLoading = false
    }

    private func convertToTracks(_ soundcloudTracks: [SoundCloudTrack]) -> [Track] {
        return soundcloudTracks.map { soundcloudTrack in
            let artworkUrl = soundcloudTrack.artwork_url ?? soundcloudTrack.user.avatar_url ?? ""
            let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

            return Track(
                title: soundcloudTrack.title,
                artist: soundcloudTrack.user.username,
                album: soundcloudTrack.genre ?? "",
                artwork: highQualityArtwork,
                duration: Double(soundcloudTrack.duration)
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if likedTracks.isEmpty {
            emptyState
        } else {
            tracksList
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Liked Songs",
            systemImage: "heart",
            description: Text("Your liked songs will appear here")
        )
    }

    private var tracksList: some View {
        List {
            Section {
                ForEach(Array(likedTracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track, number: index + 1, showCover: true)
                        .redacted(reason: track.title.isEmpty ? .placeholder : [])
                }
            }
        }
        .listStyle(.plain)
    }
}

#Preview("Light Mode") {
    LikedView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    LikedView()
        .preferredColorScheme(.dark)
}
