//
//  AddToPlaylistSheet.swift
//  mixbridge
//
//  Sheet for adding a track to an existing playlist.
//  Supports both user-created playlists and SoundCloud playlists.
//

import SwiftUI
import MixBridgeDB

struct AddToPlaylistSheet: View {
    let track: Track
    let soundCloudTrack: SoundCloudTrack

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showError = false
    @State private var addingToPlaylistId: String?
    @State private var successPlaylistId: String?

    private let db = MixBridgeDB.shared
    private let playlistSync = PlaylistSync.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlists.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "music.note.list",
                        description: Text("Create a playlist first to add songs")
                    )
                } else {
                    playlistList
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .task {
                await loadPlaylists()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error {
                    Text(error.localizedDescription)
                }
            }
        }
    }

    private var playlistList: some View {
        List {
            Section {
                ForEach(playlists) { playlist in
                    Button {
                        Task {
                            await addToPlaylist(playlist)
                        }
                    } label: {
                        PlaylistRowContent(
                            playlist: playlist,
                            isAdding: addingToPlaylistId == playlist.id,
                            isSuccess: successPlaylistId == playlist.id
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color(.systemGroupedBackground))
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .listSectionSpacing(16)
    }

    private func loadPlaylists() async {
        guard let userId = authManager.currentUserId else {
            isLoading = false
            return
        }

        do {
            // Load all playlists the user owns (both user-created and SoundCloud), excluding hidden ones
            let allPlaylists = try await db.reader.read { db in
                try PersistedPlaylist
                    .filter(PersistedPlaylist.Columns.libraryOwnerUserId == userId)
                    .filter(PersistedPlaylist.Columns.isHiddenFromLibrary == false)
                    .order(PersistedPlaylist.Columns.lastUpdated.desc)
                    .fetchAll(db)
            }

            playlists = allPlaylists.map { $0.toPlaylist() }
        } catch {
            logError(.db, "Failed to load playlists: \(error)")
        }

        isLoading = false
    }

    private func addToPlaylist(_ playlist: Playlist) async {
        guard let userId = authManager.currentUserId else { return }

        addingToPlaylistId = playlist.id
        HapticManager.medium()

        do {
            let persistedTrack = PersistedTrack(from: soundCloudTrack)

            if playlist.isUserCreated {
                // User-created playlist: use existing method
                try await playlistSync.addTrackToUserPlaylist(
                    userId: userId,
                    playlistId: playlist.id,
                    track: persistedTrack
                )
            } else {
                // SoundCloud playlist: use new method that stores in playlistUserTracks
                try await playlistSync.addTrackToSoundCloudPlaylist(
                    userId: userId,
                    playlistId: playlist.id,
                    track: persistedTrack,
                    soundCloudTrack: soundCloudTrack
                )
            }

            // Show success state
            addingToPlaylistId = nil
            withAnimation(.smooth(duration: 0.3)) {
                successPlaylistId = playlist.id
            }
            HapticManager.success()

            // Wait for animation then dismiss
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        } catch {
            self.error = error
            showError = true
            HapticManager.error()
            addingToPlaylistId = nil
        }
    }
}

// MARK: - Playlist Row Content

private struct PlaylistRowContent: View {
    let playlist: Playlist
    let isAdding: Bool
    let isSuccess: Bool

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
                        .overlay {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if playlist.isUserCreated {
                        Text("Your Playlist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(playlist.creator)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if isAdding {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: isSuccess ? "checkmark" : "plus.circle")
                    .font(isSuccess ? .system(size: 18, weight: .semibold) : .title2)
                    .foregroundStyle(isSuccess ? .primary : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .contentShape(Rectangle())
    }
}

// Preview requires a valid SoundCloudTrack which is not easily mockable
// Use the actual app to test this view
