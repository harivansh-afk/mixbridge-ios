//
//  ExpandedMusicPlayer.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/10/25.
//

import SwiftUI

struct ExpandedMusicPlayer: View {
    @Binding var isPresented: Bool
    let track: Track
    let namespace: Namespace.ID

    @State private var playbackPosition: Double = 42
    @State private var isPlaying = true
    @State private var volume: Double = 0.6

    private var duration: Double { track.duration == 0 ? 210 : track.duration }

    var body: some View {
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
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
        .navigationTransition(.zoom(sourceID: "MINIPLAYER", in: namespace))
    }

    private var dragHandle: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 64, height: 5)
    }

    private var albumArtwork: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(height: 320)
            .overlay {
                artworkContent
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
    }

    @ViewBuilder
    private var artworkContent: some View {
        if track.artwork.starts(with: "http"), let url = URL(string: track.artwork) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    artworkPlaceholder
                @unknown default:
                    artworkPlaceholder
                }
            }
        } else if let image = UIImage(named: track.artwork) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if !track.artwork.isEmpty {
            ZStack {
                Color.brandAccent.opacity(0.2)
                Image(systemName: track.artwork)
                    .resizable()
                    .scaledToFit()
                    .padding(60)
                    .foregroundStyle(.primary)
            }
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.albumGradient())
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)
            }
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
    }

    private var progressSection: some View {
        VStack(spacing: 10) {
            Slider(value: $playbackPosition, in: 0...duration)
                .tint(.primary)

            HStack {
                Text(formatTime(playbackPosition))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("-\(formatTime(duration - playbackPosition))")
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
                    isPlaying.toggle()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            controlButton("forward.fill")
        }
        .buttonStyle(.plain)
    }

    private func controlButton(_ systemImage: String) -> some View {
        Button {} label: {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var volumeSection: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: $volume, in: 0...1)
                    .tint(.primary)
                Image(systemName: "speaker.wave.3.fill")
            }
            .foregroundStyle(.primary)
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
