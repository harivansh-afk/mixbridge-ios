import SwiftUI

struct AllSongsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager
    @Environment(PreloadedDataStore.self) private var dataStore

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none

    var body: some View {
        Group {
            if dataStore.likedTracksState == .loading && dataStore.likedTracks.isEmpty {
                ProgressView()
            } else if case .failed(let error) = dataStore.likedTracksState, dataStore.likedTracks.isEmpty {
                errorView(error)
            } else if dataStore.likedTracks.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Your songs will appear here")
                )
            } else {
                List {
                    Section {
                        ForEach(Array(dataStore.likedTracks.enumerated()), id: \.element.id) { index, item in
                            TrackRow(
                                item.track,
                                number: index + 1,
                                showCover: true,
                                soundCloudTrack: item.soundCloudTrack,
                                listContext: dataStore.likedTracks,
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
                Task { await loadSongs(forceRefresh: true) }
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadSongs(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }
        await AppDataPreloader.shared.refreshIfStale(userId: userId, dataType: .likedTracks)
    }
}

#Preview {
    NavigationStack {
        AllSongsView()
            .environment(AuthManager.shared)
            .environment(QueueManager.shared)
            .environment(PreloadedDataStore.shared)
    }
}
