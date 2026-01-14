//
//  LikedView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

// MARK: - Liked Tab

enum LikedTab: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case playlists = "Playlists"

    var id: String { rawValue }
}

struct LikedView: View {
    @State private var viewModel = LikedViewModel()
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var selectedTab: LikedTab = .tracks
    @State private var selectedPlaylist: Playlist?
    @Namespace private var namespace

    private let revealThreshold: CGFloat = 90

    private var filteredTracks: [TrackItem] {
        guard !searchText.isEmpty else { return viewModel.likedTracks }
        return viewModel.likedTracks.filter {
            $0.track.title.localizedCaseInsensitiveContains(searchText) ||
            $0.track.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredPlaylists: [PlaylistItem] {
        guard !searchText.isEmpty else { return viewModel.likedPlaylists }
        return viewModel.likedPlaylists.filter {
            $0.playlist.name.localizedCaseInsensitiveContains(searchText) ||
            $0.playlist.creator.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        content
            .navigationTitle("Liked")
            .navigationBarTitleDisplayMode(.large)
            // Start database observation
            .task {
                await viewModel.observeDatabase()
            }
            .task {
                await viewModel.observePlaylistsDatabase()
            }
            // Fetch fresh data
            .task {
                if let userId = authManager.currentUserId {
                    await viewModel.refresh(userId: userId)
                    await viewModel.refreshPlaylists(userId: userId)
                }
            }
            .refreshable {
                if let userId = authManager.currentUserId {
                    await viewModel.refresh(userId: userId, forceRefresh: true)
                    await viewModel.refreshPlaylists(userId: userId, forceRefresh: true)
                }
            }
            .navigationDestination(item: $selectedPlaylist) { playlist in
                PlaylistDetailView(playlist: playlist)
                    .navigationTransition(.zoom(sourceID: "liked-\(playlist.id)", in: namespace))
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.likedTracks.isEmpty && viewModel.likedPlaylists.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.error, viewModel.likedTracks.isEmpty && viewModel.likedPlaylists.isEmpty {
            errorView(error)
        } else if viewModel.likedTracks.isEmpty && viewModel.likedPlaylists.isEmpty {
            emptyState
        } else {
            likedList
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task {
                    if let userId = authManager.currentUserId {
                        await viewModel.refresh(userId: userId)
                        await viewModel.refreshPlaylists(userId: userId)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Liked Items",
            systemImage: "heart",
            description: Text("Your liked songs and playlists will appear here")
        )
    }

    private var likedList: some View {
        List {
            // Tab Picker Section
            Section {
                Picker("Liked Items", selection: $selectedTab) {
                    ForEach(LikedTab.allCases) { tab in
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
                tracksContent

            case .playlists:
                playlistsContent
            }
        }
        .listStyle(.plain)
        .onChange(of: selectedTab) { _, _ in
            HapticManager.selection()
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            guard oldPhase == .interacting, newPhase != .interacting else { return }
            let geometry = context.geometry
            let offset = geometry.contentOffset.y + geometry.contentInsets.top

            if offset < -revealThreshold && !isSearchPresented {
                isSearchPresented = true
                HapticManager.light()
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search Liked")
        .navigationAllowDismissalGestures(allowDismissalGesture)
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
    }

    // MARK: - Tracks Content

    @ViewBuilder
    private var tracksContent: some View {
        if filteredTracks.isEmpty && !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        } else if filteredTracks.isEmpty {
            ContentUnavailableView("No liked tracks", systemImage: "music.note")
                .listRowSeparator(.hidden)
        } else {
            let rows = filteredTracks.indexedRows()
            ForEach(rows) { row in
                TrackRow(
                    row.item.track,
                    number: row.index + 1,
                    showCover: true,
                    soundCloudTrack: row.item.soundCloudTrack,
                    listContext: filteredTracks,
                    indexInList: row.index
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(row.index == 0 ? .hidden : .visible, edges: .top)
                .listRowSeparator(row.index == rows.count - 1 ? .hidden : .visible, edges: .bottom)
            }
        }
    }

    // MARK: - Playlists Content

    @ViewBuilder
    private var playlistsContent: some View {
        if viewModel.isLoadingPlaylists && viewModel.likedPlaylists.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowSeparator(.hidden)
        } else if filteredPlaylists.isEmpty && !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        } else if filteredPlaylists.isEmpty {
            ContentUnavailableView("No liked playlists", image: "playlist")
                .listRowSeparator(.hidden)
        } else {
            let rows = filteredPlaylists.indexedRows()
            ForEach(rows) { row in
                playlistRow(item: row.item, index: row.index, total: rows.count)
            }
        }
    }

    // MARK: - Playlist Row

    private func playlistRow(item: PlaylistItem, index: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            if item.playlist.artwork.starts(with: "http"),
               let url = URL(string: item.playlist.artwork) {
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
                Text(item.playlist.name)
                    .font(.body)
                    .lineLimit(1)

                Text(item.playlist.creator)
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
        .matchedTransitionSource(id: "liked-\(item.playlist.id)", in: namespace)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.selection()
            selectedPlaylist = item.playlist
        }
        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
        .listRowSeparator(index == total - 1 ? .hidden : .visible, edges: .bottom)
    }
}

#Preview("Light Mode") {
    NavigationStack {
        LikedView()
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        LikedView()
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .preferredColorScheme(.dark)
}
