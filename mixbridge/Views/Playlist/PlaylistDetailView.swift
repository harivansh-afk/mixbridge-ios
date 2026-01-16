//
//  PlaylistDetailView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI
import UIKit

struct PlaylistDetailView: View {
    let playlist: Playlist
    @State private var viewModel: PlaylistDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager
    @Environment(PlayerState.self) private var playerState
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(FeatureFlags.self) private var featureFlags

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none

    // Sharing state
    @State private var shareURL: URL?
    @State private var isGeneratingShareLink = false
    @State private var showCopiedConfirmation = false
    @State private var showShareSheet = false
    @State private var pendingShareSheetPresentation = false

    private let artworkSize: CGFloat = 300

    init(playlist: Playlist) {
        self.playlist = playlist
        self._viewModel = State(initialValue: PlaylistDetailViewModel(
            playlistId: playlist.id,
            isUserCreated: playlist.isUserCreated
        ))
    }

    var body: some View {
        ZStack {
            // Dynamic background from artwork
            PlayerBackgroundView(artwork: playlist.artwork)
                .blur(radius: 60)

            // Subtle overlay for depth
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.12)
                .ignoresSafeArea()

            List {
                Section {
                    VStack(spacing: 20) {
                        artwork
                            .padding(.top, 20)

                        playlistInfo

                        actionButtons
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                tracksSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationAllowDismissalGestures(allowDismissalGesture)
        .navigationBarBackButtonHidden(true)
        // Start database observation and fetch fresh data
        .task(id: authManager.currentUserId) {
            async let observe: Void = viewModel.observeDatabase()
            if !viewModel.hasAttemptedLoad, let userId = authManager.currentUserId {
                await viewModel.refresh(userId: userId)
            }

            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all

            _ = await observe
        }
        .refreshable {
            if let userId = authManager.currentUserId {
                await viewModel.refresh(userId: userId, forceRefresh: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Share option - works for all playlists
                    Button {
                        handleShareTapped()
                    } label: {
                        if isGeneratingShareLink {
                            Label("Generating...", systemImage: "ellipsis")
                        } else {
                            Label("Share Playlist", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isGeneratingShareLink)

                    if shareURL != nil {
                        Button {
                            copyShareLink()
                        } label: {
                            Label(showCopiedConfirmation ? "Link Copied!" : "Copy Link", systemImage: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
                        }
                    }


                    if featureFlags.downloadsEnabled {
                        Button {
                            downloadAllTracks()
                        } label: {
                            Label("Download All", systemImage: "arrow.down.circle")
                        }
                        .disabled(viewModel.trackItems.isEmpty)
                    }

                    if playlist.isUserCreated {

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
        }
        .alert("Delete Playlist?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deletePlaylist()
            }
        } message: {
            Text("Are you sure you want to delete \"\(playlist.name)\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
    }
    
    @State private var showDeleteConfirmation = false
    
    private func deletePlaylist() {
        guard let userId = authManager.currentUserId else { return }
        HapticManager.medium()
        
        Task {
            do {
                try await PlaylistSync.shared.deleteUserPlaylist(userId: userId, playlistId: playlist.id)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                logError(.sync, "Failed to delete playlist: \(error)")
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        ArtworkView(
            artwork: playlist.artwork,
            size: artworkSize,
            cornerRadius: 20,
            placeholderIcon: "playlist",
            placeholderIconSize: 60,
            showsProgressWhileLoading: true,
            shadow: (color: .black.opacity(0.3), radius: 20, y: 10)
        )
    }

    private var playlistInfo: some View {
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

            Text(playlist.creator)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        PlaylistActionButtons(
            onPlay: {
                guard !viewModel.trackItems.isEmpty else { return }
                playerState.playFromList(items: viewModel.trackItems, startIndex: 0)
            },
            onShuffle: {
                guard !viewModel.trackItems.isEmpty else { return }
                playerState.playFromList(items: viewModel.trackItems, startIndex: 0, shuffle: true)
            }
        )
    }

    private var tracksSection: some View {
        Section {
            if viewModel.isLoading && viewModel.trackItems.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }
                .padding()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if let error = viewModel.error, viewModel.trackItems.isEmpty {
                VStack(spacing: 12) {
                    Text("Unable to load tracks")
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task {
                            if let userId = authManager.currentUserId {
                                await viewModel.refresh(userId: userId, forceRefresh: true)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .listRowBackground(Color.clear)
            } else if !viewModel.trackItems.isEmpty {
                ForEach(viewModel.trackRows) { row in
                    TrackRow(
                        row.item.track,
                        number: row.index + 1,
                        showCover: true,
                        soundCloudTrack: row.item.soundCloudTrack,
                        listContext: viewModel.trackItems,
                        indexInList: row.index
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else if !playlist.tracks.isEmpty {
                ForEach(playlist.tracks.indexedRows()) { row in
                    TrackRow(row.item, number: row.index + 1, showCover: true)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Text("No tracks in this playlist")
                    .foregroundStyle(.secondary)
                    .padding()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listSectionSeparator(.hidden)
    }

    private func downloadAllTracks() {
        let soundCloudTracks = viewModel.trackItems.compactMap { $0.soundCloudTrack }
        guard !soundCloudTracks.isEmpty else { return }
        HapticManager.medium()
        downloadManager.downloadTracks(soundCloudTracks)
    }

    private func generateShareLink() {
        isGeneratingShareLink = true
        HapticManager.light()

        Task {
            do {
                let response: ShareLinkResponse
                if playlist.isUserCreated {
                    response = try await ConvexService.shared.createShareLink(playlistId: playlist.id)
                } else {
                    // SoundCloud playlist - use the different endpoint
                    response = try await ConvexService.shared.shareSoundCloudPlaylist(playlistId: playlist.id)
                }

                await MainActor.run {
                    shareURL = URL(string: response.shareUrl)
                    isGeneratingShareLink = false
                    HapticManager.success()
                    if pendingShareSheetPresentation {
                        pendingShareSheetPresentation = false
                        showShareSheet = true
                    }
                }
            } catch {
                await MainActor.run {
                    isGeneratingShareLink = false
                    pendingShareSheetPresentation = false
                }
                logError(.network, "Failed to generate share link: \(error)")
            }
        }
    }

    private func handleShareTapped() {
        if shareURL != nil {
            showShareSheet = true
            return
        }

        pendingShareSheetPresentation = true
        generateShareLink()
    }

    private func copyShareLink() {
        guard let shareURL else { return }
        UIPasteboard.general.url = shareURL
        HapticManager.medium()

        showCopiedConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                showCopiedConfirmation = false
            }
        }
    }
}

#Preview("Light Mode") {
    NavigationStack {
        PlaylistDetailView(playlist: Playlist(
            name: "Sample Playlist",
            creator: "Artist",
            artwork: ""
        ))
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .environment(PlayerState.shared)
    .environmentObject(DownloadManager.shared)
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        PlaylistDetailView(playlist: Playlist(
            name: "Sample Playlist",
            creator: "Artist",
            artwork: ""
        ))
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .environment(PlayerState.shared)
    .environmentObject(DownloadManager.shared)
    .preferredColorScheme(.dark)
}
