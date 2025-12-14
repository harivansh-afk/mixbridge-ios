//
//  LikedView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LikedView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager
    @Environment(PreloadedDataStore.self) private var dataStore

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none

    var body: some View {
        content
            .navigationTitle("Liked")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadLikedTracks(forceRefresh: true)
            }
    }

    private func loadLikedTracks(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }
        await AppDataPreloader.shared.refreshIfStale(userId: userId, dataType: .likedTracks)
    }

    @ViewBuilder
    private var content: some View {
        if dataStore.likedTracksState == .loading && dataStore.likedTracks.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .failed(let error) = dataStore.likedTracksState, dataStore.likedTracks.isEmpty {
            errorView(error)
        } else if dataStore.likedTracks.isEmpty {
            emptyState
        } else {
            likedList
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
                    await loadLikedTracks()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Liked Songs",
            systemImage: "heart",
            description: Text("Your liked songs will appear here")
        )
    }

    private var likedList: some View {
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
        .listSectionSpacing(0)
        .navigationAllowDismissalGestures(allowDismissalGesture)
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
    }
}

#Preview("Light Mode") {
    NavigationStack {
        LikedView()
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .environment(PreloadedDataStore.shared)
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        LikedView()
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .environment(PreloadedDataStore.shared)
    .preferredColorScheme(.dark)
}
