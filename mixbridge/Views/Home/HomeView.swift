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
    @Environment(QueueManager.self) private var queueManager
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
        } else if queueManager.queueTracks.isEmpty && recentlyPlayed.isEmpty {
            emptyState
        } else {
            homeList
        }
    }

    private var skeletonLoadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var profileAvatar: some View {
        HStack {
            if let avatarUrl = profileManager.avatarUrl,
               let url = URL(string: avatarUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 35, height: 35)
                .clipShape(Circle())
                .onTapGesture {
                    HapticManager.light()
                    showingAccount.toggle()
                }
            } else {
                ProfileCircleView(
                    profileImage: nil,
                    userName: profileManager.displayName,
                )
                .onTapGesture {
                    HapticManager.light()
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
            if !queueManager.queueTracks.isEmpty {
                Section {
                    // Subheading row
                    Text("Queue")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)

                    // Track rows
                    ForEach(Array(queueManager.queueTracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            track,
                            number: index + 1,
                            showCover: true,
                            onDelete: {
                                Task {
                                    try? await queueManager.removeTrack(track)
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
                            trackData: recentlyPlayedData[track.id]
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
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

        // Load queue via QueueManager
        do {
            try await queueManager.loadQueue(userId: userId)
        } catch {
            print("❌ [HomeView] Queue error: \(error)")
        }

        // Load recently played
        do {
            print("📡 [HomeView] Fetching play history for userId: \(userId)")
            let history = try await BackgroundExecutor.run {
                try await ConvexService.shared.getPlayHistory(userId: userId, limit: 20)
            }

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
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    HomeView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .preferredColorScheme(.dark)
}
