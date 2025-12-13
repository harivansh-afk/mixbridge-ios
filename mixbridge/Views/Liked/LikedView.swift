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

    @State private var trackItems: [TrackItem] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var error: Error?
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none

    var body: some View {
        content
            .navigationTitle("Liked")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if !hasLoaded {
                    Task {
                        await loadLikedTracks()
                    }
                }
            }
            .refreshable {
                await loadLikedTracks(forceRefresh: true)
            }
    }

    private func loadLikedTracks(forceRefresh: Bool = false) async {
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

    @ViewBuilder
    private var content: some View {
        if isLoading && !hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            errorView(error)
        } else if trackItems.isEmpty {
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
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        LikedView()
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .preferredColorScheme(.dark)
}
