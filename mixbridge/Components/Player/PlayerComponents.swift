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
                .fill(Color(.systemGray6))
            Image(systemName: "music.note")
                .font(.system(size: (size ?? 100) * 0.35))
                .foregroundStyle(.gray.opacity(0.6))
        }
        .frame(width: size, height: size)
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
                            Color.clear
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
                    Color.clear
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
        CustomSlider(
            value: $value,
            bounds: 0...max(duration, 1),
            isDragging: $isDragging,
            onEditingChanged: onEditingChanged,
            progressColor: colorScheme == .dark ? .white.opacity(0.85) : .primary,
            trackColor: colorScheme == .dark ? .white.opacity(0.2) : .gray.opacity(0.3)
        )
        .overlay(alignment: .top) {
            HStack {
                Text(formatTime(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formatTime(max(duration - value, 0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .allowsHitTesting(false)
        }
    }
    
    private func formatTime(_ value: Double) -> String {
        let totalSeconds = Int(max(0, value))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Play/Pause Icon
/// Play/pause icon that keeps the *original* sizing while avoiding layout shifts.
/// The ZStack's size becomes the max of both symbols, so toggling never changes the button bounds.
struct PlayPauseIcon: View {
    let isPlaying: Bool

    var body: some View {
        ZStack {
            Image(systemName: "play.fill")
                .opacity(isPlaying ? 0 : 1)
                .scaleEffect(isPlaying ? 0.94 : 1.0)

            Image(systemName: "pause.fill")
                .opacity(isPlaying ? 1 : 0)
                .scaleEffect(isPlaying ? 1.0 : 0.94)
        }
        .contentShape(Circle())
        .animation(.snappy(duration: 0.12), value: isPlaying)
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
            .buttonStyle(PlayerButtonStyle(hapticStyle: .light, scaleAmount: 0.88, haloSize: 20, haloOpacity: 0.32))

            Button(action: onPlayPause) {
                PlayPauseIcon(isPlaying: isPlaying)
                    .font(.system(size: 50))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(PlayerButtonStyle(hapticStyle: .light, scaleAmount: 0.88, haloSize: 36, haloOpacity: 0.32))

            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(PlayerButtonStyle(hapticStyle: .light, scaleAmount: 0.88, haloSize: 20, haloOpacity: 0.32))
        }
    }
}

// MARK: - Player Button Style
/// Custom button style with haptics and subtle scale animation
struct PlayerButtonStyle: ButtonStyle {
    var hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .light
    var enableHaptic: Bool = true
    var scaleAmount: CGFloat = 0.9
    var pressedOpacity: CGFloat = 1.0
    var pressedBrightness: Double = 0.0
    var haloSize: CGFloat = 40
    var haloOpacity: Double = 0.22

    func makeBody(configuration: Configuration) -> some View {
        PlayerButtonStyleBody(
            configuration: configuration,
            hapticStyle: hapticStyle,
            enableHaptic: enableHaptic,
            scaleAmount: scaleAmount,
            pressedOpacity: pressedOpacity,
            pressedBrightness: pressedBrightness,
            haloSize: haloSize,
            haloOpacity: haloOpacity
        )
    }
}

private struct PlayerButtonStyleBody: View {
    let configuration: ButtonStyle.Configuration
    let hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle
    let enableHaptic: Bool
    let scaleAmount: CGFloat
    let pressedOpacity: CGFloat
    let pressedBrightness: Double
    let haloSize: CGFloat
    let haloOpacity: Double

    @State private var pressed: Bool = false

    private var pressIn: Animation { .easeOut(duration: 0.07) }
    private var pressOut: Animation { .snappy(duration: 0.16, extraBounce: 0.16) }

    var body: some View {
        configuration.label
            .background {
                ZStack {
                    // Subtle grey touch halo - smaller and more muted.
                    Circle()
                        .fill(Color.gray.opacity(0.35))
                        .opacity(pressed ? haloOpacity : 0.0)
                        .scaleEffect(pressed ? 1.0 : 0.85)
                        .blur(radius: pressed ? 0 : 6)
                }
                .frame(width: haloSize, height: haloSize)
                .animation(pressed ? pressIn : pressOut, value: pressed)
            }
            .scaleEffect(pressed ? scaleAmount : 1.0)
            .opacity(pressed ? pressedOpacity : 1.0)
            .brightness(pressed ? pressedBrightness : 0)
            .animation(pressed ? pressIn : pressOut, value: pressed)
            .onAppear { pressed = configuration.isPressed }
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed != pressed {
                    withAnimation(isPressed ? pressIn : pressOut) {
                        pressed = isPressed
                    }
                }

                if isPressed && enableHaptic {
                    switch hapticStyle {
                    case .light: HapticManager.light()
                    case .medium: HapticManager.medium()
                    case .heavy: HapticManager.heavy()
                    @unknown default: HapticManager.light()
                    }
                }
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
