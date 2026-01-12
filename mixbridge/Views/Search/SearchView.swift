//
//  SearchView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

// MARK: - Search Tab

enum SearchTab: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case playlists = "Playlists"
    case artists = "Artists"

    var id: String { rawValue }
}

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
    @State private var selectedArtist: ArtistInfo?
    @State private var selectedTab: SearchTab = .tracks
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
        let trackItems = results.tracks.prefix(20).map { TrackItem(soundCloudTrack: $0) }
        let listContext = Array(trackItems)

        return List {
            // Tab Picker Section
            Section {
                Picker("Search Results", selection: $selectedTab) {
                    ForEach(SearchTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .glassEffect(.regular)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            // Content based on selected tab
            switch selectedTab {
            case .tracks:
                if results.tracks.isEmpty {
                    ContentUnavailableView("No tracks found", systemImage: "music.note")
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(trackItems.enumerated()), id: \.element.id) { index, item in
                        TrackRow(
                            item.track,
                            number: index + 1,
                            showCover: true,
                            soundCloudTrack: item.soundCloudTrack,
                            listContext: listContext,
                            indexInList: index
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }

            case .playlists:
                if results.playlists.isEmpty {
                    ContentUnavailableView("No playlists found", systemImage: "music.note.list")
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(results.playlists.prefix(15), id: \.id) { scPlaylist in
                        playlistRow(scPlaylist: scPlaylist)
                    }
                }

            case .artists:
                if results.users.isEmpty {
                    ContentUnavailableView("No artists found", systemImage: "person.2")
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(results.users.prefix(15).enumerated()), id: \.element.id) { index, scUser in
                        artistRow(scUser: scUser, index: index, total: min(results.users.count, 15))
                    }
                }
            }
        }
        .listStyle(.plain)
        .onChange(of: selectedTab) { _, _ in
            HapticManager.selection()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist)
                .navigationTransition(.zoom(sourceID: "search-\(playlist.id)", in: namespace))
        }
        .navigationDestination(item: $selectedArtist) { artist in
            ArtistDetailView(artist: artist)
                .navigationTransition(.zoom(sourceID: "search-artist-\(artist.id)", in: namespace))
        }
    }

    // MARK: - Playlist Row

    private func playlistRow(scPlaylist: SoundCloudPlaylist) -> some View {
        let playlist = Playlist(
            id: String(scPlaylist.id),
            name: scPlaylist.title,
            creator: scPlaylist.user.username,
            artwork: scPlaylist.primaryArtworkUrl,
            tracks: [],
            lastUpdated: Date()
        )

        return HStack(spacing: 12) {
            if playlist.artwork.starts(with: "http"),
               let url = URL(string: playlist.artwork) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.body)
                    .lineLimit(1)

                Text(playlist.creator)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .matchedTransitionSource(id: "search-\(playlist.id)", in: namespace)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.selection()
            selectedPlaylist = playlist
        }
    }

    // MARK: - Artist Row (matches AllArtistsView)

    private func artistRow(scUser: SoundCloudUser, index: Int, total: Int) -> some View {
        let artist = ArtistInfo(
            id: String(scUser.id),
            name: scUser.username,
            avatarUrl: scUser.avatar_url?.upgradeArtworkQuality(),
            trackCount: 0
        )

        return HStack(spacing: 12) {
            if let avatarUrl = artist.avatarUrl,
               let url = URL(string: avatarUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "music.mic")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.body)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
        .matchedTransitionSource(id: "search-artist-\(artist.id)", in: namespace)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.selection()
            selectedArtist = artist
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
