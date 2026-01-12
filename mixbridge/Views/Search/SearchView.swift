//
//  SearchView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

// MARK: - Search Source

enum SearchSource: String, CaseIterable, Identifiable {
    case soundcloud = "SoundCloud"
    case library = "Library"

    var id: String { rawValue }

    var placeholder: String {
        switch self {
        case .soundcloud: return "Search SoundCloud"
        case .library: return "Search your library"
        }
    }
}

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
    @State private var searchSource: SearchSource = .soundcloud
    @State private var viewModel = LikedViewModel()
    @State private var libraryViewModel = LibraryViewModel()
    @Namespace private var namespace

    private var filteredLibraryTracks: [TrackItem] {
        guard !searchText.isEmpty else { return [] }
        return viewModel.likedTracks.filter {
            $0.track.title.localizedCaseInsensitiveContains(searchText) ||
            $0.track.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredLibraryPlaylists: [Playlist] {
        guard !searchText.isEmpty else { return [] }

        // Combine liked playlists and user's own library playlists
        let likedPlaylists = viewModel.likedPlaylists.map { $0.playlist }
        let ownPlaylists = libraryViewModel.playlists

        // Deduplicate by ID
        var seen = Set<String>()
        var allPlaylists: [Playlist] = []
        for playlist in likedPlaylists + ownPlaylists {
            if !seen.contains(playlist.id) {
                seen.insert(playlist.id)
                allPlaylists.append(playlist)
            }
        }

        return allPlaylists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.creator.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredLibraryArtists: [ArtistInfo] {
        guard !searchText.isEmpty else { return [] }
        let artists = buildArtistsFromTracks(viewModel.likedTracks)
        return artists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func buildArtistsFromTracks(_ tracks: [TrackItem]) -> [ArtistInfo] {
        var artistsDict: [String: ArtistInfo] = [:]

        for item in tracks {
            let artistName = item.track.artist
            let artistId = String(item.soundCloudTrack.user.id)
            let avatarUrl = item.soundCloudTrack.user.avatar_url?.upgradeArtworkQuality()

            if var existing = artistsDict[artistName] {
                existing.trackCount += 1
                existing.trackItems.append(item)
                artistsDict[artistName] = existing
            } else {
                var artistInfo = ArtistInfo(
                    id: artistId,
                    name: artistName,
                    avatarUrl: avatarUrl,
                    trackCount: 1
                )
                artistInfo.trackItems = [item]
                artistsDict[artistName] = artistInfo
            }
        }

        return artistsDict.values.sorted { $0.trackCount > $1.trackCount }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .searchable(text: $searchText, prompt: searchSource.placeholder)
                .onChange(of: searchText) { oldValue, newValue in
                    guard searchSource == .soundcloud else { return }

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
                .onChange(of: searchSource) { _, _ in
                    HapticManager.selection()
                    searchResult = nil
                    lastSearchedQuery = ""
                }
                .task {
                    await viewModel.observeDatabase()
                }
                .task {
                    await viewModel.observePlaylistsDatabase()
                }
                .task {
                    if let userId = authManager.currentUserId {
                        await libraryViewModel.observeDatabase(userId: userId)
                    }
                }
                .task {
                    if let userId = authManager.currentUserId {
                        await viewModel.refresh(userId: userId)
                        await viewModel.refreshPlaylists(userId: userId)
                        await libraryViewModel.refresh(userId: userId)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if searchText.isEmpty {
                emptyState
            } else if searchSource == .library {
                libraryResultsView
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
        .animation(.default, value: searchText.isEmpty)
        .animation(.default, value: searchSource)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Picker("Search Source", selection: $searchSource) {
                ForEach(SearchSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .glassEffect(.regular)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if recentSearchManager.recentSearches.isEmpty {
                Spacer()
                ContentUnavailableView(
                    searchSource == .soundcloud ? "Search SoundCloud" : "Search your library",
                    systemImage: "magnifyingglass"
                )
                Spacer()
            } else {
                recentSearchesView
            }
        }
    }

    private var libraryResultsView: some View {
        let listContext = Array(filteredLibraryTracks)
        let hasContent: Bool = {
            switch selectedTab {
            case .tracks: return !filteredLibraryTracks.isEmpty
            case .playlists: return !filteredLibraryPlaylists.isEmpty
            case .artists: return !filteredLibraryArtists.isEmpty
            }
        }()

        return VStack(spacing: 0) {
            Picker("Library Results", selection: $selectedTab) {
                ForEach(SearchTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .glassEffect(.regular)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if hasContent {
                List {
                    switch selectedTab {
                    case .tracks:
                        ForEach(Array(filteredLibraryTracks.enumerated()), id: \.element.id) { index, item in
                            TrackRow(
                                item.track,
                                number: index + 1,
                                showCover: true,
                                soundCloudTrack: item.soundCloudTrack,
                                listContext: listContext,
                                indexInList: index
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                            .listRowSeparator(index == filteredLibraryTracks.count - 1 ? .hidden : .visible, edges: .bottom)
                        }

                    case .playlists:
                        ForEach(Array(filteredLibraryPlaylists.enumerated()), id: \.element.id) { index, playlist in
                            libraryPlaylistRow(playlist: playlist, index: index, total: filteredLibraryPlaylists.count)
                        }

                    case .artists:
                        ForEach(Array(filteredLibraryArtists.enumerated()), id: \.element.id) { index, artist in
                            libraryArtistRow(artist: artist, index: index, total: filteredLibraryArtists.count)
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                Spacer()
                switch selectedTab {
                case .tracks:
                    ContentUnavailableView("No tracks found", systemImage: "music.note")
                case .playlists:
                    ContentUnavailableView("No playlists found", systemImage: "music.note.list")
                case .artists:
                    ContentUnavailableView("No artists found", systemImage: "person.2")
                }
                Spacer()
            }
        }
        .onChange(of: selectedTab) { _, _ in
            HapticManager.selection()
        }
        .navigationDestination(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist)
                .navigationTransition(.zoom(sourceID: "library-\(playlist.id)", in: namespace))
        }
        .navigationDestination(item: $selectedArtist) { artist in
            ArtistDetailView(artist: artist)
                .navigationTransition(.zoom(sourceID: "library-artist-\(artist.id)", in: namespace))
        }
    }

    private func libraryPlaylistRow(playlist: Playlist, index: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            if !playlist.artwork.isEmpty,
               let url = URL(string: playlist.artwork) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
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
        .contentShape(Rectangle())
        .matchedTransitionSource(id: "library-\(playlist.id)", in: namespace)
        .onTapGesture {
            HapticManager.selection()
            selectedPlaylist = playlist
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
        .listRowSeparator(index == total - 1 ? .hidden : .visible, edges: .bottom)
    }

    private func libraryArtistRow(artist: ArtistInfo, index: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            if let avatarUrl = artist.avatarUrl,
               let url = URL(string: avatarUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(artist.trackCount) \(artist.trackCount == 1 ? "track" : "tracks")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .matchedTransitionSource(id: "library-artist-\(artist.id)", in: namespace)
        .onTapGesture {
            HapticManager.selection()
            selectedArtist = artist
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
        .listRowSeparator(index == total - 1 ? .hidden : .visible, edges: .bottom)
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
        VStack(spacing: 0) {
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            List {
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
    }

    private func resultsView(results: SearchResult) -> some View {
        let trackItems = results.tracks.prefix(20).map { TrackItem(soundCloudTrack: $0) }
        let listContext = Array(trackItems)
        let hasContent: Bool = {
            switch selectedTab {
            case .tracks: return !results.tracks.isEmpty
            case .playlists: return !results.playlists.isEmpty
            case .artists: return !results.users.isEmpty
            }
        }()

        return VStack(spacing: 0) {
            Picker("Search Results", selection: $selectedTab) {
                ForEach(SearchTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .glassEffect(.regular)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if hasContent {
                List {
                    switch selectedTab {
                    case .tracks:
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
                            .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                            .listRowSeparator(index == trackItems.count - 1 ? .hidden : .visible, edges: .bottom)
                        }

                    case .playlists:
                        let playlists = Array(results.playlists.prefix(15))
                        ForEach(Array(playlists.enumerated()), id: \.element.id) { index, scPlaylist in
                            playlistRow(scPlaylist: scPlaylist, index: index, total: playlists.count)
                        }

                    case .artists:
                        ForEach(Array(results.users.prefix(15).enumerated()), id: \.element.id) { index, scUser in
                            artistRow(scUser: scUser, index: index, total: min(results.users.count, 15))
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                Spacer()
                switch selectedTab {
                case .tracks:
                    ContentUnavailableView("No tracks found", systemImage: "music.note")
                case .playlists:
                    ContentUnavailableView("No playlists found", systemImage: "music.note.list")
                case .artists:
                    ContentUnavailableView("No artists found", systemImage: "person.2")
                }
                Spacer()
            }
        }
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

    private func playlistRow(scPlaylist: SoundCloudPlaylist, index: Int, total: Int) -> some View {
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
        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
        .listRowSeparator(index == total - 1 ? .hidden : .visible, edges: .bottom)
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
        .listRowSeparator(index == total - 1 ? .hidden : .visible, edges: .bottom)
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
