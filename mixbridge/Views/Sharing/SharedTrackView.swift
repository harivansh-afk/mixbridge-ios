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

    @State private var trackData: SharedTrackResponse?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                if let artwork = trackData?.trackData?.artwork_url {
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
                    deepLinkRouter.dismissSharedContent()
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

        ScrollView {
            VStack(spacing: 24) {
                // Artwork
                ArtworkView(
                    artwork: track?.artwork_url ?? "",
                    size: 260,
                    cornerRadius: 20,
                    placeholderIcon: "music.note",
                    placeholderIconSize: 80,
                    showsProgressWhileLoading: true,
                    shadow: (color: .black.opacity(0.3), radius: 20, y: 10)
                )
                .padding(.top, 40)

                // Track info
                VStack(spacing: 8) {
                    Text(track?.title ?? "Unknown Track")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(track?.user?.username ?? "Unknown Artist")
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
                            if let avatarUrl = sharer.avatarUrl {
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
                        .padding(.top, 8)
                    }
                }

                // Play button
                Button {
                    playTrack()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!authManager.isAuthenticated)
                .padding(.horizontal, 40)

                if !authManager.isAuthenticated {
                    Text("Sign in to play this track")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
    }

    private func loadTrack() async {
        do {
            trackData = try await ConvexService.shared.getSharedTrack(shareId: shareId)
            if trackData == nil {
                error = "This track is no longer available"
            }
        } catch {
            self.error = "Failed to load track"
            logError(.network, "Failed to load shared track: \(error)")
        }
        isLoading = false
    }

    private func playTrack() {
        guard let soundCloudTrack = trackData?.trackData?.toSoundCloudTrack() else { return }

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
}

#Preview {
    SharedTrackView(shareId: "test123")
        .environment(AuthManager.shared)
        .environment(PlayerState.shared)
        .environment(DeepLinkRouter.shared)
}
