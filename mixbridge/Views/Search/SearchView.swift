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

private struct SoundCloudPlaylistRow: Identifiable, Equatable {
    let playlist: SoundCloudPlaylist
    let index: Int

    var id: Int { playlist.id }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

private struct SoundCloudUserRow: Identifiable, Equatable {
    let user: SoundCloudUser
    let index: Int

    var id: Int { user.id }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
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

    private var headerView: some View {
        Text("Search")
            .font(.largeTitle)
            .fontWeight(.bold)
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 6)
    }

    private var showHeader: Bool {
        searchText.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if showHeader {
                    headerView
                }
                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: searchSource.placeholder)
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
                .task(id: authManager.currentUserId) {
                    let userId = authManager.currentUserId

                    async let observeLikedTracks: Void = viewModel.observeDatabase()
                    async let observeLikedPlaylists: Void = viewModel.observePlaylistsDatabase()
                    async let observeLibrary: Void = {
                        guard let userId else { return }
                        await libraryViewModel.observeDatabase(userId: userId)
                    }()

                    if let userId {
                        await viewModel.refresh(userId: userId)
                        await viewModel.refreshPlaylists(userId: userId)
                        await libraryViewModel.refresh(userId: userId)
                    }

                    _ = await (observeLikedTracks, observeLikedPlaylists, observeLibrary)
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
            } else if let results = searchResult, !isSearching {
                resultsView(results: results)
            } else if let error, !isSearching {
                errorView(error)
            } else {
                // Loading state - show when searching or waiting for results
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
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
                ContentUnavailableView {
                    Label(searchSource == .soundcloud ? "Search SoundCloud" : "Search Your Library", systemImage: "magnifyingglass")
                }
                .padding(.top, 100)
            } else {
                recentSearchesView
            }
        }
    }

    private var libraryResultsView: some View {
        let hasContent: Bool = {
            switch selectedTab {
            case .tracks: return !filteredLibraryTracks.isEmpty
            case .playlists: return !filteredLibraryPlaylists.isEmpty
            case .artists: return !filteredLibraryArtists.isEmpty
            }
        }()

        return List {
            Section {
                Picker("Library Results", selection: $selectedTab) {
                    ForEach(SearchTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .glassEffect(.regular)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)

            if hasContent {
                switch selectedTab {
                case .tracks:
                    let listContext = Array(filteredLibraryTracks)
                    let trackRows = filteredLibraryTracks.indexedRows()
                    ForEach(trackRows) { row in
                        TrackRow(
                            row.item.track,
                            number: row.index + 1,
                            showCover: true,
                            soundCloudTrack: row.item.soundCloudTrack,
                            listContext: listContext,
                            indexInList: row.index
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(row.index == 0 ? .hidden : .visible, edges: .top)
                        .listRowSeparator(row.index == trackRows.count - 1 ? .hidden : .visible, edges: .bottom)
                    }

                case .playlists:
                    let playlistRows = filteredLibraryPlaylists.indexedRows()
                    ForEach(playlistRows) { row in
                        libraryPlaylistRow(playlist: row.item, index: row.index, total: playlistRows.count)
                    }

                case .artists:
                    let artistRows = filteredLibraryArtists.indexedRows()
                    ForEach(artistRows) { row in
                        libraryArtistRow(artist: row.item, index: row.index, total: artistRows.count)
                    }
                }
            } else {
                Section {
                    Group {
                        switch selectedTab {
                        case .tracks:
                            ContentUnavailableView {
                                Label("No tracks found", systemImage: "music.note")
                            }
                        case .playlists:
                            ContentUnavailableView {
                                Label("No playlists found", image: "playlist")
                            }
                        case .artists:
                            ContentUnavailableView {
                                Label("No artists found", systemImage: "person.2")
                            }
                        }
                    }
                    .padding(.top, 100)
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
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
                        Image("playlist")
                            .renderingMode(.template)
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

    private func resultsView(results: SearchResult) -> some View {
        let hasContent: Bool = {
            switch selectedTab {
            case .tracks: return !results.tracks.isEmpty
            case .playlists: return !results.playlists.isEmpty
            case .artists: return !results.users.isEmpty
            }
        }()

        return List {
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

            if hasContent {
                switch selectedTab {
                case .tracks:
                    let trackItems = results.tracks.prefix(20).map { TrackItem(soundCloudTrack: $0) }
                    let listContext = Array(trackItems)
                    let trackRows = trackItems.indexedRows()
                    ForEach(trackRows) { row in
                        TrackRow(
                            row.item.track,
                            number: row.index + 1,
                            showCover: true,
                            soundCloudTrack: row.item.soundCloudTrack,
                            listContext: listContext,
                            indexInList: row.index
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(row.index == 0 ? .hidden : .visible, edges: .top)
                        .listRowSeparator(row.index == trackRows.count - 1 ? .hidden : .visible, edges: .bottom)
                    }

                case .playlists:
                    let playlists = Array(results.playlists.prefix(15))
                    let playlistRows = playlists.enumerated().map { SoundCloudPlaylistRow(playlist: $0.element, index: $0.offset) }
                    ForEach(playlistRows) { row in
                        playlistRow(scPlaylist: row.playlist, index: row.index, total: playlistRows.count)
                    }

                case .artists:
                    let users = Array(results.users.prefix(15))
                    let userRows = users.enumerated().map { SoundCloudUserRow(user: $0.element, index: $0.offset) }
                    ForEach(userRows) { row in
                        artistRow(scUser: row.user, index: row.index, total: userRows.count)
                    }
                }
            } else {
                Section {
                    Group {
                        switch selectedTab {
                        case .tracks:
                            ContentUnavailableView {
                                Label("No tracks found", systemImage: "music.note")
                            }
                        case .playlists:
                            ContentUnavailableView {
                                Label("No playlists found", image: "playlist")
                            }
                        case .artists:
                            ContentUnavailableView {
                                Label("No artists found", systemImage: "person.2")
                            }
                        }
                    }
                    .padding(.top, 100)
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .onChange(of: selectedTab) { _, _ in
            HapticManager.selection()
        }
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
                            Image("playlist")
                                .renderingMode(.template)
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
                        Image("playlist")
                            .renderingMode(.template)
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
                        Image("microphone")
                            .renderingMode(.template)
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
