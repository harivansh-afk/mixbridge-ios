//
//  TrackRow.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//  Inspired by Cider-Remote LibraryTrackRow
//

import SwiftUI

struct TrackRow: View {
    let track: Track
    let number: Int
    let showCover: Bool
    var isQueueContext: Bool = false
    var onAddToQueue: (() -> Void)?
    var onRemoveFromQueue: (() -> Void)?
    var onLike: (() -> Void)?
    var onDelete: (() -> Void)?
    var soundCloudTrack: SoundCloudTrack?
    var onPlay: (() -> Void)?

    /// List context for smart queue management
    var listContext: [TrackItem]?
    var indexInList: Int?

    @Environment(PlayerState.self) private var playerState

    private let coverSize: CGFloat = 44

    init(
        _ track: Track,
        number: Int,
        showCover: Bool = false,
        isQueueContext: Bool = false,
        onAddToQueue: (() -> Void)? = nil,
        onRemoveFromQueue: (() -> Void)? = nil,
        onLike: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        soundCloudTrack: SoundCloudTrack? = nil,
        onPlay: (() -> Void)? = nil,
        listContext: [TrackItem]? = nil,
        indexInList: Int? = nil
    ) {
        self.track = track
        self.number = number
        self.showCover = showCover
        self.isQueueContext = isQueueContext
        self.onAddToQueue = onAddToQueue
        self.onRemoveFromQueue = onRemoveFromQueue
        self.onLike = onLike
        self.onDelete = onDelete
        self.soundCloudTrack = soundCloudTrack
        self.onPlay = onPlay
        self.listContext = listContext
        self.indexInList = indexInList
    }

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isLiked = false
    @EnvironmentObject private var downloadManager: DownloadManager

    private var downloadStatus: DownloadStatus {
        downloadManager.downloadStatuses[track.id] ?? .notDownloaded
    }

    var body: some View {
        let isCurrentTrack = playerState.currentTrack.id == track.id

        HStack(spacing: 12) {
            leadingContent
            trackInfo
            Spacer()
            trailingActions
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isCurrentTrack)
        .contentShape(Rectangle())
        .prefetchStream(for: track.id)
        .onTapGesture {
            handlePlayTapped()
        }
        .task {
            isLiked = await LikedSync.shared.isTrackLiked(trackId: track.id)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isQueueContext {
                Button {
                    handleAddToQueue()
                } label: {
                    Label("", systemImage: "text.line.last.and.arrowtriangle.forward")
                }
                .tint(.orange)

                Button {
                    handlePlayNext()
                } label: {
                    Label("", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .tint(Color(red: 117/255, green: 114/255, blue: 255/255))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isQueueContext {
                Button {
                    onRemoveFromQueue?()
                } label: {
                    Label("", systemImage: "minus")
                }
                .tint(.red)
            } else {
                Button {
                    isLiked ? handleUnlike() : handleLike()
                } label: {
                    Label("", systemImage: isLiked ? "heart.slash" : "heart")
                }
                .tint(.pink)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .contextMenu {
            if !isQueueContext {
                downloadContextMenuItems
                Divider()
                queueContextMenuItems
            }
        }
    }

    @ViewBuilder
    private var downloadContextMenuItems: some View {
        switch downloadStatus {
        case .notDownloaded, .failed:
            Button {
                handleDownload()
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        case .downloading:
            Button {
                downloadManager.cancelDownload(trackId: track.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        case .downloaded:
            Button {
                Task {
                    await downloadManager.deleteDownload(trackId: track.id)
                }
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        }

    }

    @ViewBuilder
    private var queueContextMenuItems: some View {
        Button {
            isLiked ? handleUnlike() : handleLike()
        } label: {
            Label(isLiked ? "Unlike" : "Like", systemImage: isLiked ? "heart.slash" : "heart")
        }

        Button {
            handleAddToQueue()
        } label: {
            Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
        }

        if QueueManager.shared.hasQueue {
            Button {
                handlePlayNext()
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if showCover {
            albumArtwork
        } else {
            trackNumber
        }
    }

    private var trackNumber: some View {
        Text(number, format: .number)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(width: 30)
    }

    private var albumArtwork: some View {
        ArtworkView(
            artwork: track.artwork,
            size: coverSize,
            cornerRadius: 12,
            placeholderIcon: "music-note-simple",
            showsProgressWhileLoading: true
        )
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(track.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailingActions: some View {
        HStack(spacing: 8) {
            if downloadStatus == .downloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if isQueueContext {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Action Handlers

    private func handlePlayTapped() {
        HapticManager.selection()

        if let onPlay {
            onPlay()
            return
        }

        // If list context is provided, use smart queue management
        if let context = listContext, let index = indexInList {
            playerState.playFromList(items: context, startIndex: index)
            return
        }

        // Fallback: single track play (no queue context)
        playerState.play(track: track, soundCloudTrack: soundCloudTrack)
    }

    private func handleAddToQueue() {
        if let onAddToQueue {
            onAddToQueue()
            return
        }

        guard let soundCloudTrack else {
            errorMessage = "Unable to add track to queue"
            showError = true
            return
        }

        do {
            try QueueManager.shared.addTrackLocalFirst(track, soundCloudTrack: soundCloudTrack)
        } catch ConvexError.alreadyInQueue {
            // Don't show error for duplicates
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func handlePlayNext() {
        guard let soundCloudTrack else {
            errorMessage = "Unable to add track to queue"
            showError = true
            return
        }

        do {
            try QueueManager.shared.insertTrackNextLocalFirst(track, soundCloudTrack: soundCloudTrack)
        } catch ConvexError.alreadyInQueue {
            // Don't show error for duplicates
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func handleLike() {
        if let onLike {
            HapticManager.medium()
            onLike()
            isLiked = true
        } else {
            Task {
                isLoading = true
                do {
                    if let soundCloudTrack {
                        try await LikedSync.shared.likeTrack(soundCloudTrack)
                    } else {
                        try await ConvexService.shared.likeTrack(trackId: track.id)
                    }
                    isLiked = true
                    HapticManager.success()
                } catch {
                    HapticManager.error()
                    errorMessage = error.localizedDescription
                    showError = true
                }
                isLoading = false
            }
        }
    }

    private func handleUnlike() {
        Task {
            isLoading = true
            do {
                try await LikedSync.shared.unlikeTrack(trackId: track.id)
                isLiked = false
                HapticManager.success()
            } catch {
                HapticManager.error()
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }

    private func handleDownload() {
        guard let soundCloudTrack else {
            errorMessage = "Unable to download track"
            showError = true
            return
        }

        HapticManager.medium()
        downloadManager.downloadTrack(soundCloudTrack)
    }

    private func handleDelete() {
        if let onDelete {
            HapticManager.warning()
            onDelete()
        } else {
            HapticManager.error()
            errorMessage = "Delete action not configured"
            showError = true
        }
    }
}

#Preview("Light Mode") {
    List {
        TrackRow(Track.sampleTracks[0], number: 1, showCover: false)
        TrackRow(Track.sampleTracks[1], number: 2, showCover: true)
        TrackRow(Track.sampleTracks[2], number: 3, showCover: true)
    }
    .listStyle(.plain)
    .environment(PlayerState.shared)
    .environmentObject(DownloadManager.shared)
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    List {
        TrackRow(Track.sampleTracks[0], number: 1, showCover: false)
        TrackRow(Track.sampleTracks[1], number: 2, showCover: true)
        TrackRow(Track.sampleTracks[2], number: 3, showCover: true)
    }
    .listStyle(.plain)
    .environment(PlayerState.shared)
    .environmentObject(DownloadManager.shared)
    .preferredColorScheme(.dark)
}
