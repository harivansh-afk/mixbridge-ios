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

    @State private var searchResult: SearchResult?
    @State private var isSearching = false
    @State private var error: Error?
    @State private var searchTask: Task<Void, Never>?
    @State private var lastSearchedQuery = ""
    @State private var recentSearchManager = RecentSearchManager.shared

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .searchable(text: $searchText, prompt: "Search")
                .onChange(of: searchText) { oldValue, newValue in
                    searchTask?.cancel()

                    if newValue.isEmpty {
                        searchResult = nil
                        lastSearchedQuery = ""
                        error = nil
                        return
                    }

                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            errorView(error)
        } else if let results = searchResult {
            resultsView(results: results)
        }
    }

    private var emptyState: some View {
        Group {
            if recentSearchManager.recentSearches.isEmpty {
                ContentUnavailableView(
                    "Search for music",
                    systemImage: "magnifyingglass"
                )
            } else {
                recentSearchesView
            }
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Search Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task { await performSearch(query: searchText) }
            }
            .buttonStyle(.bordered)
        }
    }

    private var recentSearchesView: some View {
        List {
            Section {
                ForEach(recentSearchManager.recentSearches, id: \.self) { query in
                    Button {
                        searchText = query
                        HapticManager.selection()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)

                            Text(query)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        recentSearchManager.removeSearch(recentSearchManager.recentSearches[index])
                    }
                    HapticManager.light()
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") {
                        withAnimation {
                            recentSearchManager.clearAll()
                        }
                        HapticManager.light()
                    }
                    .font(.caption)
                    .textCase(.none)
                }
            }
        }
        .listStyle(.plain)
    }

    private func resultsView(results: SearchResult) -> some View {
        List {
            if !results.tracks.isEmpty {
                Section("Tracks") {
                    ForEach(Array(results.tracks.prefix(10).enumerated()), id: \.element.id) { index, scTrack in
                        let item = TrackItem(soundCloudTrack: scTrack)
                        TrackRow(
                            item.track,
                            number: index + 1,
                            showCover: true,
                            soundCloudTrack: item.soundCloudTrack
                        )
                    }
                }
            }

            if !results.playlists.isEmpty {
                Section("Playlists") {
                    ForEach(results.playlists.prefix(5), id: \.id) { scPlaylist in
                        let artworkUrl = scPlaylist.artwork_url ?? scPlaylist.user.avatar_url ?? ""
                        let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

                        let playlist = Playlist(
                            id: String(scPlaylist.id),
                            name: scPlaylist.title,
                            creator: scPlaylist.user.username,
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
                                    CachedAsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Color.clear
                                    }
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(.body)
                                        .lineLimit(2)

                                    Text("\(scPlaylist.track_count ?? 0) tracks • \(playlist.creator)")
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
        guard query != lastSearchedQuery else { return }
        guard let userId = authManager.currentUserId else { return }

        isSearching = true
        error = nil

        do {
            let results = try await BackgroundExecutor.run {
                try await ConvexService.shared.search(userId: userId, query: query, limit: 20)
            }

            if query == searchText {
                self.searchResult = results
                self.lastSearchedQuery = query
                recentSearchManager.addSearch(query)
            }
        } catch {
            if query == searchText {
                self.error = error
            }
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
