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
    @State private var selectedPlaylist: Playlist?
    @Namespace private var namespace

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
            VStack {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                Spacer()
            }
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
                Task { await performSearch(query: searchText, forceRefresh: true) }
            }
            .buttonStyle(.bordered)
        }
    }

    private var recentSearchesView: some View {
        List {
            HStack {
                Text("Recent")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.primary)
                Spacer()
                Button("Clear") {
                    withAnimation {
                        recentSearchManager.clearAll()
                    }
                    HapticManager.light()
                }
                .font(.caption)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))

            ForEach(recentSearchManager.recentSearches, id: \.self) { query in
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)

                    Text(query)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    searchText = query
                    HapticManager.selection()
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    recentSearchManager.removeSearch(recentSearchManager.recentSearches[index])
                }
                HapticManager.light()
            }
        }
        .listStyle(.plain)
    }

    private func resultsView(results: SearchResult) -> some View {
        let trackItems = results.tracks.prefix(10).map { TrackItem(soundCloudTrack: $0) }
        let listContext = Array(trackItems)

        return List {
            if !results.tracks.isEmpty {
                Text("Tracks")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.primary)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))

                ForEach(Array(trackItems.enumerated()), id: \.element.id) { index, item in
                    TrackRow(
                        item.track,
                        number: index + 1,
                        showCover: true,
                        soundCloudTrack: item.soundCloudTrack,
                        listContext: listContext,
                        indexInList: index
                    )
                }
            }

            if !results.playlists.isEmpty {
                Text("Playlists")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.primary)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))

                ForEach(results.playlists.prefix(5), id: \.id) { scPlaylist in
                    let playlist = Playlist(
                        id: String(scPlaylist.id),
                        name: scPlaylist.title,
                        creator: scPlaylist.user.username,
                        artwork: scPlaylist.primaryArtworkUrl,
                        tracks: [],
                        lastUpdated: Date()
                    )

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
                        } else {
                            Color.clear
                                .frame(width: 60, height: 60)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name)
                                .font(.body)
                                .lineLimit(1)

                            Text(playlist.creator)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .matchedTransitionSourceIfAvailable(id: "search-\(playlist.id)", in: namespace)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.selection()
                        selectedPlaylist = playlist
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist)
                .navigationTransitionIfAvailable(sourceID: "search-\(playlist.id)", in: namespace)
        }
    }

    private func performSearch(query: String, forceRefresh: Bool = false) async {
        guard !query.isEmpty else { return }
        guard forceRefresh || query != lastSearchedQuery else { return }
        guard let userId = authManager.currentUserId else { return }

        // Try local cache first for instant UI.
        do {
            if let cached = try await SearchSync.shared.getLocalSearchResult(userId: userId, query: query) {
                if query == searchText {
                    self.searchResult = cached.result
                    self.error = nil
                    self.lastSearchedQuery = query
                    recentSearchManager.addSearch(query)
                }
            }
        } catch {
            // Cache decode failure shouldn't block live search.
        }

        // Only show spinner if we have nothing to display yet.
        isSearching = (searchResult == nil)
        error = nil

        do {
            let results = try await SearchSync.shared.fetchAndStoreSearch(
                userId: userId,
                query: query,
                limit: 20,
                forceRefresh: forceRefresh
            )

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
