//
//  PlayerComponents.swift
//  mixbridge
//
//  Created by AI Assistant on 11/19/25.
//

import SwiftUI

// MARK: - Modular Player Components
// These components are designed to be "dumb" UI elements.
// They don't know about PlayerState or AVPlayer.
// They only know about the data passed to them.
// This makes them:
// 1. Easier to preview (no complex dependencies)
// 2. Easier to test
// 3. Reusable across different views (MiniPlayer vs ExpandedPlayer)

// MARK: - 1. Player Artwork
/// A unified artwork view that handles loading, caching, and transitions.
/// Centralizing this ensures consistent shadowing, corner radius, and placeholder behavior app-wide.
struct PlayerArtworkView: View {
    let artwork: String
    var namespace: Namespace.ID?
    var id: String?
    var size: CGFloat? // Optional fixed size
    var cornerRadius: CGFloat = 24
    var shadowRadius: CGFloat = 8
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Group {
            if artwork.starts(with: "http"), let url = URL(string: artwork) {
                CachedAsyncImagePhase(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else if let image = UIImage(named: artwork) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(
            color: colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.15),
            radius: shadowRadius, x: 0, y: -shadowRadius/2
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.6 : 0.2),
            radius: shadowRadius, x: 0, y: shadowRadius/2
        )
        .if(namespace != nil && id != nil) { view in
            view.matchedGeometryEffect(id: id!, in: namespace!)
        }
    }
    
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.gray.opacity(0.3))
            
            Image(systemName: "music.note")
                .font(.system(size: (size ?? 50) * 0.5))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 2. Dynamic Background
/// Creates an immersive background by blurring the current track's artwork.
/// This elevates the design from a flat sheet to a modern media experience.
struct PlayerBackgroundView: View {
    let artwork: String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if artwork.starts(with: "http"), let url = URL(string: artwork) {
                    CachedAsyncImagePhase(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .blur(radius: 60)
                                .opacity(0.8)
                        } else {
                            // Blue gradient fallback while loading
                            LinearGradient(
                                colors: [.blue.opacity(0.8), .indigo.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                } else if let image = UIImage(named: artwork) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 60)
                        .opacity(0.8)
                } else {
                    // Blue gradient fallback for no artwork
                    LinearGradient(
                        colors: [.blue.opacity(0.8), .indigo.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 3. Player Info
/// Displays the track title and artist.
struct PlayerInfoView: View {
    let title: String
    let artist: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
            
            Text(artist)
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - 4. Player Progress
/// Wraps the CustomSlider and time labels.
/// Keeps the time formatting logic isolated from the main view.
struct PlayerProgressView: View {
    @Binding var value: Double
    let duration: Double
    @Binding var isDragging: Bool
    let onEditingChanged: (Bool) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(formatTime(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(formatTime(max(duration - value, 0)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            CustomSlider(
                value: $value,
                bounds: 0...max(duration, 1),
                isDragging: $isDragging,
                onEditingChanged: onEditingChanged,
                progressColor: colorScheme == .dark ? .white.opacity(0.85) : .primary,
                trackColor: colorScheme == .dark ? .white.opacity(0.2) : .gray.opacity(0.3),
                verticalAlignment: .top // Align flush to the top
            )
            .clipped()
            .padding(.top, -25)
            
            
        }
    }
    
    private func formatTime(_ value: Double) -> String {
        let totalSeconds = Int(max(0, value))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - 5. Player Controls
/// The main transport controls.
/// Using a ViewBuilder allows us to easily swap the layout or buttons without changing the logic.
struct PlayerControlsView: View {
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    
    var body: some View {
        HStack(spacing: 40) {
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Helper Extension for Conditional Modifiers
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
