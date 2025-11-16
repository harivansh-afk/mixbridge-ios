//
//  HomeView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct HomeView: View {
    // MARK: - State
    @State private var showingAccount = false
    @Environment(AuthManager.self) private var authManager
    @Environment(UserProfileManager.self) private var profileManager
    @State private var queueTracks: [Track] = []
    @State private var queueTrackIds: [String: String] = [:] // Track.id -> Convex queue track ID
    @State private var recentlyPlayed: [Track] = []
    @State private var recentlyPlayedData: [String: [String: Any]] = [:] // Track ID -> raw data
    @State private var isLoading = false
    @State private var hasLoaded = false

    // MARK: - Body
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.large)
                .refreshable {
                    await loadHomeData()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        profileAvatar
                    }
                }
            .sheet(isPresented: $showingAccount) {
                AccountBottomSheet(
                    isPresented: $showingAccount,
                    userName: profileManager.displayName,
                    userEmail: nil,
                    profileImage: nil
                )
            }
            .task {
                if let userId = authManager.currentUserId {
                    await profileManager.loadProfile(userId: userId)
                }
            }
            .onAppear {
                if !hasLoaded {
                    Task {
                        await loadHomeData()
                    }
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && !hasLoaded {
            // Skeleton loading state
            skeletonLoadingView
        } else if queueTracks.isEmpty && recentlyPlayed.isEmpty {
            emptyState
        } else {
            homeList
        }
    }

    private var skeletonLoadingView: some View {
        List {
            Section {
                Text("Queue")
                    .font(.title2)
                    .fontWeight(.bold)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)

                ForEach(0..<3) { _ in
                    skeletonTrackRow
                }
            }

            Section {
                Text("Recently Played")
                    .font(.title2)
                    .fontWeight(.bold)
                    .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)

                ForEach(0..<5) { _ in
                    skeletonTrackRow
                }
            }
        }
        .listStyle(.plain)
        .redacted(reason: .placeholder)
    }

    private var skeletonTrackRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("Loading Track Title")
                    .font(.body)
                Text("Loading Artist")
                    .font(.caption)
            }

            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var profileAvatar: some View {
        HStack {
            if let avatarUrl = profileManager.avatarUrl,
               let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(.gray.opacity(0.3))
                }
                .frame(width: 35, height: 35)
                .clipShape(Circle())
                .onTapGesture {
                    showingAccount.toggle()
                }
            } else {
                ProfileCircleView(
                    profileImage: nil,
                    userName: profileManager.displayName,
                )
                .onTapGesture {
                    showingAccount.toggle()
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Activity Yet",
            systemImage: "music.note",
            description: Text("Your queue and listening history will appear here")
        )
    }

    private var homeList: some View {
        List {
            // Queue Section
            if !queueTracks.isEmpty {
                Section {
                    // Subheading row
                    Text("Queue")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)

                    // Track rows
                    ForEach(Array(queueTracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            track,
                            number: index + 1,
                            showCover: true,
                            onDelete: {
                                removeTrackFromQueue(track)
                            },
                            onTrackAddedToQueue: { addedTrack, queueTrackId in
                                // Add track and store queue track ID mapping
                                print("⚡ [HomeView] Adding track to queue with ID: \(queueTrackId)")
                                if !queueTracks.contains(where: { $0.id == addedTrack.id }) {
                                    queueTracks.append(addedTrack)
                                    queueTrackIds[addedTrack.id] = queueTrackId
                                    print("✅ [HomeView] Queue now has \(queueTracks.count) tracks")
                                    print("✅ [HomeView] Stored mapping: \(addedTrack.id) -> \(queueTrackId)")
                                } else {
                                    print("⚠️ [HomeView] Track already in queue, skipping")
                                }
                            }
                        )
                    }
                }
            }

            // Recently Played Section
            if !recentlyPlayed.isEmpty {
                Section {
                    // Subheading row
                    Text("Recently Played")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)

                    // Track rows
                    ForEach(Array(recentlyPlayed.prefix(10).enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            track,
                            number: index + 1,
                            showCover: true,
                            onTrackAddedToQueue: { addedTrack, queueTrackId in
                                // Add track and store queue track ID mapping
                                print("⚡ [HomeView] Adding track to queue with ID: \(queueTrackId)")
                                if !queueTracks.contains(where: { $0.id == addedTrack.id }) {
                                    queueTracks.append(addedTrack)
                                    queueTrackIds[addedTrack.id] = queueTrackId
                                    print("✅ [HomeView] Queue now has \(queueTracks.count) tracks")
                                    print("✅ [HomeView] Stored mapping: \(addedTrack.id) -> \(queueTrackId)")
                                } else {
                                    print("⚠️ [HomeView] Track already in queue, skipping")
                                }
                            },
                            trackData: recentlyPlayedData[track.id]
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
    }

    // MARK: - Queue Actions

    private func removeTrackFromQueue(_ track: Track) {
        guard let convexQueueTrackId = queueTrackIds[track.id] else {
            print("❌ [HomeView] No Convex queue track ID found for track: \(track.id)")
            return
        }

        print("🗑️ [HomeView] Removing track: \(track.title)")

        // Store original state for rollback
        let removedTrack = track
        let originalIndex = queueTracks.firstIndex(where: { $0.id == track.id })

        // 1. Optimistically remove from UI - INSTANT
        queueTracks.removeAll { $0.id == track.id }
        queueTrackIds.removeValue(forKey: track.id)
        print("⚡ [HomeView] Optimistically removed - queue now has \(queueTracks.count) tracks")

        // 2. Call API in background
        Task {
            do {
                try await ConvexService.shared.removeTrackFromQueue(queueTrackId: convexQueueTrackId)
                print("✅ [HomeView] Track deleted from server successfully")
            } catch {
                print("❌ [HomeView] Failed to delete track from server: \(error)")

                // Rollback: re-insert track at original position
                if let index = originalIndex {
                    queueTracks.insert(removedTrack, at: min(index, queueTracks.count))
                    queueTrackIds[track.id] = convexQueueTrackId
                    print("↩️ [HomeView] Rolled back delete - restored to queue")
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadHomeData() async {
        guard let userId = authManager.currentUserId else {
            print("❌ [HomeView] No userId")
            return
        }

        // Prevent concurrent loads (fixes -999 cancelled error)
        if isLoading {
            print("⏭️ [HomeView] Already loading, skipping")
            return
        }

        isLoading = true
        print("🔄 [HomeView] Starting load...")

        // Load queue
        do {
            print("📡 [HomeView] Fetching queue for userId: \(userId)")
            let queueData = try await ConvexService.shared.getQueueTracks(userId: userId)

            var tracks: [Track] = []
            var trackIdMap: [String: String] = [:]

            for queueTrack in queueData {
                let artworkUrl = queueTrack.artworkUrl ?? ""
                let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

                let track = Track(
                    id: queueTrack.trackId, // Use SoundCloud track ID
                    title: queueTrack.title,
                    artist: queueTrack.artist,
                    album: "",
                    artwork: highQualityArtwork,
                    duration: queueTrack.duration
                )

                tracks.append(track)
                trackIdMap[queueTrack.trackId] = queueTrack._id // Map SoundCloud ID -> Convex queue track ID
            }

            self.queueTracks = tracks
            self.queueTrackIds = trackIdMap

            print("✅ [HomeView] Loaded \(queueTracks.count) queue tracks!")
        } catch {
            print("❌ [HomeView] Queue error: \(error)")
        }

        // Load recently played
        do {
            print("📡 [HomeView] Fetching play history for userId: \(userId)")
            let history = try await ConvexService.shared.getPlayHistory(userId: userId, limit: 20)

            // Store both Track objects and raw data
            var allTracks: [Track] = []
            var rawDataMap: [String: [String: Any]] = [:]

            for playItem in history {
                let track = playItem.trackData
                let artworkUrl = track.artwork_url ?? track.user.avatar_url ?? ""
                let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

                let trackId = String(track.id)
                let trackObj = Track(
                    id: trackId,
                    title: track.title,
                    artist: track.user.username,
                    album: track.genre ?? "",
                    artwork: highQualityArtwork,
                    duration: Double(track.duration)
                )

                // Convert the SoundCloud track data to dictionary
                if let trackDict = try? JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(track),
                    options: []
                ) as? [String: Any] {
                    rawDataMap[trackId] = trackDict
                }

                allTracks.append(trackObj)
            }

            // Deduplicate tracks based on title and artist
            var seen = Set<String>()
            self.recentlyPlayed = allTracks.filter { track in
                let key = "\(track.title.lowercased())|\(track.artist.lowercased())"
                return seen.insert(key).inserted
            }

            self.recentlyPlayedData = rawDataMap

            print("✅ [HomeView] Loaded \(recentlyPlayed.count) recently played tracks (deduplicated from \(allTracks.count))!")
        } catch {
            print("❌ [HomeView] Play history error: \(error)")
        }

        hasLoaded = true
        isLoading = false
    }
}

#Preview("Light Mode") {
    HomeView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    HomeView()
        .preferredColorScheme(.dark)
}
