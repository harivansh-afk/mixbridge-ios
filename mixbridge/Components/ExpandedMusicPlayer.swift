//
//  ExpandedMusicPlayer.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/10/25.
//

import SwiftUI
import UIKit

// MARK: - Smart Container
/// The "Smart" container that connects the PlayerState (Data) to the ExpandedPlayerView (UI).
/// It handles all the logic, bindings, and state management.
struct ExpandedMusicPlayer: View {
    @Binding var isPresented: Bool
    let namespace: Namespace.ID

    @Bindable private var playerState = PlayerState.shared

    init(isPresented: Binding<Bool>, namespace: Namespace.ID) {
        self._isPresented = isPresented
        self.namespace = namespace
    }
    @Environment(QueueManager.self) private var queueManager
    @Environment(AuthManager.self) private var authManager
    @State private var isDraggingProgress = false
    @State private var isDraggingVolume = false

    /// Local slider value used during dragging to prevent observer conflicts
    @State private var localSliderPosition: Double = 0

    // Compute duration safely
    // Prefer PlayerState duration (from AVPlayer), fall back to Track metadata (from API)
    private var duration: Double {
        if playerState.duration > 0 {
            return playerState.duration
        }
        // Use track's duration directly - it's preloaded from API
        return max(playerState.currentTrack.duration, 0)
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
                get: {
                    // Use local value during dragging, otherwise use actual playback position
                    isDraggingProgress ? localSliderPosition : playerState.playbackPosition
                },
                set: { newValue in
                    // Update local value during dragging
                    localSliderPosition = newValue
                }
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
                if editing {
                    // ⚡ User started dragging - block time observer updates
                    playerState.isSeeking = true
                    localSliderPosition = playerState.playbackPosition
                } else {
                    // ⚡ User stopped dragging - seek immediately
                    // NOTE: PlayerState.seek() will handle clearing isSeeking flag with proper delay
                    // Don't set isSeeking = false here, it causes race condition!
                    playerState.seek(to: localSliderPosition)
                }
            },
            onDismiss: {
                withAnimation {
                    isPresented = false
                }
            }
        )
        .onAppear {
            // Load queue when expanded player opens
            if let userId = authManager.currentUserId {
                Task {
                    try? await queueManager.loadQueue(userId: userId)
                    // Sync player's queue index after queue loads
                    // This ensures navigation works even if track was played from outside the queue
                    playerState.syncQueueIndex()
                }
            }
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
    private var queueManager = QueueManager.shared

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

    // Preview support
    var previewQueueTracks: [Track]? = nil
    var initialShowQueue: Bool = false

    // MARK: - Carousel State (Direct @State for immediate updates)
    @State private var displayedTrack: Track
    @State private var displayedNext: Track?
    @State private var displayedPrevious: Track?
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingArtwork = false
    @State private var showQueueSheet: Bool
    @State private var queueExpansion: CGFloat // How much queue pushes content up
    @State private var queueDragStart: CGFloat = 0 // Starting expansion when drag begins

    // Haptic generators (prepared for instant feedback)
    @State private var lightHaptic = UIImpactFeedbackGenerator(style: .light)
    @State private var mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    @State private var heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var lastHapticThreshold: Int = 0
    @State private var confirmDeleteQueue: Bool = false

    init(currentTrack: Track, nextTrack: Track?, previousTrack: Track?, isPlaying: Bool, namespace: Namespace.ID, playbackPosition: Binding<Double>, duration: Double, volume: Binding<Double>, isDraggingProgress: Binding<Bool>, isDraggingVolume: Binding<Bool>, onPlayPause: @escaping () -> Void, onNext: @escaping () -> Void, onPrevious: @escaping () -> Void, onSeek: @escaping (Bool) -> Void, onDismiss: @escaping () -> Void, previewQueueTracks: [Track]? = nil, initialShowQueue: Bool = false) {
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
        self.previewQueueTracks = previewQueueTracks
        self.initialShowQueue = initialShowQueue

        // Initialize display state
        _displayedTrack = State(initialValue: currentTrack)
        _displayedNext = State(initialValue: nextTrack)
        _displayedPrevious = State(initialValue: previousTrack)
        _showQueueSheet = State(initialValue: true)
        _queueExpansion = State(initialValue: 0) // Queue visible but no displacement
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            // Responsive sizing
            let horizontalPadding = screenWidth * 0.075// 7.5% of screen width
            let artworkMaxWidth = screenWidth // 95% of screen width (leaves small margin)
            let cardSpacing: CGFloat = 60 // Spacing between cards in carousel (visible during swipe)
            let cornerRadius = screenWidth * 0.12 // 8% of width for rounded corners
            let contentSpacing = screenHeight * 0.04 // 4% of screen height
            let progressTopSpacing = screenHeight * -0.05 // 2.5% of screen height

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
                    // Top section (artwork + controls) - moves up when queue expands
                    Group {
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

                        // Current card (center) - No matchedGeometryEffect needed as we use navigationTransition(.zoom)
                        TrackCard(
                            track: displayedTrack,
                            namespace: nil,
                            artworkWidth: artworkMaxWidth,
                            cornerRadius: cornerRadius,
                            isMatchedGeometrySource: false
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
                    // Use custom gesture recognizer to allow vertical swipes (dismissal) to pass through
                    .overlay(
                        HorizontalPanGesture(
                            onChanged: { translation, velocity in
                                handleDragChanged(translation: translation, screenWidth: screenWidth)
                            },
                            onEnded: { translation, velocity in
                                handleDragEnded(translation: translation, velocity: velocity, screenWidth: screenWidth)
                            }
                        )
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
                    .onAppear {
                        // Prepare all haptic generators
                        lightHaptic.prepare()
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
                    // Apply offset to entire top section (artwork + controls) when queue expands
                    .offset(y: showQueueSheet ? -queueExpansion : 0)
                    .ignoresSafeArea(.all, edges: .top) // Flush artwork to top, applied to whole group
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: queueExpansion)

                    // 4. Queue List or Toolbar
                    if showQueueSheet {
                        VStack(spacing: 0) {
                            // Drag handle area - larger hit target
                            VStack(spacing: 8) {
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 60, height: 5)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                            .padding(.bottom, 8)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 5)
                                    .onChanged { value in
                                        // Capture start position on first drag movement
                                        if queueDragStart == 0 {
                                            queueDragStart = queueExpansion
                                        }

                                        // Negative translation = dragging up = expand
                                        let drag = -value.translation.height
                                        let newExpansion = max(0, min(300, queueDragStart + drag))

                                        // Haptic at thresholds
                                        let oldThreshold = Int(queueExpansion / 50)
                                        let newThreshold = Int(newExpansion / 50)
                                        if newThreshold != oldThreshold {
                                            lightHaptic.impactOccurred(intensity: 0.5)
                                        }

                                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.8)) {
                                            queueExpansion = newExpansion
                                        }
                                    }
                                    .onEnded { value in
                                        queueDragStart = 0

                                        // Swipe down to close
                                        if value.translation.height > 100 && queueExpansion < 100 {
                                            mediumHaptic.impactOccurred()
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                showQueueSheet = false
                                                queueExpansion = 0
                                            }
                                        } else {
                                            // Snap to expanded or collapsed based on position
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                queueExpansion = queueExpansion > 100 ? 200 : 0
                                            }
                                        }
                                    }
                            )

                            List {
                                ForEach(Array((previewQueueTracks ?? queueManager.queueTracks).enumerated()), id: \.element.id) { index, track in
                                    TrackRow(
                                        track,
                                        number: index + 1,
                                        showCover: true,
                                        isQueueContext: true,
                                        onRemoveFromQueue: {
                                            removeFromQueue(at: index)
                                        }
                                    )
                                    .listRowSeparator(.hidden)
                                }
                                .onMove(perform: moveQueueItem)
                                .onDelete(perform: deleteQueueItem)
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .contentMargins(.bottom, 60, for: .scrollContent)
                            .mask(
                                VStack(spacing: 0) {
                                    LinearGradient(
                                        colors: [.clear, .white],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 30)
                                    Color.black
                                }
                            )
                        }
                        .frame(height: 280 + queueExpansion)
                        .offset(y: -queueExpansion)
                        .layoutPriority(1)
                        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: queueExpansion)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Spacer()

                        // Clear queue button (left) and Queue button (right)
                        HStack {
                            // Clear queue button (only show if queue has items)
                            if queueManager.hasQueue {
                                Button {
                                    if confirmDeleteQueue {
                                        Task {
                                            try? await queueManager.clearQueueWithSync()
                                        }
                                        withAnimation(.smooth(duration: 0.3)) {
                                            confirmDeleteQueue = false
                                        }
                                    } else {
                                        withAnimation(.smooth(duration: 0.3)) {
                                            confirmDeleteQueue = true
                                        }
                                    }
                                } label: {
                                    Image(systemName: confirmDeleteQueue ? "checkmark" : "trash")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(confirmDeleteQueue ? .white : .red)
                                        .contentTransition(.symbolEffect(.replace))
                                        .frame(width: 44, height: 44)
                                        .background(confirmDeleteQueue ? Color.blue : Color.clear)
                                        .clipShape(Circle())
                                }
                                .glassEffect(.regular, in: .circle)
                            }

                            Spacer()

                            // Queue button
                            Button {
                                confirmDeleteQueue = false // Reset confirmation state
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showQueueSheet = true
                                    queueExpansion = 200 // Start expanded
                                }
                            } label: {
                                Image("queue")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .buttonStyle(GlassToolbarButtonStyle())
                        }
                        .padding(.horizontal, horizontalPadding)
                    }

                }

            }
        }

        // Setup the hero transition
        .navigationTransition(.zoom(sourceID: "MINIPLAYER", in: namespace))
        .onChange(of: showQueueSheet) { _, newValue in
            // Reset delete confirmation when queue sheet state changes
            if newValue {
                confirmDeleteQueue = false
            }
        }
    }

    // MARK: - Gesture Handlers

    private func handleDragChanged(translation: CGFloat, screenWidth: CGFloat) {
        // Start drag if not already dragging
        if !isDraggingArtwork {
            isDraggingArtwork = true
            lastHapticThreshold = 0
            lightHaptic.prepare()
            
            heavyHaptic.prepare()
        }

        // Apply boundary resistance for natural feel
        let resistedOffset = applyBoundaryResistance(
            translation: translation,
            hasNext: displayedNext != nil,
            hasPrevious: displayedPrevious != nil
        )

        // Update drag offset with resistance
        dragOffset = resistedOffset

        // Progressive haptic feedback throughout the drag
        let progress = abs(translation) / screenWidth
        let currentThreshold = Int(progress * 100 / 10) // 0-10 scale

        if currentThreshold > lastHapticThreshold {
            lastHapticThreshold = currentThreshold

            if progress < 0.15 {
                // Light haptic at start (10-15%)
                lightHaptic.impactOccurred(intensity: 0.3)
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

    private func handleDragEnded(translation: CGFloat, velocity: CGFloat, screenWidth: CGFloat) {
        let threshold = screenWidth * 0.25

        // Consider both distance AND velocity for natural feel
        let shouldAdvance = abs(translation) > threshold || abs(velocity) > 500

        if shouldAdvance {
            if translation > 0 && displayedPrevious != nil {
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
            } else if translation < 0 && displayedNext != nil {
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

    // Move queue item for reordering
    private func moveQueueItem(from source: IndexSet, to destination: Int) {
        queueManager.queueTracks.move(fromOffsets: source, toOffset: destination)
    }

    // Delete queue item (for swipe to delete)
    private func deleteQueueItem(at offsets: IndexSet) {
        for index in offsets {
            removeFromQueue(at: index)
        }
    }

    // Remove single item from queue with backend sync
    private func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queueManager.queueTracks.count else { return }
        let track = queueManager.queueTracks[index]

        Task {
            do {
                try await queueManager.removeTrack(track)
            } catch {
                // Removal failed - QueueManager handles rollback
                HapticManager.error()
            }
        }
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

// MARK: - Gesture Recognizer Helper
struct HorizontalPanGesture: UIViewRepresentable {
    var onChanged: (CGFloat, CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let gesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        gesture.delegate = context.coordinator
        view.addGestureRecognizer(gesture)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat, CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat) -> Void

        init(onChanged: @escaping (CGFloat, CGFloat) -> Void, onEnded: @escaping (CGFloat, CGFloat) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view).x
            let velocity = gesture.velocity(in: gesture.view).x

            switch gesture.state {
            case .changed:
                onChanged(translation, velocity)
            case .ended, .cancelled:
                onEnded(translation, velocity)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            // Only begin if horizontal motion dominates
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}


// MARK: - Glass Button Style
struct GlassToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .glassEffect(.regular, in: .capsule)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }
}

// MARK: - Track Card Component (Artwork + Title grouped)
struct TrackCard: View {
    let track: Track
    let namespace: Namespace.ID?
    let artworkWidth: CGFloat
    let cornerRadius: CGFloat
    var isMatchedGeometrySource: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // Artwork (flush to top)
            // Only apply matched geometry effect to the source card to avoid conflicts
            // Use constant ID to match MiniPlayer, not track.id
            PlayerArtworkView(
                artwork: track.artwork,
                namespace: isMatchedGeometrySource ? namespace : nil,
                id: isMatchedGeometrySource && namespace != nil ? "MINIPLAYER_ARTWORK" : nil,
                cornerRadius: cornerRadius,
                shadowRadius: 0
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(width: artworkWidth, height: artworkWidth)

            // Song info
            VStack(spacing: 6) {
                MarqueeGlassText(
                    text: track.title,
                    font: UIFont.systemFont(ofSize: 30, weight: .bold),
                    leftFade: 10,
                    rightFade: 10,
                    startDelay: 5.0
                )
                .frame(maxWidth: artworkWidth - 40) // Padding on sides

                Text(track.artist)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
        onDismiss: {},
        previewQueueTracks: Track.sampleTracks,
        initialShowQueue: true
    )
    .preferredColorScheme(.dark)
}

#Preview("Queue List") {
    @Previewable @State var queueExpansion: CGFloat = 200

    VStack(spacing: 0) {
        // Drag handle
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 40, height: 5)

            Text("Up Next")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 12)

        List {
            ForEach(Array(Track.sampleTracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(
                    track,
                    number: index + 1,
                    showCover: true
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    .frame(height: 280 + queueExpansion)
    .background(Color.blue.opacity(0.3))
    .preferredColorScheme(.dark)
}
