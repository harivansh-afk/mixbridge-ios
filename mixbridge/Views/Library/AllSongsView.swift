import SwiftUI

struct AllSongsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
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
                            TrackRow(track, number: index + 1, showCover: true)
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
            print("📡 [AllSongs] Fetching liked tracks for userId: \(userId)")
            let cached = try await ConvexService.shared.getLikedTracks(userId: userId)

            if let cached = cached {
                self.tracks = cached.tracks.map { soundcloudTrack in
                    let artworkUrl = soundcloudTrack.artwork_url ?? soundcloudTrack.user.avatar_url ?? ""
                    let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

                    return Track(
                        title: soundcloudTrack.title,
                        artist: soundcloudTrack.user.username,
                        album: soundcloudTrack.genre ?? "",
                        artwork: highQualityArtwork,
                        duration: Double(soundcloudTrack.duration)
                    )
                }
                print("✅ [AllSongs] Loaded \(tracks.count) songs!")
            }
        } catch {
            print("❌ [AllSongs] Error: \(error)")
        }

        hasLoaded = true
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        AllSongsView()
            .environment(AuthManager.shared)
    }
}
