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

    private let db = MixBridgeDB.shared

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(PlayerState.self) private var playerState
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(FeatureFlags.self) private var featureFlags

    @State private var playlist: SharedPlaylistResponse?
    @State private var trackItems: [TrackItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isAddingToLibrary = false
    @State private var showAddedConfirmation = false
    @State private var isInLibrary = false

    private var playlistArtwork: String {
        if let artwork = playlist?.artwork?.upgradeArtworkQuality(), !artwork.isEmpty {
            return artwork
        }
        return trackItems.first?.track.artwork ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                if !playlistArtwork.isEmpty {
                    PlayerBackgroundView(artwork: playlistArtwork)
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
                        dismissSharedContent()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if isInLibrary {
                            Button {} label: {
                                Label("Already in Library", systemImage: "checkmark")
                            }
                            .disabled(true)
                        } else {
                            Button {
                                addToLibrary()
                            } label: {
                                if isAddingToLibrary {
                                    Label("Adding...", systemImage: "ellipsis")
                                } else {
                                    Label(showAddedConfirmation ? "Added" : "Add to Library",
                                          systemImage: showAddedConfirmation ? "checkmark" : "plus")
                                }
                            }
                            .disabled(isAddingToLibrary || showAddedConfirmation || !authManager.isAuthenticated)
                        }

                        if featureFlags.downloadsEnabled {
                            Button {
                                downloadAllTracks()
                            } label: {
                                Label("Download All", systemImage: "arrow.down.circle")
                            }
                            .disabled(trackItems.isEmpty)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
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
                    dismissSharedContent()
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
        let artwork = playlistArtwork

        List {
            // Header section
            Section {
                VStack(spacing: 20) {
                    // Artwork
                    ArtworkView(
                        artwork: artwork,
                        size: 300,
                        cornerRadius: 20,
                        placeholderIcon: "music.note.list",
                        placeholderIconSize: 60,
                        showsProgressWhileLoading: true,
                        shadow: (color: .black.opacity(0.3), radius: 20, y: 10)
                    )
                    .padding(.top, 20)

                    // Info
                    VStack(spacing: 8) {
                        MarqueeGlassText(
                            text: playlist.name,
                            font: .systemFont(ofSize: 28, weight: .bold),
                            startDelay: 3.0,
                            loopsBeforePause: 2,
                            isPlaying: true
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)

                        if let owner = playlist.owner, let username = owner.username {
                            HStack(spacing: 6) {
                                if let avatarUrl = owner.avatarUrl?.upgradeArtworkQuality() {
                                    AsyncImage(url: URL(string: avatarUrl)) { image in
                                        image.resizable()
                                    } placeholder: {
                                        Circle().fill(.secondary.opacity(0.3))
                                    }
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())
                                }
                                Text("@\(username)")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    PlaylistActionButtons(
                        onPlay: {
                            playAll()
                        },
                        onShuffle: {
                            shuffleAll()
                        }
                    )
                    .disabled(trackItems.isEmpty || !authManager.isAuthenticated)
                    .padding(.horizontal)
                    .padding(.bottom, 24)

                    if !authManager.isAuthenticated {
                        Text("Sign in to play or save this playlist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Tracks section
            tracksSection
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
                        owner: scPlaylist.sharer,
                        sourcePlaylistId: scPlaylist.sourcePlaylistId
                    )
                }
            } else {
                playlist = try await ConvexService.shared.getSharedPlaylist(shareId: shareId)
            }

            if let playlist {
                let items = playlist.tracks.compactMap { $0.toSoundCloudTrack() }.map { TrackItem(soundCloudTrack: $0) }
                await MainActor.run {
                    trackItems = items
                }
                await updateLibraryStatus(for: playlist)
            } else {
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
                    tracks: persistedTracks,
                    sourcePlaylistId: fullPlaylist.sourcePlaylistId ?? playlist?.sourcePlaylistId
                )

                await MainActor.run {
                    isAddingToLibrary = false
                    showAddedConfirmation = true
                    isInLibrary = true
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
        guard !trackItems.isEmpty else { return }

        HapticManager.medium()

        playerState.playFromList(items: trackItems, startIndex: 0)
    }
    private func shuffleAll() {
        guard !trackItems.isEmpty else { return }
        HapticManager.medium()
        playerState.playFromList(items: trackItems, startIndex: 0, shuffle: true)
    }

    private var tracksSection: some View {
        Section {
            if trackItems.isEmpty {
                Text("No tracks in this playlist")
                    .foregroundStyle(.secondary)
                    .padding()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(trackItems.enumerated()), id: \.element.id) { index, item in
                    TrackRow(
                        item.track,
                        number: index + 1,
                        showCover: true,
                        soundCloudTrack: item.soundCloudTrack,
                        listContext: trackItems,
                        indexInList: index
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listSectionSeparator(.hidden)
    }

    private func downloadAllTracks() {
        let soundCloudTracks = trackItems.map(\.soundCloudTrack)
        guard !soundCloudTracks.isEmpty else { return }
        HapticManager.medium()
        downloadManager.downloadTracks(soundCloudTracks)
    }

    private func updateLibraryStatus(for playlist: SharedPlaylistResponse) async {
        guard let userId = authManager.currentUserId else { return }

        do {
            let exists = try await db.reader.read { db in
                if let sourceId = playlist.sourcePlaylistId {
                    let request = PersistedPlaylist.filter(
                        sql: "libraryOwnerUserId = ? AND (id = ? OR sourcePlaylistId = ?)",
                        arguments: [userId, sourceId, sourceId]
                    )
                    if try request.fetchCount(db) > 0 {
                        return true
                    }
                }

                var request = PersistedPlaylist
                    .filter(PersistedPlaylist.Columns.libraryOwnerUserId == userId)
                    .filter(PersistedPlaylist.Columns.name == playlist.name)
                    .filter(PersistedPlaylist.Columns.trackCount == playlist.trackCount)

                if isSoundCloudPlaylist {
                    request = request.filter(PersistedPlaylist.Columns.isUserCreated == false)
                    if let owner = playlist.owner?.username {
                        request = request.filter(PersistedPlaylist.Columns.creator == owner)
                    }
                } else {
                    request = request.filter(PersistedPlaylist.Columns.isUserCreated == true)
                    if let description = playlist.description {
                        request = request.filter(PersistedPlaylist.Columns.description == description)
                    } else {
                        request = request.filter(PersistedPlaylist.Columns.description == nil)
                    }
                }

                return try request.fetchCount(db) > 0
            }

            await MainActor.run {
                isInLibrary = exists
            }
        } catch {
            logError(.db, "Failed to check shared playlist library status: \(error)")
        }
    }

    private func dismissSharedContent() {
        if deepLinkRouter.isShowingSharedContent {
            deepLinkRouter.dismissSharedContent()
        } else {
            dismiss()
        }
    }
}

#Preview {
    SharedPlaylistView(shareId: "test123")
        .environment(AuthManager.shared)
        .environment(PlayerState.shared)
        .environment(DeepLinkRouter.shared)
        .environmentObject(DownloadManager.shared)
}
