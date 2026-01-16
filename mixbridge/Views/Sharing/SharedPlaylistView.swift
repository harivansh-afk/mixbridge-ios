//
//  SharedPlaylistView.swift
//  mixbridge
//
//  Displays a shared playlist from a deep link
//

import SwiftUI
import MixBridgeDB

struct SharedPlaylistView: View {
    let shareId: String
    var isSoundCloudPlaylist: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager
    @Environment(PlayerState.self) private var playerState
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @State private var playlist: SharedPlaylistResponse?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isAddingToLibrary = false
    @State private var showAddedConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                if let artwork = playlist?.artwork {
                    PlayerBackgroundView(artwork: artwork)
                        .blur(radius: 60)
                } else {
                    Color.black.ignoresSafeArea()
                }

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.12)
                    .ignoresSafeArea()

                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        deepLinkRouter.dismissSharedContent()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .task {
            await loadPlaylist()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading playlist...")
        } else if let error {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Dismiss") {
                    deepLinkRouter.dismissSharedContent()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if let playlist {
            playlistContent(playlist)
        }
    }

    @ViewBuilder
    private func playlistContent(_ playlist: SharedPlaylistResponse) -> some View {
        List {
            // Header section
            Section {
                VStack(spacing: 20) {
                    // Artwork
                    ArtworkView(
                        artwork: playlist.artwork ?? "",
                        size: 200,
                        cornerRadius: 16,
                        placeholderIcon: "music.note.list",
                        placeholderIconSize: 60,
                        showsProgressWhileLoading: true,
                        shadow: (color: .black.opacity(0.3), radius: 20, y: 10)
                    )
                    .padding(.top, 20)

                    // Info
                    VStack(spacing: 8) {
                        Text(playlist.name)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        if let owner = playlist.owner, let username = owner.username {
                            HStack(spacing: 6) {
                                if let avatarUrl = owner.avatarUrl {
                                    AsyncImage(url: URL(string: avatarUrl)) { image in
                                        image.resizable()
                                    } placeholder: {
                                        Circle().fill(.secondary.opacity(0.3))
                                    }
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())
                                }
                                Text("@\(username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("\(playlist.trackCount) tracks")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Action buttons
                    HStack(spacing: 16) {
                        Button {
                            addToLibrary()
                        } label: {
                            HStack {
                                if isAddingToLibrary {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: showAddedConfirmation ? "checkmark" : "plus")
                                }
                                Text(showAddedConfirmation ? "Added" : "Add to Library")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAddingToLibrary || !authManager.isAuthenticated)

                        Button {
                            playAll()
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!authManager.isAuthenticated)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)

                    if !authManager.isAuthenticated {
                        Text("Sign in to play or save this playlist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Tracks section
            Section {
                if playlist.tracks.isEmpty {
                    Text("No tracks in this playlist")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { index, track in
                        SharedTrackRow(track: track, number: index + 1)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            } header: {
                Text("Tracks")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func loadPlaylist() async {
        do {
            if isSoundCloudPlaylist {
                // Fetch SoundCloud playlist and adapt to SharedPlaylistResponse format
                if let scPlaylist = try await ConvexService.shared.getSharedSoundCloudPlaylist(shareId: shareId) {
                    playlist = SharedPlaylistResponse(
                        name: scPlaylist.name,
                        description: scPlaylist.description,
                        artwork: scPlaylist.artwork,
                        trackCount: scPlaylist.trackCount,
                        tracks: scPlaylist.tracks,
                        createdAt: scPlaylist.createdAt,
                        owner: scPlaylist.sharer
                    )
                }
            } else {
                playlist = try await ConvexService.shared.getSharedPlaylist(shareId: shareId)
            }

            if playlist == nil {
                error = "This playlist is no longer available"
            }
        } catch {
            self.error = "Failed to load playlist"
            logError(.network, "Failed to load shared playlist: \(error)")
        }
        isLoading = false
    }

    private func addToLibrary() {
        guard authManager.isAuthenticated, let userId = authManager.currentUserId else { return }

        isAddingToLibrary = true
        HapticManager.medium()

        Task {
            do {
                // Get full playlist data
                guard let fullPlaylist = try await ConvexService.shared.getFullSharedPlaylist(shareId: shareId) else {
                    throw ConvexError.notFound
                }

                // Create a copy in user's library
                let persistedTracks = (fullPlaylist.trackData ?? []).map { PersistedTrack(from: $0) }
                _ = try await PlaylistSync.shared.createUserPlaylistWithTracks(
                    userId: userId,
                    name: fullPlaylist.name,
                    description: fullPlaylist.description,
                    tracks: persistedTracks
                )

                await MainActor.run {
                    isAddingToLibrary = false
                    showAddedConfirmation = true
                    HapticManager.success()
                }

                // Reset confirmation after delay
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    showAddedConfirmation = false
                }
            } catch {
                await MainActor.run {
                    isAddingToLibrary = false
                }
                logError(.sync, "Failed to add shared playlist to library: \(error)")
            }
        }
    }

    private func playAll() {
        guard let playlist, !playlist.tracks.isEmpty else { return }

        HapticManager.medium()

        let tracks = playlist.tracks.compactMap { $0.toSoundCloudTrack() }
        guard !tracks.isEmpty else { return }

        let items = tracks.map { TrackItem(soundCloudTrack: $0) }
        playerState.playFromList(items: items, startIndex: 0)
    }
}

// MARK: - Shared Track Row

private struct SharedTrackRow: View {
    let track: SharedPlaylistTrack
    let number: Int

    var body: some View {
        HStack(spacing: 12) {
            // Number
            Text("\(number)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Artwork
            if let artworkUrl = track.artwork_url {
                AsyncImage(url: URL(string: artworkUrl.replacingOccurrences(of: "-large", with: "-t200x200"))) { image in
                    image.resizable()
                } placeholder: {
                    Rectangle().fill(.secondary.opacity(0.2))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title ?? "Unknown Track")
                    .font(.subheadline)
                    .lineLimit(1)

                Text(track.user?.username ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Duration
            if let duration = track.duration {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ ms: Int) -> String {
        let seconds = ms / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

#Preview {
    SharedPlaylistView(shareId: "test123")
        .environment(AuthManager.shared)
        .environment(QueueManager.shared)
        .environment(PlayerState.shared)
        .environment(DeepLinkRouter.shared)
}
