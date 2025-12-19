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
    @Environment(PreloadedDataStore.self) private var dataStore

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none

    private let artworkSize: CGFloat = 300

    // Computed properties from dataStore
    private var trackItems: [TrackItem] {
        dataStore.playlistTracks[playlist.id] ?? []
    }

    private var isLoading: Bool {
        dataStore.playlistTracksState[playlist.id] == .loading
    }

    private var loadError: Error? {
        if case .failed(let error) = dataStore.playlistTracksState[playlist.id] {
            return error
        }
        return nil
    }

    private var hasLoaded: Bool {
        dataStore.playlistTracksState[playlist.id]?.isLoaded ?? false
    }

    var body: some View {
        ZStack {
            // Dynamic background from artwork
            PlayerBackgroundView(artwork: playlist.artwork)
                .blur(radius: 60)

            // Subtle overlay for depth
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.12)
                .ignoresSafeArea()

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
                    .listRowBackground(Color.clear)
                }

                tracksSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationAllowDismissalGestures(allowDismissalGesture)
        .navigationBarBackButtonHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
        .onAppear {
            if !hasLoaded {
                Task { await loadPlaylistTracks() }
            }
        }
        .refreshable {
            await loadPlaylistTracks(forceRefresh: true)
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
        }
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if playlist.artwork.starts(with: "http") {
                CachedAsyncImagePhase(url: URL(string: playlist.artwork)) { phase in
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
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemGray5))
            .frame(width: artworkSize, height: artworkSize)
            .overlay {
                Image(systemName: "music.note.list")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }
    }

    private var playlistInfo: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let font = UIFont.systemFont(ofSize: 28, weight: .bold)
                let truncatedName = playlist.name.truncatedToFit(font: font, maxWidth: geo.size.width)
                GlassEffectText(
                    text: truncatedName,
                    font: font
                )
                .frame(maxWidth: .infinity)
            }
            .frame(height: 34)

            Text(playlist.creator)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        PlaylistActionButtons(
            onPlay: {
                guard !trackItems.isEmpty else { return }
                Task {
                    await PlayerState.shared.playFromList(items: trackItems, startIndex: 0)
                }
            },
            onShuffle: {
                guard !trackItems.isEmpty else { return }
                Task {
                    await PlayerState.shared.playFromList(items: trackItems, startIndex: 0, shuffle: true)
                }
            }
        )
    }

    private var tracksSection: some View {
        Section {
            if isLoading && trackItems.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if let error = loadError, trackItems.isEmpty {
                VStack(spacing: 12) {
                    Text("Unable to load tracks")
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await loadPlaylistTracks(forceRefresh: true) }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .listRowBackground(Color.clear)
            } else if !trackItems.isEmpty {
                ForEach(Array(trackItems.enumerated()), id: \.element.id) { index, item in
                    TrackRow(
                        item.track,
                        number: index + 1,
                        showCover: true,
                        soundCloudTrack: item.soundCloudTrack,
                        listContext: trackItems,
                        indexInList: index
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else if !playlist.tracks.isEmpty {
                ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track, number: index + 1, showCover: true)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Text("No tracks in this playlist")
                    .foregroundStyle(.secondary)
                    .padding()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listSectionSeparator(.hidden)
    }

    private func loadPlaylistTracks(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }

        if forceRefresh {
            // Force refresh from network - bypasses cache check
            await AppDataPreloader.shared.preloadPlaylistTracks(userId: userId, playlistId: playlist.id, forceRefresh: true)
        } else {
            // Just ensure it's loaded
            await AppDataPreloader.shared.refreshIfStale(userId: userId, dataType: .playlistTracks(playlistId: playlist.id))
        }
    }
}

#Preview("Light Mode") {
    NavigationStack {
        PlaylistDetailView(playlist: Playlist(
            name: "Sample Playlist",
            creator: "Artist",
            artwork: ""
        ))
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .environment(PreloadedDataStore.shared)
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        PlaylistDetailView(playlist: Playlist(
            name: "Sample Playlist",
            creator: "Artist",
            artwork: ""
        ))
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .environment(PreloadedDataStore.shared)
    .preferredColorScheme(.dark)
}
