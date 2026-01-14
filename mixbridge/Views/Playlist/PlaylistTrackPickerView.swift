//
//  PlaylistTrackPickerView.swift
//  mixbridge
//
//  Apple Music-style track picker for playlist creation.
//  Uses native SwiftUI List with insetGrouped sections.
//

import SwiftUI

struct PlaylistTrackPickerView: View {
    @Bindable var viewModel: CreatePlaylistViewModel
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    private var navigationTitle: String {
        let count = viewModel.selectedCount
        if count == 0 {
            return "Add to \"\(viewModel.playlistName)\""
        } else {
            let songText = count == 1 ? "song" : "songs"
            return "\(count) \(songText) added to \"\(viewModel.playlistName)\""
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.searchText.isEmpty {
                    searchResultsSection
                } else {
                    librarySection
                    suggestionsSection
                }
            }
            .listStyle(InsetGroupedListStyle())
            .listSectionSpacing(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Artists, Songs, and More")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        viewModel.goBackToNameEntry()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createPlaylist()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(viewModel.canCreatePlaylist ? Color.accentColor : .secondary)
                    }
                    .disabled(!viewModel.canCreatePlaylist || viewModel.isCreating)
                }
            }
            .task {
                if let userId = authManager.currentUserId {
                    await viewModel.loadTrackSources(userId: userId)
                }
            }
            .onChange(of: viewModel.searchText) { _, newValue in
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard viewModel.searchText == newValue else { return }
                    if let userId = authManager.currentUserId {
                        await viewModel.search(userId: userId)
                    }
                }
            }
        }
    }

    // MARK: - Library Section

    @ViewBuilder
    private var librarySection: some View {
        Section {
            NavigationLink {
                TrackSelectionListView(
                    title: "Liked Tracks",
                    tracks: viewModel.likedTracks,
                    viewModel: viewModel
                )
            } label: {
                Label {
                    Text("Liked Tracks")
                } icon: {
                    Image("heart")
                        .resizable()
                        .frame(width: 25, height: 25)
                }
            }

            NavigationLink {
                TrackSelectionListView(
                    title: "Recently Played",
                    tracks: viewModel.recentlyPlayed,
                    viewModel: viewModel
                )
            } label: {
                Label {
                    Text("Recently Played")
                } icon: {
                    Image("clock")
                        .resizable()
                        .frame(width: 25, height: 25)
                }
            }

            NavigationLink {
                PlaylistSelectionListView(
                    playlists: viewModel.libraryPlaylists,
                    viewModel: viewModel
                )
            } label: {
                Label {
                    Text("Playlists")
                } icon: {
                    Image("playlist")
                        .resizable()
                        .frame(width: 25, height: 25)
                }
            }
        } header: {
            Text("Library")
        }
    }

    // MARK: - Suggestions Section

    @ViewBuilder
    private var suggestionsSection: some View {
        if !viewModel.filteredRecentlyPlayed.isEmpty {
            let items = Array(viewModel.filteredRecentlyPlayed.prefix(15))
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SelectableTrackRow(
                        track: item.track,
                        isSelected: viewModel.isSelected(item)
                    ) {
                        viewModel.toggleTrackSelection(item)
                    }
                    .listRowInsets(EdgeInsets(
                        top: index == 0 ? 16 : 6,
                        leading: 16,
                        bottom: index == items.count - 1 ? 16 : 6,
                        trailing: 16
                    ))
                }
            } header: {
                Text("Suggestions")
            }
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsSection: some View {
        if viewModel.isSearching {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
                .listRowBackground(Color(.systemGroupedBackground))
            }
        } else if viewModel.searchResults.isEmpty {
            Section {
                ContentUnavailableView.search(text: viewModel.searchText)
                    .listRowBackground(Color(.systemGroupedBackground))
            }
        } else {
            Section {
                ForEach(viewModel.searchResults) { item in
                    SelectableTrackRow(
                        track: item.track,
                        isSelected: viewModel.isSelected(item)
                    ) {
                        viewModel.toggleTrackSelection(item)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color(.systemGroupedBackground))
                }
            } header: {
                Text("Search Results")
            }
        }
    }

    // MARK: - Helpers

    private func createPlaylist() {
        Task {
            if let userId = authManager.currentUserId {
                if let _ = await viewModel.createPlaylist(userId: userId) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Track Selection List View (Pushed View)

private struct TrackSelectionListView: View {
    let title: String
    let tracks: [TrackItem]
    @Bindable var viewModel: CreatePlaylistViewModel

    var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "No Tracks",
                    systemImage: "music.note",
                    description: Text("No tracks available")
                )
            } else {
                List {
                    Section {
                        ForEach(tracks) { item in
                            SelectableTrackRow(
                                track: item.track,
                                isSelected: viewModel.isSelected(item)
                            ) {
                                viewModel.toggleTrackSelection(item)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color(.systemGroupedBackground))
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .listSectionSpacing(16)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Playlist Selection List View (Pushed View)

private struct PlaylistSelectionListView: View {
    let playlists: [Playlist]
    @Bindable var viewModel: CreatePlaylistViewModel
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Group {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    image: "playlist",
                    description: Text("No playlists available")
                )
            } else {
                List {
                    Section {
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                PlaylistTracksSelectionView(
                                    playlist: playlist,
                                    viewModel: viewModel
                                )
                            } label: {
                                PlaylistRowView(playlist: playlist)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color(.systemGroupedBackground))
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .listSectionSpacing(16)
            }
        }
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Playlist Row View

private struct PlaylistRowView: View {
    let playlist: Playlist
    
    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImagePhase(url: URL(string: playlist.artwork)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Color(.tertiarySystemFill)
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(playlist.creator)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Playlist Tracks Selection View (Drill-in from Playlist)

private struct PlaylistTracksSelectionView: View {
    let playlist: Playlist
    @Bindable var viewModel: CreatePlaylistViewModel
    @Environment(AuthManager.self) private var authManager

    @State private var tracks: [TrackItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                ContentUnavailableView(
                    "No Tracks",
                    systemImage: "music.note",
                    description: Text("This playlist is empty")
                )
            } else {
                List {
                    // Add All button
                    Section {
                        Button {
                            viewModel.addTracksFromPlaylist(tracks)
                            HapticManager.medium()
                        } label: {
                            Label {
                                Text("Add All (\(tracks.count) songs)")
                            } icon: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                    }

                    // Tracks
                    Section {
                        ForEach(tracks) { item in
                            SelectableTrackRow(
                                track: item.track,
                                isSelected: viewModel.isSelected(item)
                            ) {
                                viewModel.toggleTrackSelection(item)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color(.systemGroupedBackground))
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .listSectionSpacing(16)
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let userId = authManager.currentUserId {
                tracks = await viewModel.loadPlaylistTracks(userId: userId, playlistId: playlist.id)
            }
            isLoading = false
        }
    }
}

// MARK: - Selectable Track Row

private struct SelectableTrackRow: View {
    let track: Track
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                CachedAsyncImagePhase(url: URL(string: track.artwork)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color(.tertiarySystemFill)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PlaylistTrackPickerView(viewModel: CreatePlaylistViewModel())
        .environment(AuthManager.shared)
}
