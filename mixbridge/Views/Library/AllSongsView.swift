import SwiftUI

struct AllSongsView: View {
    @State private var viewModel = LikedViewModel()
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private let revealThreshold: CGFloat = 90

    private var filteredTracks: [TrackItem] {
        guard !searchText.isEmpty else { return viewModel.likedTracks }
        return viewModel.likedTracks.filter {
            $0.track.title.localizedCaseInsensitiveContains(searchText) ||
            $0.track.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.likedTracks.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.likedTracks.isEmpty {
                errorView(error)
            } else if viewModel.likedTracks.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Your songs will appear here")
                )
            } else {
                ScrollView {
                    if filteredTracks.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(minHeight: 300)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, item in
                                TrackRow(
                                    item.track,
                                    number: index + 1,
                                    showCover: true,
                                    soundCloudTrack: item.soundCloudTrack,
                                    listContext: filteredTracks,
                                    indexInList: index
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)

                                if index < filteredTracks.count - 1 {
                                    Divider()
                                        .padding(.leading, 76)
                                }
                            }
                        }
                    }
                }
                .onScrollPhaseChange { oldPhase, newPhase, context in
                    guard oldPhase == .interacting, newPhase != .interacting else { return }
                    let geometry = context.geometry
                    let offset = geometry.contentOffset.y + geometry.contentInsets.top

                    if offset < -revealThreshold && !isSearchPresented {
                        isSearchPresented = true
                        HapticManager.light()
                    }
                }
                .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search Songs")
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
