//
//  SearchView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct SearchView: View {
    @State private var searchText = ""
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager
    @State private var searchResults: SearchResponse?
    @State private var searchTracksData: [String: [String: Any]] = [:] // Track ID -> raw data
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var lastSearchedQuery = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .searchable(text: $searchText, prompt: "Search SoundCloud...")
                .onChange(of: searchText) { oldValue, newValue in
                    // Cancel previous search
                    searchTask?.cancel()

                    if newValue.isEmpty {
                        searchResults = nil
                        lastSearchedQuery = ""
                        return
                    }

                    // Debounce: Wait 500ms before searching
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

                        // Check if still the current query after delay
                        guard !Task.isCancelled else { return }

                        await performSearch(query: newValue)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if searchText.isEmpty {
            emptyState
        } else if isSearching {
            ProgressView("Searching...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let results = searchResults {
            resultsView(results: results)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Search SoundCloud",
            systemImage: "magnifyingglass",
            description: Text("Find tracks, playlists, and artists")
        )
    }

    private func resultsView(results: SearchResponse) -> some View {
        List {
            if !results.tracks.isEmpty {
                Section("Tracks") {
                    ForEach(Array(results.tracks.prefix(10).enumerated()), id: \.element.id) { index, soundcloudTrack in
                        let artworkUrl = soundcloudTrack.artwork_url ?? soundcloudTrack.user.avatar_url ?? ""
                        let highQualityArtwork = artworkUrl.upgradeArtworkQuality()
                        let trackId = String(soundcloudTrack.id)

                        let track = Track(
                            id: trackId,
                            title: soundcloudTrack.title,
                            artist: soundcloudTrack.user.username,
                            album: soundcloudTrack.genre ?? "",
                            artwork: highQualityArtwork,
                            duration: Double(soundcloudTrack.duration)
                        )

                        TrackRow(
                            track,
                            number: index + 1,
                            showCover: true,
                            trackData: searchTracksData[trackId]
                        )
                        .onAppear {
                            // Store raw data when row appears
                            if searchTracksData[trackId] == nil,
                               let rawDict = try? JSONSerialization.jsonObject(
                                with: JSONEncoder().encode(soundcloudTrack),
                                options: []
                               ) as? [String: Any] {
                                searchTracksData[trackId] = rawDict
                            }
                        }
                    }
                }
            }

            if !results.playlists.isEmpty {
                Section("Playlists") {
                    ForEach(results.playlists.prefix(5), id: \.id) { soundcloudPlaylist in
                        let artworkUrl = soundcloudPlaylist.artwork_url ?? soundcloudPlaylist.user.avatar_url ?? ""
                        let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

                        let playlist = Playlist(
                            id: String(soundcloudPlaylist.id),
                            name: soundcloudPlaylist.title,
                            creator: soundcloudPlaylist.user.username,
                            artwork: highQualityArtwork,
                            tracks: [],
                            lastUpdated: Date()
                        )

                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            HStack(spacing: 12) {
                                if playlist.artwork.starts(with: "http"),
                                   let url = URL(string: playlist.artwork) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(.gray.opacity(0.3))
                                    }
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(.body)
                                        .lineLimit(2)

                                    Text("\(soundcloudPlaylist.track_count ?? 0) tracks • \(playlist.creator)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                        .haptic(.selection)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func performSearch(query: String) async {
        guard !query.isEmpty else { return }

        // Skip if we already searched for this exact query
        guard query != lastSearchedQuery else {
            print("⏭️ [Search] Already searched for '\(query)', skipping")
            return
        }

        isSearching = true
        print("🔍 [Search] Searching for: '\(query)'")

        do {
            let results = try await BackendAPI.shared.search(query: query, limit: 20)

            // Only update if this is still the current search query
            if query == searchText {
                self.searchResults = results
                self.lastSearchedQuery = query
                print("✅ [Search] Results for '\(query)': \(results.tracks.count) tracks, \(results.playlists.count) playlists")
            } else {
                print("⏭️ [Search] Discarding stale results for '\(query)' (current: '\(searchText)')")
            }
        } catch {
            print("❌ [Search] Error searching for '\(query)': \(error)")
        }

        isSearching = false
    }
}

#Preview("Light Mode") {
    SearchView()
        .environment(AuthManager.shared)
        .environment(QueueManager.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    SearchView()
        .environment(AuthManager.shared)
        .environment(QueueManager.shared)
        .preferredColorScheme(.dark)
}
