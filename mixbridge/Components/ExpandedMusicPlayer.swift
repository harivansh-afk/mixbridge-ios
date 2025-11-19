//
//  ExpandedMusicPlayer.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/10/25.
//

import SwiftUI

struct ExpandedMusicPlayer: View {
    @Binding var isPresented: Bool
    let namespace: Namespace.ID

    @Environment(\.colorScheme) var colorScheme
    @State private var playerState = PlayerState.shared

    /// Tracks whether the user is currently dragging the progress slider
    @State private var isDraggingProgress = false

    /// Tracks whether the user is currently dragging the volume slider
    @State private var isDraggingVolume = false

    private var track: Track { playerState.currentTrack }
    private var duration: Double {
        if playerState.duration > 0 {
            return playerState.duration
        }
        return track.duration == 0 ? 210 : track.duration
    }

    var body: some View {
        ZStack {

            GeometryReader { proxy in
                VStack(spacing: 28) {
                    dragHandle
                    albumArtwork
                    trackDetails
                    progressSection
                    transportControls
                    volumeSection
                    secondaryControls
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(32, proxy.safeAreaInsets.bottom))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .navigationTransition(.zoom(sourceID: "MINIPLAYER", in: namespace))
    }


    private var dragHandle: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 64, height: 5)
    }

    private var albumArtwork: some View {
        artworkContent
            .id(track.id)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 320)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(
                color: colorScheme == .dark
                    ? .white.opacity(0.1)
                    : .black.opacity(0.15),
                radius: 8, x: 0, y: -4
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.6 : 0.2), radius: 8, x: 0, y: 4)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: track.id)
    }

    @ViewBuilder
    private var artworkContent: some View {
        if track.artwork.starts(with: "http"), let url = URL(string: track.artwork) {
            CachedAsyncImagePhase(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    artworkPlaceholder
                @unknown default:
                    artworkPlaceholder
                }
            }
        } else if let image = UIImage(named: track.artwork) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.blue, .blue.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var trackDetails: some View {
        VStack(spacing: 6) {
            Text(track.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(track.artist)
                .font(.headline)
                .foregroundStyle(.secondary)

        }
        .frame(maxWidth: .infinity)
        .id(track.id)
        .contentTransition(.interpolate)
        .animation(.easeInOut(duration: 0.25), value: track.id)
    }

    private var progressSection: some View {
        VStack(spacing: 10) {
            CustomSlider(
                value: Binding(
                    get: { playerState.playbackPosition },
                    set: { newValue in playerState.playbackPosition = newValue }
                ),
                bounds: 0...max(duration, 1),
                isDragging: $isDraggingProgress,
                onEditingChanged: { editing in
                    if !editing {
                        // Seek only when drag ends (debounced automatically in PlayerState)
                        playerState.seek(to: playerState.playbackPosition)
                    }
                },
                progressColor: colorScheme == .dark ? .white.opacity(0.85) : .primary,
                trackColor: colorScheme == .dark ? .white.opacity(0.2) : .gray.opacity(0.3)
            )

            HStack {
                Text(formatTime(playerState.playbackPosition))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("-\(formatTime(max(duration - playerState.playbackPosition, 0)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 22)
    }

    private var transportControls: some View {
        HStack(spacing: 60) {
            controlButton("backward.fill")

            Button {
                withAnimation(.spring) {
                    playerState.togglePlayback()
                }
            } label: {
                Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            controlButton("forward.fill")
        }
        .buttonStyle(.plain)
    }

    private func controlButton(_ systemImage: String) -> some View {
        Button {
            if systemImage == "backward.fill" {
                playerState.playPreviousFromQueue()
            } else {
                playerState.playNextFromQueue()
            }
        } label: {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var volumeSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                CustomSlider(
                    value: $playerState.volume,
                    bounds: 0...1,
                    isDragging: $isDraggingVolume,
                    onEditingChanged: { _ in
                        // Volume changes are instant (no debouncing needed for volume)
                    },
                    progressColor: colorScheme == .dark ? .white.opacity(0.85) : .primary,
                    trackColor: colorScheme == .dark ? .white.opacity(0.2) : .gray.opacity(0.3)
                )

                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 14)
    }

    private var secondaryControls: some View {
        HStack(spacing: 70) {
            secondaryIconButton(systemImage: "music.note.list")
            Button {} label: {
                Image(systemName: "airplayaudio")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            secondaryIconButton(systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        .font(.title3)
        .padding(.top, 10)

    }

    private func secondaryIconButton(systemImage: String) -> some View {
        Button {} label: {
            Image(systemName: systemImage)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ value: Double) -> String {
        let totalSeconds = Int(max(0, value))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
