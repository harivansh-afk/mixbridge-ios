import SwiftUI

struct AllSongsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager

    @State private var trackItems: [TrackItem] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var error: Error?
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none

    var body: some View {
        Group {
            if isLoading && !hasLoaded {
                ProgressView()
            } else if let error {
                errorView(error)
            } else if trackItems.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Your songs will appear here")
                )
            } else {
                List {
                    Section {
                        ForEach(Array(trackItems.enumerated()), id: \.element.id) { index, item in
                            TrackRow(
                                item.track,
                                number: index + 1,
                                showCover: true,
                                soundCloudTrack: item.soundCloudTrack,
                                listContext: trackItems,
                                indexInList: index
                            )
                        }
                    }
                }
                .listStyle(.plain)
                .navigationAllowDismissalGestures(allowDismissalGesture)
            }
        }
        .navigationTitle("Songs")
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
        .onAppear {
            if !hasLoaded {
                Task { await loadSongs() }
            }
        }
        .refreshable {
            await loadSongs(forceRefresh: true)
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task { await loadSongs() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadSongs(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let tracks = try await BackgroundExecutor.run {
                try await ConvexService.shared.getLikedTracks(userId: userId, forceRefresh: forceRefresh)
            }
            self.trackItems = tracks.toTrackItems()
        } catch {
            self.error = error
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
