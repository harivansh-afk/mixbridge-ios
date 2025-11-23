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
    var onTrackAddedToQueue: ((Track, String) -> Void)? // Callback with track + queue track ID
    var trackData: [String: Any]?
    var onPlay: (() -> Void)?
    @State private var playerState = PlayerState.shared

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
        onTrackAddedToQueue: ((Track, String) -> Void)? = nil,
        trackData: [String: Any]? = nil,
        onPlay: (() -> Void)? = nil
    ) {
        self.track = track
        self.number = number
        self.showCover = showCover
        self.isQueueContext = isQueueContext
        self.onAddToQueue = onAddToQueue
        self.onRemoveFromQueue = onRemoveFromQueue
        self.onLike = onLike
        self.onDelete = onDelete
        self.onTrackAddedToQueue = onTrackAddedToQueue
        self.trackData = trackData
        self.onPlay = onPlay
    }

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        let isCurrentTrack = playerState.currentTrack.id == track.id

        HStack(spacing: 12) {
            // Left side: Track number or album artwork
            leadingContent

            // Middle: Track info
            trackInfo

            Spacer()

            // Right side: Actions
            trailingActions
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isCurrentTrack)
        .contentShape(Rectangle())
        .onTapGesture {
            handlePlayTapped()
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
                Button(role: .destructive) {
                    handleDelete()
                } label: {
                    Label("", systemImage: "trash")
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isQueueContext {
                Button {
                    handleAddToQueue()
                } label: {
                    Label("", systemImage: "text.line.last.and.arrowtriangle.forward")
                }
                .tint(Color(red: 117/255, green: 114/255, blue: 255/255))
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
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
        Group {
            if track.artwork.starts(with: "http") {
                // Real URL - use CachedAsyncImage
                CachedAsyncImagePhase(url: URL(string: track.artwork)) { phase in
                    switch phase {
                    case .empty:
                        artworkPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: coverSize, height: coverSize)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                            .frame(width: coverSize, height: coverSize)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: coverSize * 0.45))
                                    .foregroundColor(.gray.opacity(0.7))
                            )
                    @unknown default:
                        artworkPlaceholder
                    }
                }
            } else {
                // Gradient placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(width: coverSize, height: coverSize)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: coverSize * 0.45))
                            .foregroundColor(.gray.opacity(0.7))
                    )
            }
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                    .frame(width: coverSize, height: coverSize)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: coverSize * 0.45))
                            .foregroundColor(.gray.opacity(0.7))
                    )

            ProgressView()
                .progressViewStyle(.circular)
        }
        .frame(width: coverSize, height: coverSize)
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
        if isQueueContext {
            Image(systemName: "line.3.horizontal")
                .font(.title2)
                .foregroundStyle(.secondary)
        } else {
            EmptyView()
        }
    }

    // MARK: - Action Handlers

    private func handlePlayTapped() {
        HapticManager.selection()

        if let onPlay {
            onPlay()
            return
        }

        PlayerState.shared.play(track: track, trackData: trackData)
    }

    private func handleAddToQueue() {
        // Use custom callback if provided (for backward compatibility)
        if let onAddToQueue = onAddToQueue {
            onAddToQueue()
            return
        }

        // Standard behavior: use QueueManager
        guard let trackData = trackData else {
            errorMessage = "Unable to add track to queue"
            showError = true
            return
        }

        Task {
            isLoading = true
            do {
                try await QueueManager.shared.addTrack(track, rawData: trackData)

                // Notify parent if callback provided
                if let onTrackAddedToQueue = onTrackAddedToQueue,
                   let queueTrackId = QueueManager.shared.queueTracks.first(where: { $0.id == track.id })?.id {
                    onTrackAddedToQueue(track, queueTrackId)
                }
            } catch ConvexError.alreadyInQueue {
                // Don't show error for duplicates - this is expected
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }

    private func handleLike() {
        if let onLike = onLike {
            HapticManager.medium()
            onLike()
        } else {
            // Default behavior: call API directly
            Task {
                isLoading = true
                do {
                    try await BackgroundExecutor.run {
                        try await ConvexService.shared.likeTrack(trackId: track.id)
                    }
                    HapticManager.success()
                } catch {
                    HapticManager.error()
                    errorMessage = "Failed to like track: \(error.localizedDescription)"
                    showError = true
                }
                isLoading = false
            }
        }
    }

    private func handleDelete() {
        if let onDelete = onDelete {
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
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    List {
        TrackRow(Track.sampleTracks[0], number: 1, showCover: false)
        TrackRow(Track.sampleTracks[1], number: 2, showCover: true)
        TrackRow(Track.sampleTracks[2], number: 3, showCover: true)
    }
    .listStyle(.plain)
    .preferredColorScheme(.dark)
}
