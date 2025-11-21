//
//  ExpandedMusicPlayer.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/10/25.
//

import SwiftUI

// MARK: - Smart Container
/// The "Smart" container that connects the PlayerState (Data) to the ExpandedPlayerView (UI).
/// It handles all the logic, bindings, and state management.
struct ExpandedMusicPlayer: View {
    @Binding var isPresented: Bool
    let namespace: Namespace.ID

    @State private var playerState = PlayerState.shared
    @State private var queueManager = QueueManager.shared
    @State private var isDraggingProgress = false
    @State private var isDraggingVolume = false

    // Compute duration safely
    private var duration: Double {
        if playerState.duration > 0 {
            return playerState.duration
        }
        return playerState.currentTrack.duration == 0 ? 210 : playerState.currentTrack.duration
    }

    // Get queue index for any track
    private func getQueueIndex(for track: Track) -> Int? {
        return queueManager.queueTracks.firstIndex(where: { $0.id == track.id })
    }

    // Get current queue index
    private func getCurrentIndex() -> Int? {
        return getQueueIndex(for: playerState.currentTrack)
    }

    // Get next and previous tracks from queue based on PlayerState
    private func getNextTrack() -> Track? {
        guard let currentIndex = getCurrentIndex() else {
            return queueManager.queueTracks.first
        }
        let nextIndex = currentIndex + 1
        return nextIndex < queueManager.queueTracks.count ? queueManager.queueTracks[nextIndex] : nil
    }

    private func getPreviousTrack() -> Track? {
        guard let currentIndex = getCurrentIndex() else {
            return nil
        }
        let prevIndex = currentIndex - 1
        return prevIndex >= 0 ? queueManager.queueTracks[prevIndex] : nil
    }

    // Get next track based on any track (for carousel updates)
    private func getNextTrack(after track: Track) -> Track? {
        guard let currentIndex = getQueueIndex(for: track) else { return nil }
        let nextIndex = currentIndex + 1
        return nextIndex < queueManager.queueTracks.count ? queueManager.queueTracks[nextIndex] : nil
    }

    // Get previous track based on any track (for carousel updates)
    private func getPreviousTrack(before track: Track) -> Track? {
        guard let currentIndex = getQueueIndex(for: track) else { return nil }
        let prevIndex = currentIndex - 1
        return prevIndex >= 0 ? queueManager.queueTracks[prevIndex] : nil
    }

    // Prefetch tracks around current position
    private func prefetchSurroundingTracks() {
        guard let currentIndex = getCurrentIndex() else { return }

        Task {
            await TrackPrefetcher.shared.prefetchForQueue(queueManager.queueTracks, currentIndex: currentIndex)

            // Immediately preload next/previous for instant carousel
            if let next = getNextTrack() {
                await TrackPrefetcher.shared.preloadTrackImmediately(next)
            }
            if let previous = getPreviousTrack() {
                await TrackPrefetcher.shared.preloadTrackImmediately(previous)
            }
        }
    }

    var body: some View {
        ExpandedPlayerView(
            currentTrack: playerState.currentTrack,
            nextTrack: getNextTrack(),
            previousTrack: getPreviousTrack(),
            isPlaying: playerState.isPlaying,
            namespace: namespace,
            playbackPosition: Binding(
                get: { playerState.playbackPosition },
                set: { newValue in playerState.playbackPosition = newValue }
            ),
            duration: duration,
            volume: $playerState.volume,
            isDraggingProgress: $isDraggingProgress,
            isDraggingVolume: $isDraggingVolume,
            onPlayPause: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    playerState.togglePlayback()
                }
            },
            onNext: { playerState.playNextFromQueue() },
            onPrevious: { playerState.playPreviousFromQueue() },
            onSeek: { editing in
                if !editing {
                    // Seek only when drag ends
                    playerState.seek(to: playerState.playbackPosition)
                }
            },
            onDismiss: {
                withAnimation {
                    isPresented = false
                }
            }
        )
        .onAppear {
            // Prefetch surrounding tracks when player opens
            prefetchSurroundingTracks()
        }
        .onChange(of: playerState.currentTrack.id) { _, _ in
            // Prefetch when track changes
            prefetchSurroundingTracks()
        }
    }
}

// MARK: - Dumb UI
/// A pure UI component that knows nothing about the PlayerState singleton.
/// It receives all data via arguments, making it reusable and testable.
struct ExpandedPlayerView: View {
    // Data (from PlayerState)
    let currentTrack: Track
    let nextTrack: Track?
    let previousTrack: Track?
    let isPlaying: Bool
    let namespace: Namespace.ID

    // Queue access for proper track mapping
    @State private var queueManager = QueueManager.shared

    // Bindings
    @Binding var playbackPosition: Double
    let duration: Double
    @Binding var volume: Double
    @Binding var isDraggingProgress: Bool
    @Binding var isDraggingVolume: Bool

    // Actions
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (Bool) -> Void
    let onDismiss: () -> Void

    // MARK: - Carousel State (Direct @State for immediate updates)
    @State private var displayedTrack: Track
    @State private var displayedNext: Track?
    @State private var displayedPrevious: Track?
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingArtwork = false

    // Haptic generators (prepared for instant feedback)
    @State private var lightHaptic = UIImpactFeedbackGenerator(style: .light)
    @State private var mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    @State private var heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var lastHapticThreshold: Int = 0

    init(currentTrack: Track, nextTrack: Track?, previousTrack: Track?, isPlaying: Bool, namespace: Namespace.ID, playbackPosition: Binding<Double>, duration: Double, volume: Binding<Double>, isDraggingProgress: Binding<Bool>, isDraggingVolume: Binding<Bool>, onPlayPause: @escaping () -> Void, onNext: @escaping () -> Void, onPrevious: @escaping () -> Void, onSeek: @escaping (Bool) -> Void, onDismiss: @escaping () -> Void) {
        self.currentTrack = currentTrack
        self.nextTrack = nextTrack
        self.previousTrack = previousTrack
        self.isPlaying = isPlaying
        self.namespace = namespace
        self._playbackPosition = playbackPosition
        self.duration = duration
        self._volume = volume
        self._isDraggingProgress = isDraggingProgress
        self._isDraggingVolume = isDraggingVolume
        self.onPlayPause = onPlayPause
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onSeek = onSeek
        self.onDismiss = onDismiss

        // Initialize display state
        _displayedTrack = State(initialValue: currentTrack)
        _displayedNext = State(initialValue: nextTrack)
        _displayedPrevious = State(initialValue: previousTrack)
    }

    var body: some View {
        GeometryReader { geometry in    
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            // Responsive sizing
            let horizontalPadding = screenWidth * 0.06 // 6% of screen width
            let artworkMaxWidth = screenWidth // 95% of screen width (leaves small margin)
            let cardSpacing: CGFloat = 40 // Spacing between cards in carousel (visible during swipe)
            let cornerRadius = screenWidth * 0.13 // 8% of width for rounded corners
            let contentSpacing = screenHeight * 0.04 // 4% of screen height
            let progressTopSpacing = screenHeight * 0.025 // 2.5% of screen height

            //Main stack below body
            ZStack(alignment: .top) {
                // Multi-layer blended background
                ZStack {
                    // Layer 1: Previous track background (fades in when swiping right)
                    if let prevTrack = displayedPrevious, dragOffset > 0 {
                        PlayerBackgroundView(artwork: prevTrack.artwork)
                            .opacity(calculateBackgroundOpacity(offset: dragOffset, direction: .left, screenWidth: screenWidth))
                            .blur(radius: 80)
                    }

                    // Layer 2: Current track background (always visible)
                    PlayerBackgroundView(artwork: displayedTrack.artwork)
                        .blur(radius: 60)
                        .id(displayedTrack.id)

                    // Layer 3: Next track background (fades in when swiping left)
                    if let nextTrack = displayedNext, dragOffset < 0 {
                        PlayerBackgroundView(artwork: nextTrack.artwork)
                            .opacity(calculateBackgroundOpacity(offset: dragOffset, direction: .right, screenWidth: screenWidth))
                            .blur(radius: 80)
                            .blendMode(.screen) // Additive blending for richer colors
                    }

                    // Layer 4: Subtle overlay for depth
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.12)
                        .ignoresSafeArea()
                }
                .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.75), value: dragOffset)
                .animation(.smooth(duration: 0.7), value: displayedTrack.id)

                VStack(spacing: 0) {
                    // 2. Artwork + Title Carousel (grouped together)
                    ZStack(alignment: .top) {
                        // Previous card (left, off-screen)
                        if let prevTrack = displayedPrevious {
                            TrackCard(
                                track: prevTrack,
                                namespace: nil,
                                artworkWidth: artworkMaxWidth,
                                cornerRadius: cornerRadius
                            )
                            .frame(width: artworkMaxWidth)
                            .offset(x: -(artworkMaxWidth + cardSpacing) + dragOffset)
                            .opacity(calculateOpacity(offset: dragOffset, direction: .left, screenWidth: screenWidth))
                            .scaleEffect(calculateScale(offset: dragOffset, direction: .left, screenWidth: screenWidth))
                            .rotation3DEffect(
                                .degrees(calculate3DRotation(offset: dragOffset, direction: .left, screenWidth: screenWidth)),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.5
                            )
                            .zIndex(0)
                            .id("prev-\(prevTrack.id)")
                        }

                        // Current card (center)
                        TrackCard(
                            track: displayedTrack,
                            namespace: namespace,
                            artworkWidth: artworkMaxWidth,
                            cornerRadius: cornerRadius
                        )
                        .frame(width: artworkMaxWidth)
                        .offset(x: dragOffset)
                        .scaleEffect(isDraggingArtwork ? 0.97 : 1.0)
                        .rotation3DEffect(
                            .degrees(calculate3DRotation(offset: dragOffset, direction: .center, screenWidth: screenWidth)),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.5
                        )
                        .zIndex(1)
                        .id("current-\(displayedTrack.id)")

                        // Next card (right, off-screen)
                        if let nxtTrack = displayedNext {
                            TrackCard(
                                track: nxtTrack,
                                namespace: nil,
                                artworkWidth: artworkMaxWidth,
                                cornerRadius: cornerRadius
                            )
                            .frame(width: artworkMaxWidth)
                            .offset(x: (artworkMaxWidth + cardSpacing) + dragOffset)
                            .opacity(calculateOpacity(offset: dragOffset, direction: .right, screenWidth: screenWidth))
                            .scaleEffect(calculateScale(offset: dragOffset, direction: .right, screenWidth: screenWidth))
                            .rotation3DEffect(
                                .degrees(calculate3DRotation(offset: dragOffset, direction: .right, screenWidth: screenWidth)),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.5
                            )
                            .zIndex(0)
                            .id("next-\(nxtTrack.id)")
                        }
                    }
                    .frame(maxWidth: artworkMaxWidth)
                    .contentShape(Rectangle())
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.78), value: dragOffset)
                    .animation(.interactiveSpring(response: 0.45, dampingFraction: 0.68), value: displayedTrack.id)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                handleDragChanged(value, screenWidth: screenWidth)
                            }
                            .onEnded { value in
                                handleDragEnded(value, screenWidth: screenWidth)
                            }
                    )
                    .onChange(of: currentTrack.id) { oldValue, newValue in
                        // Sync carousel when player changes externally (buttons, auto-advance)
                        if displayedTrack.id != newValue {
                            withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.68)) {
                                displayedTrack = currentTrack
                                displayedNext = nextTrack
                                displayedPrevious = previousTrack
                                dragOffset = 0
                                isDraggingArtwork = false
                            }
                        }
                    }
                    .clipped()
                    .ignoresSafeArea(.all, edges: .top) // Flush to very top
                    .onAppear {
                        // Prepare all haptic generators
                        lightHaptic.prepare()
                        mediumHaptic.prepare()
                        heavyHaptic.prepare()

                        // Initialize carousel with current tracks
                        displayedTrack = currentTrack
                        displayedNext = nextTrack
                        displayedPrevious = previousTrack
                    }

                    // 3. Controls Section
                    VStack(spacing: 0) {
                        PlayerProgressView(
                            value: $playbackPosition,
                            duration: duration,
                            isDragging: $isDraggingProgress,
                            onEditingChanged: onSeek
                        )
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, progressTopSpacing)

                        PlayerControlsView(
                            isPlaying: isPlaying,
                            onPlayPause: onPlayPause,
                            onNext: onNext,
                            onPrevious: onPrevious
                        )
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, contentSpacing)
                    }

                }

            }
        }

        // Setup the hero transition
        .navigationTransition(.zoom(sourceID: "MINIPLAYER", in: namespace))
    }

    // MARK: - Gesture Handlers

    private func handleDragChanged(_ value: DragGesture.Value, screenWidth: CGFloat) {
        // Start drag if not already dragging
        if !isDraggingArtwork {
            isDraggingArtwork = true
            lastHapticThreshold = 0
            lightHaptic.prepare()
            mediumHaptic.prepare()
            heavyHaptic.prepare()
        }

        // Apply boundary resistance for natural feel
        let resistedOffset = applyBoundaryResistance(
            translation: value.translation.width,
            hasNext: displayedNext != nil,
            hasPrevious: displayedPrevious != nil
        )

        // Update drag offset with resistance
        dragOffset = resistedOffset

        // Progressive haptic feedback throughout the drag
        let progress = abs(value.translation.width) / screenWidth
        let currentThreshold = Int(progress * 100 / 10) // 0-10 scale

        if currentThreshold > lastHapticThreshold {
            lastHapticThreshold = currentThreshold

            if progress < 0.15 {
                // Light haptic at start (10-15%)
                lightHaptic.impactOccurred(intensity: 0.3)
            } else if progress < 0.25 {
                // Medium haptic near threshold (15-25%)
                mediumHaptic.impactOccurred(intensity: 0.5)
            } else if progress >= 0.25 && progress < 0.35 {
                // Heavy haptic past threshold (25-35%)
                heavyHaptic.impactOccurred(intensity: 0.8)
            }
        }
    }

    // Apply resistance when dragging past boundaries
    private func applyBoundaryResistance(translation: CGFloat, hasNext: Bool, hasPrevious: Bool) -> CGFloat {
        // Swipe left (next) without next track
        if translation < 0 && !hasNext {
            return translation * 0.3 // Heavy resistance
        }
        // Swipe right (previous) without previous track
        if translation > 0 && !hasPrevious {
            return translation * 0.3 // Heavy resistance
        }
        return translation
    }

    private func handleDragEnded(_ value: DragGesture.Value, screenWidth: CGFloat) {
        let threshold = screenWidth * 0.25
        let velocity = value.predictedEndTranslation.width - value.translation.width

        // Consider both distance AND velocity for natural feel
        let shouldAdvance = abs(value.translation.width) > threshold || abs(velocity) > 500

        if shouldAdvance {
            if value.translation.width > 0 && displayedPrevious != nil {
                // Swipe right → previous
                heavyHaptic.impactOccurred(intensity: 1.0) // Final heavy haptic on commit

                // Smooth spring animation with iOS 18 interactiveSpring
                withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.68, blendDuration: 0.1)) {
                    // Commit changes instantly
                    let newCurrent = displayedPrevious!
                    displayedNext = displayedTrack
                    displayedTrack = newCurrent
                    // Calculate previous based on NEW current track position in queue
                    displayedPrevious = getPreviousTrack(before: newCurrent)
                    dragOffset = 0
                    isDraggingArtwork = false
                }

                // Update player in background
                Task.detached { @MainActor in
                    onPrevious()
                }
            } else if value.translation.width < 0 && displayedNext != nil {
                // Swipe left → next
                heavyHaptic.impactOccurred(intensity: 1.0) // Final heavy haptic on commit

                // Smooth spring animation
                withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.68, blendDuration: 0.1)) {
                    // Commit changes instantly
                    let newCurrent = displayedNext!
                    displayedPrevious = displayedTrack
                    displayedTrack = newCurrent
                    // Calculate next based on NEW current track position in queue
                    displayedNext = getNextTrack(after: newCurrent)
                    dragOffset = 0
                    isDraggingArtwork = false
                }

                // Update player in background
                Task.detached { @MainActor in
                    onNext()
                }
            } else {
                // Invalid direction or no track available - snap back with bounce
                lightHaptic.impactOccurred(intensity: 0.4) // Light haptic for failed swipe
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.62, blendDuration: 0)) {
                    dragOffset = 0
                    isDraggingArtwork = false
                    lastHapticThreshold = 0
                }
            }
        } else {
            // Not enough distance/velocity - snap back with satisfying bounce
            lightHaptic.impactOccurred(intensity: 0.4) // Light haptic for snap-back
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.62, blendDuration: 0)) {
                dragOffset = 0
                isDraggingArtwork = false
                lastHapticThreshold = 0
            }
        }
    }

    // MARK: - Helper Functions

    // Get queue index for any track
    private func getQueueIndex(for track: Track) -> Int? {
        return queueManager.queueTracks.firstIndex(where: { $0.id == track.id })
    }

    // Get next track based on any track (for carousel updates)
    private func getNextTrack(after track: Track) -> Track? {
        guard let currentIndex = getQueueIndex(for: track) else { return nil }
        let nextIndex = currentIndex + 1
        return nextIndex < queueManager.queueTracks.count ? queueManager.queueTracks[nextIndex] : nil
    }

    // Get previous track based on any track (for carousel updates)
    private func getPreviousTrack(before track: Track) -> Track? {
        guard let currentIndex = getQueueIndex(for: track) else { return nil }
        let prevIndex = currentIndex - 1
        return prevIndex >= 0 ? queueManager.queueTracks[prevIndex] : nil
    }

    private enum Direction {
        case left, center, right
    }

    private func calculateOpacity(offset: CGFloat, direction: Direction, screenWidth: CGFloat) -> Double {
        let normalizedOffset = abs(offset) / screenWidth

        switch direction {
        case .left:
            // Fade IN when swiping right (offset > 0)
            return 0.4 + (offset > 0 ? normalizedOffset * 0.6 : 0)
        case .right:
            // Fade IN when swiping left (offset < 0)
            return 0.4 + (offset < 0 ? normalizedOffset * 0.6 : 0)
        case .center:
            return 1.0
        }
    }

    private func calculateScale(offset: CGFloat, direction: Direction, screenWidth: CGFloat) -> CGFloat {
        let normalizedOffset = abs(offset) / screenWidth

        switch direction {
        case .left:
            // Scale up as it comes into view
            return 0.85 + (offset > 0 ? normalizedOffset * 0.15 : 0)
        case .right:
            // Scale up as it comes into view
            return 0.85 - (offset < 0 ? normalizedOffset * 0.15 : -0.15)
        case .center:
            return 1.0
        }
    }

    private func calculate3DRotation(offset: CGFloat, direction: Direction, screenWidth: CGFloat) -> Double {
        let normalizedOffset = offset / screenWidth
        let maxRotation: Double = 15 // degrees

        switch direction {
        case .left:
            // Rotate inward as it slides in from left
            return normalizedOffset > 0 ? -maxRotation * (1 - Double(normalizedOffset)) : -maxRotation
        case .right:
            // Rotate inward as it slides in from right
            return normalizedOffset < 0 ? maxRotation * (1 + Double(normalizedOffset)) : maxRotation
        case .center:
            // Current card rotates based on swipe direction
            return Double(normalizedOffset) * maxRotation
        }
    }

    private func calculateBackgroundOpacity(offset: CGFloat, direction: Direction, screenWidth: CGFloat) -> Double {
        let normalizedProgress = abs(offset) / screenWidth

        switch direction {
        case .left:
            // Fade in when swiping right (offset > 0)
            return offset > 0 ? Double(normalizedProgress * 0.8) : 0
        case .right:
            // Fade in when swiping left (offset < 0)
            return offset < 0 ? Double(normalizedProgress * 0.8) : 0
        case .center:
            return 1.0
        }
    }
}


// MARK: - Track Card Component (Artwork + Title grouped)
struct TrackCard: View {
    let track: Track
    let namespace: Namespace.ID?
    let artworkWidth: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        VStack(spacing: 20) {
            // Artwork (flush to top)
            PlayerArtworkView(
                artwork: track.artwork,
                namespace: namespace,
                id: namespace != nil ? track.id : nil,
                cornerRadius: cornerRadius,
                shadowRadius: 0
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(width: artworkWidth, height: artworkWidth)

            // Song info
            PlayerInfoView(
                title: track.title.count > 20
                    ? String(track.title.prefix(20)) + "…"
                    : track.title,
                artist: track.artist
            )
        } 
    }
}

// MARK: - Preview
#Preview("Expanded Player") {
    @Previewable @Namespace var namespace
    @Previewable @State var position: Double = 45
    @Previewable @State var volume: Double = 1

    ExpandedPlayerView(
        currentTrack: Track.sampleTracks[0],
        nextTrack: Track.sampleTracks[1],
        previousTrack: nil,
        isPlaying: true,
        namespace: namespace,
        playbackPosition: $position,
        duration: 210,
        volume: $volume,
        isDraggingProgress: .constant(false),
        isDraggingVolume: .constant(false),
        onPlayPause: {},
        onNext: {},
        onPrevious: {},
        onSeek: { _ in },
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
