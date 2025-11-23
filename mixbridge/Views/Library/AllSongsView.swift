import SwiftUI

struct AllSongsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager
    @State private var tracks: [Track] = []
    @State private var tracksData: [String: [String: Any]] = [:] // Track ID -> raw data
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("")
            } else if tracks.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Your songs will appear here")
                )
            } else {
                List {
                    Section {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track,
                                number: index + 1,
                                showCover: true,
                                trackData: tracksData[track.id]
                            )
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Songs")
        .onAppear {
            if !hasLoaded {
                Task {
                    await loadSongs()
                }
            }
        }
    }

    private func loadSongs() async {
        guard let userId = authManager.currentUserId else { return }
        guard !isLoading else { return }

        isLoading = true

        do {
            let cached = try await BackgroundExecutor.run {
                try await ConvexService.shared.getLikedTracks(userId: userId)
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
                        duration: Double(soundcloudTrack.duration) / 1000.0 // Convert ms to seconds
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
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        AllSongsView()
            .environment(AuthManager.shared)
            .environment(QueueManager.shared)
    }
}
