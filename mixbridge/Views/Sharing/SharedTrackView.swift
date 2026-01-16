//
//  SharedTrackView.swift
//  mixbridge
//
//  Displays a shared track from a deep link
//

import SwiftUI

struct SharedTrackView: View {
    let shareId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(PlayerState.self) private var playerState
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(FeatureFlags.self) private var featureFlags

    @State private var trackData: SharedTrackResponse?
    @State private var trackItem: TrackItem?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isAddingToLibrary = false
    @State private var showAddedConfirmation = false
    @State private var isLiked = false

    private let artworkSize: CGFloat = 300

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                if let artwork = (trackItem?.track.artwork ?? trackData?.trackData?.artwork_url?.upgradeArtworkQuality()),
                   !artwork.isEmpty {
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
                        dismissSharedContent()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if featureFlags.downloadsEnabled {
                            Button {
                                downloadTrack()
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                            .disabled(trackItem?.soundCloudTrack == nil || !authManager.isAuthenticated)
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
            await loadTrack()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading track...")
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
        } else if let trackData {
            trackContent(trackData)
        }
    }

    @ViewBuilder
    private func trackContent(_ response: SharedTrackResponse) -> some View {
        let track = response.trackData

        List {
            Section {
                VStack(spacing: 20) {
                    // Artwork
                    ArtworkView(
                        artwork: trackItem?.track.artwork ?? track?.artwork_url?.upgradeArtworkQuality() ?? "",
                        size: artworkSize,
                        cornerRadius: 20,
                        placeholderIcon: "music.note",
                        placeholderIconSize: 80,
                        showsProgressWhileLoading: true,
                        shadow: (color: .black.opacity(0.3), radius: 20, y: 10)
                    )
                    .padding(.top, 20)

                    // Track info
                    VStack(spacing: 8) {
                        MarqueeGlassText(
                            text: trackItem?.track.title ?? track?.title ?? "Unknown Track",
                            font: .systemFont(ofSize: 28, weight: .bold),
                            startDelay: 3.0,
                            loopsBeforePause: 2,
                            isPlaying: true
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)

                        Text(trackItem?.track.artist ?? track?.user?.username ?? "Unknown Artist")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        if let duration = track?.duration {
                            Text(formatDuration(duration))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        // Shared by
                        if let sharer = response.sharer, let username = sharer.username {
                            HStack(spacing: 6) {
                                Text("Shared by")
                                    .foregroundStyle(.secondary)
                                if let avatarUrl = sharer.avatarUrl?.upgradeArtworkQuality() {
                                    AsyncImage(url: URL(string: avatarUrl)) { image in
                                        image.resizable()
                                    } placeholder: {
                                        Circle().fill(.secondary.opacity(0.3))
                                    }
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())
                                }
                                Text("@\(username)")
                                    .foregroundStyle(.primary)
                            }
                            .font(.caption)
                            .padding(.top, 6)
                        }
                    }

                    actionButtons
                        .padding(.horizontal)
                        .padding(.bottom, 12)

                    if !authManager.isAuthenticated {
                        Text("Sign in to play or save this track")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func loadTrack() async {
        do {
            let response = try await ConvexService.shared.getSharedTrack(shareId: shareId)
            if let response {
                let soundCloudTrack = response.trackData?.toSoundCloudTrack()
                await MainActor.run {
                    trackData = response
                    trackItem = soundCloudTrack.map { TrackItem(soundCloudTrack: $0) }
                }
                if let soundCloudTrack, authManager.isAuthenticated {
                    let liked = await LikedSync.shared.isTrackLiked(trackId: String(soundCloudTrack.id))
                    await MainActor.run {
                        isLiked = liked
                    }
                }
            } else {
                await MainActor.run {
                    error = "This track is no longer available"
                }
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to load track"
            }
            logError(.network, "Failed to load shared track: \(error)")
        }
        await MainActor.run {
            isLoading = false
        }
    }

    private func playTrack() {
        guard let soundCloudTrack = trackItem?.soundCloudTrack else { return }

        HapticManager.medium()
        let item = TrackItem(soundCloudTrack: soundCloudTrack)
        playerState.playFromList(items: [item], startIndex: 0)
    }

    private func formatDuration(_ ms: Int) -> String {
        let seconds = ms / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: {
                playTrack()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .imageScale(.small)
                    Text("Play")
                }
                .font(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.primary)
                .glassEffect(.clear, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(!authManager.isAuthenticated)

            Button(action: {
                addToLibrary()
            }) {
                HStack(spacing: 6) {
                    if isAddingToLibrary {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Image(systemName: showAddedConfirmation || isLiked ? "checkmark" : "plus")
                            .imageScale(.small)
                    }
                    Text(showAddedConfirmation || isLiked ? "Added" : "Add to Library")
                }
                .font(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.primary)
                .glassEffect(.clear, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(isAddingToLibrary || isLiked || !authManager.isAuthenticated || trackItem?.soundCloudTrack == nil)
        }
    }

    private func addToLibrary() {
        guard authManager.isAuthenticated, let soundCloudTrack = trackItem?.soundCloudTrack else { return }
        guard !isAddingToLibrary, !isLiked else { return }

        isAddingToLibrary = true
        HapticManager.medium()

        Task {
            do {
                try await LikedSync.shared.likeTrack(soundCloudTrack)
                await MainActor.run {
                    isAddingToLibrary = false
                    isLiked = true
                    showAddedConfirmation = true
                    HapticManager.success()
                }

                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    showAddedConfirmation = false
                }
            } catch {
                await MainActor.run {
                    isAddingToLibrary = false
                }
                logError(.sync, "Failed to add shared track to library: \(error)")
            }
        }
    }

    private func downloadTrack() {
        guard let soundCloudTrack = trackItem?.soundCloudTrack else { return }
        HapticManager.medium()
        downloadManager.downloadTrack(soundCloudTrack)
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
    SharedTrackView(shareId: "test123")
        .environment(AuthManager.shared)
        .environment(PlayerState.shared)
        .environment(DeepLinkRouter.shared)
        .environmentObject(DownloadManager.shared)
}
