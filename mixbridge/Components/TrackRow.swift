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

    private var playerState = PlayerState.shared

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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isQueueContext {
                Button {
                    onRemoveFromQueue?()
                } label: {
                    Label("", systemImage: "minus")
                }
                .tint(.red)
            } else {
                if QueueManager.shared.hasQueue {
                    Button {
                        handlePlayNext()
                    } label: {
                        Label("", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .tint(Color(red: 117/255, green: 114/255, blue: 255/255))
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isQueueContext {
                Button {
                    handleAddToQueue()
                } label: {
                    Label("", systemImage: "text.line.last.and.arrowtriangle.forward")
                }
                .tint(.orange)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage {
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

        // If list context is provided, use smart queue management
        if let context = listContext, let index = indexInList {
            Task {
                await PlayerState.shared.playFromList(items: context, startIndex: index)
            }
            return
        }

        // Fallback: single track play (no queue context)
        PlayerState.shared.play(track: track, soundCloudTrack: soundCloudTrack)
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

        Task {
            isLoading = true
            do {
                try await QueueManager.shared.addTrack(track, soundCloudTrack: soundCloudTrack)
            } catch ConvexError.alreadyInQueue {
                // Don't show error for duplicates
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }

    private func handlePlayNext() {
        guard let soundCloudTrack else {
            errorMessage = "Unable to add track to queue"
            showError = true
            return
        }

        Task {
            isLoading = true
            do {
                try await QueueManager.shared.insertTrackNext(track, soundCloudTrack: soundCloudTrack)
            } catch ConvexError.alreadyInQueue {
                // Don't show error for duplicates
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }

    private func handleLike() {
        if let onLike {
            HapticManager.medium()
            onLike()
        } else {
            Task {
                isLoading = true
                do {
                    try await BackgroundExecutor.run {
                        try await ConvexService.shared.likeTrack(trackId: track.id)
                    }
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
