import SwiftUI

struct AllSongsView: View {
    @State private var viewModel = LikedViewModel()
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.likedTracks.isEmpty {
                ProgressView()
            } else if let error = viewModel.error, viewModel.likedTracks.isEmpty {
                errorView(error)
            } else if viewModel.likedTracks.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Your songs will appear here")
                )
            } else {
                List {
                    Section {
                        ForEach(Array(viewModel.likedTracks.enumerated()), id: \.element.id) { index, item in
                            TrackRow(
                                item.track,
                                number: index + 1,
                                showCover: true,
                                soundCloudTrack: item.soundCloudTrack,
                                listContext: viewModel.likedTracks,
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
        // Start database observation
        .task {
            await viewModel.observeDatabase()
        }
        // Fetch fresh data
        .task {
            if let userId = authManager.currentUserId {
                await viewModel.refresh(userId: userId)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
        .refreshable {
            if let userId = authManager.currentUserId {
                await viewModel.refresh(userId: userId, forceRefresh: true)
            }
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task {
                    if let userId = authManager.currentUserId {
                        await viewModel.refresh(userId: userId, forceRefresh: true)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    NavigationStack {
        AllSongsView()
            .environment(AuthManager.shared)
            .environment(QueueManager.shared)
    }
}
