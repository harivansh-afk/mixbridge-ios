//
//  AddTracksToPlaylistView.swift
//  mixbridge
//
//  Track picker for adding tracks to an existing playlist.
//  Reuses the same UI patterns as CreatePlaylistSheet track picker.
//

import SwiftUI

struct AddTracksToPlaylistView: View {
    @Bindable var viewModel: EditPlaylistViewModel
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var addedCount = 0
    
    private var navigationTitle: String {
        if addedCount == 0 {
            return "Add Tracks"
        } else {
            let songText = addedCount == 1 ? "song" : "songs"
            return "\(addedCount) \(songText) added"
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
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.medium)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
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
                AddTrackSelectionListView(
                    title: "Liked Tracks",
                    tracks: viewModel.likedTracks,
                    viewModel: viewModel,
                    onAdd: { addedCount += 1 }
                )
            } label: {
                Label {
                    Text("Liked Tracks")
                } icon: {
                    Image("heart")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                        .frame(width: 25, height: 25)
                }
            }
            
            NavigationLink {
                AddTrackSelectionListView(
                    title: "Recently Played",
                    tracks: viewModel.recentlyPlayed,
                    viewModel: viewModel,
                    onAdd: { addedCount += 1 }
                )
            } label: {
                Label {
                    Text("Recently Played")
                } icon: {
                    Image("clock")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                        .frame(width: 25, height: 25)
                }
            }
            
            NavigationLink {
                AddPlaylistSelectionListView(
                    playlists: viewModel.libraryPlaylists,
                    viewModel: viewModel,
                    onAdd: { addedCount += 1 }
                )
            } label: {
                Label {
                    Text("Playlists")
                } icon: {
                    Image("playlist")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
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
                let rows = items.indexedRows()
                ForEach(rows) { row in
                    AddableTrackRow(
                        track: row.item.track,
                        isInPlaylist: viewModel.isTrackInPlaylist(row.item.id)
                    ) {
                        viewModel.addTrack(row.item)
                        addedCount += 1
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
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
                    AddableTrackRow(
                        track: item.track,
                        isInPlaylist: viewModel.isTrackInPlaylist(item.id)
                    ) {
                        viewModel.addTrack(item)
                        addedCount += 1
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color(.systemGroupedBackground))
                }
            } header: {
                Text("Search Results")
            }
        }
    }
}

// MARK: - Track Selection List View

private struct AddTrackSelectionListView: View {
    let title: String
    let tracks: [TrackItem]
    @Bindable var viewModel: EditPlaylistViewModel
    let onAdd: () -> Void
    
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
                            AddableTrackRow(
                                track: item.track,
                                isInPlaylist: viewModel.isTrackInPlaylist(item.id)
                            ) {
                                viewModel.addTrack(item)
                                onAdd()
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

// MARK: - Playlist Selection List View

private struct AddPlaylistSelectionListView: View {
    let playlists: [Playlist]
    @Bindable var viewModel: EditPlaylistViewModel
    @Environment(AuthManager.self) private var authManager
    let onAdd: () -> Void
    
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
                                AddPlaylistTracksView(
                                    playlist: playlist,
                                    viewModel: viewModel,
                                    onAdd: onAdd
                                )
                            } label: {
                                AddPlaylistRowView(playlist: playlist)
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

private struct AddPlaylistRowView: View {
    let playlist: Playlist
    
    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImagePhase(url: URL(string: playlist.artwork)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
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

// MARK: - Playlist Tracks View

private struct AddPlaylistTracksView: View {
    let playlist: Playlist
    @Bindable var viewModel: EditPlaylistViewModel
    @Environment(AuthManager.self) private var authManager
    let onAdd: () -> Void
    
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
                            addAllTracks()
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
                            AddableTrackRow(
                                track: item.track,
                                isInPlaylist: viewModel.isTrackInPlaylist(item.id)
                            ) {
                                viewModel.addTrack(item)
                                onAdd()
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
    
    private func addAllTracks() {
        HapticManager.medium()
        for track in tracks where !viewModel.isTrackInPlaylist(track.id) {
            viewModel.addTrack(track)
            onAdd()
        }
    }
}

// MARK: - Addable Track Row

private struct AddableTrackRow: View {
    let track: Track
    let isInPlaylist: Bool
    let onAdd: () -> Void
    
    var body: some View {
        Button(action: {
            if !isInPlaylist {
                onAdd()
            }
        }) {
            HStack(spacing: 12) {
                CachedAsyncImagePhase(url: URL(string: track.artwork)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
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
                
                Image(systemName: isInPlaylist ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isInPlaylist ? .white : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isInPlaylist)
    }
}

#Preview {
    AddTracksToPlaylistView(viewModel: EditPlaylistViewModel(playlist: Playlist(
        id: "test",
        name: "Test",
        creator: "You",
        artwork: "",
        tracks: [],
        lastUpdated: Date(),
        isUserCreated: true
    )))
    .environment(AuthManager.shared)
}
