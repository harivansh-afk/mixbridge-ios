//
//  PlaylistDetailView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager
    @State private var tracks: [Track] = []
    @State private var tracksData: [String: [String: Any]] = [:] // Track ID -> raw data
    @State private var isLoadingTracks = false
    @State private var hasLoaded = false

    private let artworkSize: CGFloat = 300

    var body: some View {
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
            }

            tracksSection
        }
        .listStyle(.plain)
        .swipeBackGesture()
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if !hasLoaded {
                Task {
                    await loadPlaylistTracks()
                }
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
                Button {
                    // More options
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if playlist.artwork.starts(with: "http") {
                AsyncImage(url: URL(string: playlist.artwork)) { phase in
                    switch phase {
                    case .empty:
                        artworkPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: artworkSize, height: artworkSize)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    case .failure:
                        artworkPlaceholder
                    @unknown default:
                        artworkPlaceholder
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: artworkSize, height: artworkSize)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            }
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ProgressView()
                .progressViewStyle(.circular)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: artworkSize, height: artworkSize)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    private var playlistInfo: some View {
        VStack(spacing: 8) {
            Text(playlist.name)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(playlist.creator)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        PlaylistActionButtons(
            onPlay: {
                // Play action
            },
            onShuffle: {
                // Shuffle action
            }
        )
    }

    private var tracksSection: some View {
        Section {
            if isLoadingTracks {
                HStack {
                    Spacer()
                    ProgressView("")
                    Spacer()
                }
                .padding()
            } else if !tracks.isEmpty {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(
                        track,
                        number: index + 1,
                        showCover: true,
                        trackData: tracksData[track.id]
                    )
                }
            } else if !playlist.tracks.isEmpty {
                // Fallback to playlist.tracks if available (no queue support)
                ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track, number: index + 1, showCover: true)
                }
            } else {
                Text("No tracks in this playlist")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .listSectionSeparator(.visible, edges: .top)
    }

    private func loadPlaylistTracks() async {
        guard let userId = authManager.currentUserId else {
            return
        }
        guard !isLoadingTracks else {
            return
        }

        isLoadingTracks = true

        // Try Convex cache first
        do {
            let cached = try await BackgroundExecutor.run {
                try await ConvexService.shared.getPlaylistTracks(
                    userId: userId,
                    playlistId: playlist.id
                )
            }

            if let cached = cached {
                var tracksList: [Track] = []
                var rawData: [String: [String: Any]] = [:]

                for soundcloudTrack in cached.tracks {
                    let artworkUrl = soundcloudTrack.artwork_url ?? soundcloudTrack.user.avatar_url ?? ""
                    let highQualityArtwork = artworkUrl.upgradeArtworkQuality()
                    let trackId = String(soundcloudTrack.id)

                    let track = Track(
                        id: trackId,
                        title: soundcloudTrack.title,
                        artist: soundcloudTrack.user.username,
                        album: soundcloudTrack.genre ?? "",
                        artwork: highQualityArtwork,
                        duration: Double(soundcloudTrack.duration)
                    )

                    tracksList.append(track)

                    // Store raw data for queue operations
                    if let rawDict = try? JSONSerialization.jsonObject(
                        with: JSONEncoder().encode(soundcloudTrack),
                        options: []
                    ) as? [String: Any] {
                        rawData[trackId] = rawDict
                    }
                }

                self.tracks = tracksList
                self.tracksData = rawData
                hasLoaded = true
                isLoadingTracks = false
                return
            }
        } catch ConvexError.noData {
        } catch {
        }

        // Fallback: Fetch from backend API
        do {
            let response = try await BackgroundExecutor.run {
                try await BackendAPI.shared.getPlaylist(playlistId: playlist.id)
            }

            if let soundcloudTracks = response.playlist.tracks {
                var tracksList: [Track] = []
                var rawData: [String: [String: Any]] = [:]

                for soundcloudTrack in soundcloudTracks {
                    let artworkUrl = soundcloudTrack.artwork_url ?? soundcloudTrack.user.avatar_url ?? ""
                    let highQualityArtwork = artworkUrl.upgradeArtworkQuality()
                    let trackId = String(soundcloudTrack.id)

                    let track = Track(
                        id: trackId,
                        title: soundcloudTrack.title,
                        artist: soundcloudTrack.user.username,
                        album: soundcloudTrack.genre ?? "",
                        artwork: highQualityArtwork,
                        duration: Double(soundcloudTrack.duration)
                    )

                    tracksList.append(track)

                    // Store raw data for queue operations
                    if let rawDict = try? JSONSerialization.jsonObject(
                        with: JSONEncoder().encode(soundcloudTrack),
                        options: []
                    ) as? [String: Any] {
                        rawData[trackId] = rawDict
                    }
                }

                self.tracks = tracksList
                self.tracksData = rawData
            }
        } catch {
        }

        hasLoaded = true
        isLoadingTracks = false
    }
}

#Preview("Light Mode") {
    NavigationStack {
        PlaylistDetailView(playlist: Playlist.samplePlaylists[0])
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        PlaylistDetailView(playlist: Playlist.samplePlaylists[0])
    }
    .preferredColorScheme(.dark)
}
