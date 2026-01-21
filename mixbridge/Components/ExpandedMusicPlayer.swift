//
//  ExpandedMusicPlayer.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/10/25.
//

import SwiftUI
import UIKit
import SystemNotification

// MARK: - Smart Container
/// The "Smart" container that connects the PlayerState (Data) to the ExpandedPlayerView (UI).
/// It handles all the logic, bindings, and state management.
struct ExpandedMusicPlayer: View {
    @Binding var isPresented: Bool
    let namespace: Namespace.ID

    @Environment(PlayerState.self) private var playerState
    @EnvironmentObject private var systemNotification: SystemNotificationContext

    init(isPresented: Binding<Bool>, namespace: Namespace.ID) {
        self._isPresented = isPresented
        self.namespace = namespace
    }
    @Environment(QueueManager.self) private var queueManager
    @Environment(AuthManager.self) private var authManager
    @State private var isDraggingProgress = false

    /// Local slider value used during dragging to prevent observer conflicts
    @State private var localSliderPosition: Double = 0

    // Compute duration safely
    // During crossfade, interpolate between current and next track durations
    private var duration: Double {
        let currentDuration: Double
        if playerState.duration > 0 {
            currentDuration = playerState.duration
        } else {
            currentDuration = max(playerState.currentTrack.duration, 0)
        }

        // Interpolate during crossfade for smooth transition
        if playerState.isCrossfading && playerState.crossfadeNextDuration > 0 {
            let progress = playerState.crossfadeProgress
            return currentDuration * (1 - progress) + playerState.crossfadeNextDuration * progress
        }

        return currentDuration
    }

    // Compute interpolated playback position during crossfade
    private var interpolatedPosition: Double {
        if playerState.isCrossfading {
            let progress = playerState.crossfadeProgress
            // Interpolate from current position to next track's position
            return playerState.playbackPosition * (1 - progress) + playerState.crossfadeNextPosition * progress
        }
        return playerState.playbackPosition
    }

    // Get next track - forward history takes priority, otherwise queue.peek()
    private func getNextTrack() -> Track? {
        playerState.nextForwardTrack ?? queueManager.queue.peek()?.track
    }

    // Get previous track from session history (not from queue)
    private func getPreviousTrack() -> Track? {
        playerState.previousHistoryTrack
    }

    // Prefetch tracks for carousel
    private func prefetchSurroundingTracks() {
        let snapshot = queueManager.queueTracks
        let next = getNextTrack()
        Task(priority: .utility) {
            await TrackPrefetcher.shared.prefetchForQueue(snapshot, currentIndex: 0)
            if let next {
                await TrackPrefetcher.shared.preloadTrackImmediately(next)
            }
        }
    }

    var body: some View {
        @Bindable var playerState = playerState

        ExpandedPlayerView(
            currentTrack: playerState.currentTrack,
            currentQueueIndex: playerState.currentQueueIndex,
            nextTrack: getNextTrack(),
            previousTrack: getPreviousTrack(),
            isPlaying: playerState.isPlaying,
            namespace: namespace,
            playbackPosition: Binding(
                get: {
                    // Use local value during dragging, otherwise use interpolated position
                    // (interpolatedPosition handles crossfade smoothly)
                    isDraggingProgress ? localSliderPosition : interpolatedPosition
                },
                set: { newValue in
                    // Update local value during dragging
                    localSliderPosition = newValue
                }
            ),
            duration: duration,
            volume: $playerState.volume,
            isDraggingProgress: $isDraggingProgress,
            onPlayPause: {
                playerState.togglePlayback()
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
            // Queue is bootstrapped at app start; avoid a network refresh on open.
            playerState.syncQueueIndex()
            // Prefetch surrounding tracks when player opens
            prefetchSurroundingTracks()
        }
        .onChange(of: playerState.currentTrack.id) { _, _ in
            // Prefetch when track changes
            prefetchSurroundingTracks()
        }
        // `ExpandedMusicPlayer` is presented via `fullScreenCover`, so it needs
        // its own `systemNotification` host to show above the cover.
        .systemNotification(systemNotification)
    }
}

// MARK: - Dumb UI
/// A pure UI component that knows nothing about the PlayerState singleton.
/// It receives all data via arguments, making it reusable and testable.
struct ExpandedPlayerView: View {
    // Data (from PlayerState)
    let currentTrack: Track
    let currentQueueIndex: Int
    let nextTrack: Track?
    let previousTrack: Track?
    let isPlaying: Bool
    let namespace: Namespace.ID

    // Queue access for proper track mapping
    private var queueManager = QueueManager.shared

    @Environment(PlayerState.self) private var playerState
    @EnvironmentObject private var systemNotification: SystemNotificationContext

    // Bindings
    @Binding var playbackPosition: Double
    let duration: Double
    @Binding var volume: Double
    @Binding var isDraggingProgress: Bool

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
    @State private var displayedQueueIndex: Int
    @State private var displayedNext: Track?
    @State private var displayedPrevious: Track?
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingArtwork = false
    @State private var showQueueSheet: Bool
    @State private var queueExpansion: CGFloat // How much queue pushes content up

    // Crossfade-safe background handoff (never swap to an unready image).
    @State private var backgroundStableArtwork: String
    @State private var backgroundPendingArtwork: String? = nil
    @State private var backgroundPendingReady: Bool = false

    // Haptic generators (prepared for instant feedback)
    @State private var lightHaptic = UIImpactFeedbackGenerator(style: .light)
    @State private var heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var lastHapticThreshold: Int = 0
    @Namespace private var toolbarUnionNamespace

    init(currentTrack: Track, currentQueueIndex: Int = -1, nextTrack: Track?, previousTrack: Track?, isPlaying: Bool, namespace: Namespace.ID, playbackPosition: Binding<Double>, duration: Double, volume: Binding<Double>, isDraggingProgress: Binding<Bool>, onPlayPause: @escaping () -> Void, onNext: @escaping () -> Void, onPrevious: @escaping () -> Void, onSeek: @escaping (Bool) -> Void, onDismiss: @escaping () -> Void, previewQueueTracks: [Track]? = nil, initialShowQueue: Bool = false) {
        self.currentTrack = currentTrack
        self.currentQueueIndex = currentQueueIndex
        self.nextTrack = nextTrack
        self.previousTrack = previousTrack
        self.isPlaying = isPlaying
        self.namespace = namespace
        self._playbackPosition = playbackPosition
        self.duration = duration
        self._volume = volume
        self._isDraggingProgress = isDraggingProgress
        self.onPlayPause = onPlayPause
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onSeek = onSeek
        self.onDismiss = onDismiss
        self.previewQueueTracks = previewQueueTracks
        self.initialShowQueue = initialShowQueue

        // Initialize display state
        _displayedTrack = State(initialValue: currentTrack)
        _displayedQueueIndex = State(initialValue: currentQueueIndex)
        _displayedNext = State(initialValue: nextTrack)
        _displayedPrevious = State(initialValue: previousTrack)
        _showQueueSheet = State(initialValue: false)
        _queueExpansion = State(initialValue: 0) // Queue visible but no displacement
        _backgroundStableArtwork = State(initialValue: currentTrack.artwork)
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width

            // Responsive sizing
            let horizontalPadding = screenWidth * 0.075 // 7.5% of screen width
            let artworkMaxWidth = screenWidth
            let cornerRadius = screenWidth * 0.12

            // Target visual rhythm.
            let rhythm: CGFloat = 20
            let queueHandleTopPadding: CGFloat = 20
            let queueHandleBottomPadding: CGFloat = 6
            let queueTopFadeHeight: CGFloat = 30
            let queueListTopInset: CGFloat = 1 
            let queueSectionVisualLift: CGFloat = 44
            // If SwiftUI carousel state lags behind playback state, prefer playback-derived values
            // so we never briefly show the previous track at the end of a crossfade.
            let shouldPreferPlaybackTrack = !isDraggingArtwork && abs(dragOffset) < 0.5 && displayedTrack.id != currentTrack.id
            let effectiveDisplayedTrack = shouldPreferPlaybackTrack ? currentTrack : displayedTrack
            let previousSwipeOpacity = (displayedPrevious != nil && dragOffset > 0)
                ? calculateBackgroundOpacity(offset: dragOffset, direction: .left, screenWidth: screenWidth)
                : 0
            let nextSwipeOpacity = (displayedNext != nil && dragOffset < 0)
                ? calculateBackgroundOpacity(offset: dragOffset, direction: .right, screenWidth: screenWidth)
                : 0
            let queueRows = queueManager.queue.items.indexedRows()

            //Main stack below body
            ZStack(alignment: .top) {
                ExpandedPlayerBackgroundStack(
                    previousArtwork: displayedPrevious?.artwork,
                    nextArtwork: displayedNext?.artwork,
                    stableArtwork: backgroundStableArtwork,
                    pendingArtwork: backgroundPendingArtwork,
                    pendingReady: backgroundPendingReady,
                    isCrossfading: playerState.isCrossfading,
                    crossfadeProgress: playerState.crossfadeProgress,
                    dragOffset: dragOffset,
                    previousSwipeOpacity: previousSwipeOpacity,
                    nextSwipeOpacity: nextSwipeOpacity,
                    animationKey: displayedTrack.id
                )

                VStack(spacing: 0) {
                    // Top section (artwork + controls) - moves up when queue expands
                    Group {
                        VStack(spacing: rhythm) {
                            // 2. Artwork + Title Carousel (grouped together)
                            ZStack(alignment: .top) {
                                // Previous artwork (left hexagon face)
                                if let prevTrack = displayedPrevious {
                                    HexagonArtworkFace(
                                        track: prevTrack,
                                        artworkWidth: artworkMaxWidth,
                                        contentHorizontalPadding: horizontalPadding,
                                        cornerRadius: cornerRadius,
                                        rotation: calculate3DRotation(offset: dragOffset, direction: .left, screenWidth: screenWidth),
                                        anchor: .trailing, // Hinge at right edge
                                        opacity: calculateOpacity(offset: dragOffset, direction: .left, screenWidth: screenWidth),
                                        isPlaying: false,
                                        contentSpacing: rhythm
                                    )
                                    .offset(x: -artworkMaxWidth + dragOffset)
                                    .zIndex(0)
                                    .id("prev-\(prevTrack.id)")
                                }

                                // Current artwork (center hexagon face - flat)
                                HexagonArtworkFace(
                                    track: effectiveDisplayedTrack,
                                    artworkWidth: artworkMaxWidth,
                                    contentHorizontalPadding: horizontalPadding,
                                    cornerRadius: cornerRadius,
                                    rotation: calculate3DRotation(offset: dragOffset, direction: .center, screenWidth: screenWidth),
                                    anchor: dragOffset > 0 ? .leading : .trailing,
                                    opacity: 1.0,
                                    scale: isDraggingArtwork ? 0.97 : 1.0,
                                    isPlaying: isPlaying,
                                    isCurrentTrack: true,
                                    contentSpacing: rhythm
                                )
                                .offset(x: dragOffset)
                                .zIndex(1)

                                // Next artwork (right hexagon face)
                                if let nxtTrack = displayedNext {
                                    HexagonArtworkFace(
                                        track: nxtTrack,
                                        artworkWidth: artworkMaxWidth,
                                        contentHorizontalPadding: horizontalPadding,
                                        cornerRadius: cornerRadius,
                                        rotation: calculate3DRotation(offset: dragOffset, direction: .right, screenWidth: screenWidth),
                                        anchor: .leading, // Hinge at left edge
                                        opacity: calculateOpacity(offset: dragOffset, direction: .right, screenWidth: screenWidth),
                                        isPlaying: false,
                                        contentSpacing: rhythm
                                    )
                                    .offset(x: artworkMaxWidth + dragOffset)
                                    .zIndex(0)
                                    .id("next-\(nxtTrack.id)")
                                }
                            }
                            .frame(maxWidth: artworkMaxWidth)
                            .contentShape(Rectangle())
                            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.82), value: dragOffset)
                            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.8), value: displayedTrack.id)
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
                                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8)) {
                                        displayedPrevious = playerState.previousHistoryTrack
                                        displayedTrack = currentTrack
                                        displayedQueueIndex = 0
                                        displayedNext = playerState.nextForwardTrack ?? queueManager.queue.peek()?.track
                                        dragOffset = 0
                                        isDraggingArtwork = false
                                    }
                                }
                            }
                            .onChange(of: queueManager.queue.items.first?.id) { oldValue, newValue in
                                // Sync displayedNext when queue changes (reorder, remove, etc.)
                                let newNext = playerState.nextForwardTrack ?? queueManager.queue.peek()?.track
                                if displayedNext?.id != newNext?.id {
                                    displayedNext = newNext

                                    // Prefetch new next track artwork for smooth carousel
                                    if let nextItem = queueManager.queue.peek() {
                                        Task {
                                            await TrackPrefetcher.shared.preloadTrackImmediately(nextItem.track)
                                        }
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
                                displayedQueueIndex = 0
                                displayedNext = playerState.nextForwardTrack ?? queueManager.queue.peek()?.track
                                displayedPrevious = playerState.previousHistoryTrack

                                // Crossfade-safe background: start from the current track artwork.
                                backgroundStableArtwork = currentTrack.artwork

                                // Show queue sheet if queue has items
                                if queueManager.hasQueue {
                                    showQueueSheet = true
                                }

                                // Prefetch next track artwork for smooth carousel
                                if let nextItem = queueManager.queue.peek() {
                                    Task {
                                        await TrackPrefetcher.shared.preloadTrackImmediately(nextItem.track)
                                    }
                                }
                            }
                            .onChange(of: playerState.crossfadeNextTrack?.artwork) { _, newArtwork in
                                // Important: don't clear pending artwork when `crossfadeNextTrack` becomes nil at
                                // transition end; we commit/clear in the `isCrossfading` handoff below to avoid a
                                // 1-frame fallback to the old stable background.
                                guard let newArtwork, !newArtwork.isEmpty else { return }

                                backgroundPendingArtwork = newArtwork
                                backgroundPendingReady = isArtworkReady(newArtwork)
                                guard !backgroundPendingReady else { return }

                                let request = newArtwork
                                Task { @MainActor in
                                    let ok = await preloadArtwork(request)
                                    if backgroundPendingArtwork == request {
                                        backgroundPendingReady = ok
                                    }
                                }
                            }
                            .onChange(of: currentTrack.artwork) { _, newArtwork in
                                guard backgroundStableArtwork != newArtwork else { return }

                                if isArtworkReady(newArtwork) {
                                    backgroundStableArtwork = newArtwork
                                    return
                                }

                                let request = newArtwork
                                Task { @MainActor in
                                    let ok = await preloadArtwork(request)
                                    if ok, currentTrack.artwork == request {
                                        backgroundStableArtwork = request
                                    }
                                }
                            }
                            .onChange(of: playerState.isCrossfading) { _, isCrossfading in
                                // When crossfade ends, keep showing the stable background until the new
                                // `currentTrack.artwork` is confirmed ready (handled by onChange above).
                                if !isCrossfading {
                                    // Commit the destination background before removing the overlay to prevent
                                    // any one-frame flash back to the previous stable artwork.
                                    if backgroundPendingReady, let pending = backgroundPendingArtwork {
                                        backgroundStableArtwork = pending
                                    }
                                    backgroundPendingArtwork = nil
                                    backgroundPendingReady = false
                                }
                            }

                            PlayerProgressView(
                                value: $playbackPosition,
                                duration: duration,
                                isDragging: $isDraggingProgress,
                                onEditingChanged: onSeek
                            )
                            .padding(.horizontal, horizontalPadding)
                            .overlay(alignment: .top) {
                                // Mixing indicator - positioned above progress bar
                                if playerState.isCrossfading && playerState.mixEnabled {
                                    MixingIndicator()
                                        .offset(y: -1)
                                        .transition(.opacity)
                                }
                            }

                            PlayerControlsView(
                                isPlaying: isPlaying,
                                onPlayPause: onPlayPause,
                                onNext: onNext,
                                onPrevious: onPrevious
                            )
                            .padding(.horizontal, horizontalPadding)
                        }
                    }
                    // Apply offset to entire top section (artwork + controls) when queue expands
                    .offset(y: showQueueSheet ? -queueExpansion : 0)
                    .ignoresSafeArea(.all, edges: .top) // Flush artwork to top, applied to whole group
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: queueExpansion)

                    // 4. Queue List (when shown)
                    if showQueueSheet {
                        ExpandedPlayerQueueSheet(
                            isVisible: $showQueueSheet,
                            expansion: $queueExpansion,
                            queueRows: queueRows,
                            queueTopFadeHeight: queueTopFadeHeight,
                            queueListTopInset: queueListTopInset,
                            queueHandleTopPadding: queueHandleTopPadding,
                            queueHandleBottomPadding: queueHandleBottomPadding,
                            queueSectionVisualLift: queueSectionVisualLift,
                            onMove: moveQueueItem,
                            onRemove: removeFromQueue
                        )
                    } else {
                        Spacer()
                    }

                    // 5. Bottom Toolbar (always visible)
                    HStack {
                        // Repeat button (left side)
                        Button {
                            playerState.cycleRepeatMode()
                            HapticManager.selection()
                        } label: {
                            Image(systemName: playerState.repeatMode.symbolName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(playerState.repeatMode.isEnabled ? .white : .secondary)
                                .shadow(color: playerState.repeatMode.isEnabled ? .white.opacity(0.7) : .clear, radius: 6)
                                .shadow(color: playerState.repeatMode.isEnabled ? .white.opacity(0.3) : .clear, radius: 12)
                                .animation(.easeInOut(duration: 0.25), value: playerState.repeatMode)
                                .contentTransition(.symbolEffect(.replace))
                                .padding(12)
                        }
                        .glassEffect(.clear, in: .circle)

                        Spacer()

                        // Mix + Queue toolbar group
                        if queueManager.hasQueue {
                            GlassEffectContainer {
                                HStack(spacing: 12) {
                                    // Mix Mode toggle
                                    Button {
                                        playerState.mixEnabled.toggle()
                                        HapticManager.selection()
                                        presentAutomixNotification(isEnabled: playerState.mixEnabled)
                                    } label: {
                                        Image("wave-sine")
                                            .renderingMode(.template)
                                            .foregroundStyle(playerState.mixEnabled ? .white : .secondary)
                                            .animation(nil, value: playerState.mixEnabled)
                                            .shadow(color: playerState.mixEnabled ? .white.opacity(0.7) : .clear, radius: 6)
                                            .shadow(color: playerState.mixEnabled ? .white.opacity(0.3) : .clear, radius: 12)
                                            .animation(.easeInOut(duration: 0.25), value: playerState.mixEnabled)
                                            .padding(.leading, 12)
                                            .padding(.vertical, 6)
                                    }
                                    .glassEffectUnion(id: "playback-toolbar", namespace: toolbarUnionNamespace)

                                    // Queue button
                                    Button {
                                        HapticManager.selection()
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            showQueueSheet = true
                                            queueExpansion = 200
                                        }
                                    } label: {
                                        Image("queue")
                                            .renderingMode(.template)
                                            .foregroundStyle(.secondary)
                                            .padding(.trailing, 12)
                                            .padding(.vertical, 6)
                                    }
                                    .tint(.secondary)
                                    .glassEffectUnion(id: "playback-toolbar", namespace: toolbarUnionNamespace)
                                }
                            }
                            .glassEffect(.clear, in: .capsule)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task {
                                        try? await queueManager.clearQueueWithSync()
                                        presentQueueClearedNotification()
                                    }
                                } label: {
                                    Label("Clear Queue", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)

                }

            }
        }

        // Setup the hero transition
        .navigationTransition(.zoom(sourceID: "MINIPLAYER", in: namespace))
        .onChange(of: queueManager.hasQueue) { _, hasQueue in
            if hasQueue {
                // Auto-open queue sheet when queue loads with items
                if !showQueueSheet {
                    showQueueSheet = true
                }
            }
        }
    }

    @MainActor
    private func presentAutomixNotification(isEnabled: Bool) {
        systemNotification.present {
            AutomixSystemNotificationContent(isEnabled: isEnabled)
        }
    }

    @MainActor
    private func presentQueueClearedNotification() {
        systemNotification.present {
            QueueClearedSystemNotificationContent()
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

                // Snappy spring for hexagon "click into place" feel
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8, blendDuration: 0)) {
                    // Commit changes instantly
                    let newCurrent = displayedPrevious!
                    let newIndex = displayedQueueIndex - 1
                    displayedNext = displayedTrack
                    displayedTrack = newCurrent
                    displayedQueueIndex = newIndex
                    // Use explicit index to get previous track (avoids firstIndex() ambiguity)
                    displayedPrevious = getPreviousTrackByIndex(newIndex)
                    dragOffset = 0
                    isDraggingArtwork = false
                }

                onPrevious()
            } else if translation < 0 && displayedNext != nil {
                // Swipe left → next
                heavyHaptic.impactOccurred(intensity: 1.0) // Final heavy haptic on commit

                // Capture current display state before queue changes
                let trackBecomingCurrent = displayedNext!
                let trackBecomingPrevious = displayedTrack

                // Pop from queue FIRST (synchronous) - this updates queue.peek()
                // We need to tell playback to advance, which pops from queue
                onNext()

                // Now update display state - queue.peek() returns correct next track
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8, blendDuration: 0)) {
                    displayedPrevious = trackBecomingPrevious
                    displayedTrack = trackBecomingCurrent
                    displayedQueueIndex = 0  // Index is always 0 in new model (current not in queue)
                    displayedNext = playerState.nextForwardTrack ?? queueManager.queue.peek()?.track
                    dragOffset = 0
                    isDraggingArtwork = false
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

    // Get next track - forward history takes priority, otherwise queue.peek()
    private func getNextTrackByIndex(_ index: Int) -> Track? {
        playerState.nextForwardTrack ?? queueManager.queue.peek()?.track
    }

    // Get previous track from session history (index is ignored in history mode)
    private func getPreviousTrackByIndex(_ index: Int) -> Track? {
        playerState.previousHistoryTrack
    }

    // Move queue item for reordering - SYNCHRONOUS local update, async backend sync
    private func moveQueueItem(from source: IndexSet, to destination: Int) {
        guard let fromIndex = source.first else { return }
        guard fromIndex != destination else { return }

        // Immediate local mutation for instant UI feedback
        queueManager.moveItemLocal(from: fromIndex, to: destination)

        // Background sync to backend
        Task {
            await queueManager.syncMoveToBackend(from: fromIndex, to: destination)
        }
    }

    // Remove single item from queue - SYNCHRONOUS local update
    private func removeFromQueue(item: QueueItem) {
        // Immediate local mutation
        if let originalIndex = queueManager.removeItemLocal(item) {
            // Background sync to backend
            Task {
                await queueManager.syncRemoveToBackend(item: item, originalIndex: originalIndex)
            }
        }
    }

    // MARK: - Background Handoff Helpers

    private func isArtworkReady(_ artwork: String) -> Bool {
        if artwork.starts(with: "http"), let url = URL(string: artwork) {
            return MemoryImageCache.shared.get(url.absoluteString) != nil
        }
        // Local assets are effectively always ready once name is known.
        return UIImage(named: artwork) != nil || !artwork.isEmpty
    }

    private func preloadArtwork(_ artwork: String) async -> Bool {
        guard artwork.starts(with: "http"), let url = URL(string: artwork) else {
            return !artwork.isEmpty
        }
        return await ImageCacheManager.shared.getImage(for: url) != nil
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

    private func calculate3DRotation(offset: CGFloat, direction: Direction, screenWidth: CGFloat) -> Double {
        let normalizedOffset = offset / screenWidth
        let maxRotation: Double = 60 // degrees - hexagon face angle

        switch direction {
        case .left:
            // Previous card: starts at -60deg (on left face of hexagon)
            // Rotates toward 0 as it becomes center
            return -maxRotation + (offset > 0 ? Double(normalizedOffset) * maxRotation : 0)
        case .right:
            // Next card: starts at +60deg (on right face of hexagon)
            // Rotates toward 0 as it becomes center
            return maxRotation + (offset < 0 ? Double(normalizedOffset) * maxRotation : 0)
        case .center:
            // Current card: rotates away onto hexagon face as you swipe
            // Swipe left (offset < 0): rotates to -60 (exits left)
            // Swipe right (offset > 0): rotates to +60 (exits right)
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

private struct AutomixSystemNotificationContent: View {
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            AutomixSystemNotificationIcon(isEnabled: isEnabled)

            Text("Automix")
                .font(.footnote.bold())
                .foregroundStyle(.primary)

            Text(isEnabled ? "On" : "Off")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 7)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct AutomixSystemNotificationIcon: View {
    let isEnabled: Bool

    @State private var isRotated = false
    @State private var isAnimated = false

    var body: some View {
        Image("wave-sine")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(isRotated ? -14 : 0), anchor: .center)
            .animation(
                .interpolatingSpring(
                    mass: 0.5,
                    stiffness: isEnabled ? 140 : 180,
                    damping: isEnabled ? 5 : 2,
                    initialVelocity: 0
                ),
                value: isAnimated
            )
            .foregroundStyle(isEnabled ? .white : Color.gray)
            .shadow(color: isEnabled ? .white.opacity(0.7) : .clear, radius: 6)
            .shadow(color: isEnabled ? .white.opacity(0.3) : .clear, radius: 12)
            .onAppear(perform: animate)
    }
}

@MainActor
private extension AutomixSystemNotificationIcon {

    func animate() {
        withAnimation { isRotated = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isRotated = false
            isAnimated = true
        }
    }
}

private struct QueueClearedSystemNotificationContent: View {
    var body: some View {
        HStack(spacing: 12) {
            QueueClearedSystemNotificationIcon()
            Text("Cleared")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 7)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct QueueClearedSystemNotificationIcon: View {
    @State private var isAnimated = false

    var body: some View {
        Image("queue")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .scaleEffect(isAnimated ? 1.0 : 0.8)
            .opacity(isAnimated ? 1.0 : 0.6)
            .animation(
                .interpolatingSpring(
                    mass: 0.5,
                    stiffness: 150,
                    damping: 6,
                    initialVelocity: 0
                ),
                value: isAnimated
            )
            .foregroundStyle(.white)
            .onAppear {
                isAnimated = true
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

// MARK: - Hexagon Artwork Face (3D rotated artwork only)
struct HexagonArtworkFace: View {
    let track: Track
    let artworkWidth: CGFloat
    var contentHorizontalPadding: CGFloat = 20
    let cornerRadius: CGFloat
    let rotation: Double
    let anchor: UnitPoint
    var opacity: Double = 1.0
    var scale: CGFloat = 1.0
    var isPlaying: Bool = true
    var isCurrentTrack: Bool = false // Whether this is the center/current track
    var contentSpacing: CGFloat = 20 // Spacing between artwork and title

    @Environment(PlayerState.self) private var playerState

    // Crossfade handoff: if crossfade visuals end before `currentTrack` updates,
    // keep showing the destination artwork until the track swap arrives.
    @State private var crossfadeHandoffTrackId: String? = nil
    @State private var crossfadeHandoffArtwork: String? = nil

    var body: some View {
        let contentWidth = max(artworkWidth - (contentHorizontalPadding * 2), 1)
        
        VStack(spacing: contentSpacing + 5) {
            // Artwork with 3D rotation applied
            // Layer the destination artwork behind Metal view to prevent flicker on transition end
            ZStack {
                // Base layer: Regular artwork
                // For current track position: use playerState sources (always up-to-date)
                // During crossfade: show next track (destination)
                // After crossfade: show currentTrack (already updated)
                // For prev/next carousel positions: use track (displayedPrevious/displayedNext)
                let baseArtwork: String = {
                    guard isCurrentTrack else { return track.artwork }
                    if playerState.isCrossfading {
                        return playerState.crossfadeNextTrack?.artwork ?? playerState.currentTrack.artwork
                    }
                    if let targetId = crossfadeHandoffTrackId,
                       playerState.currentTrack.id != targetId,
                       let handoff = crossfadeHandoffArtwork {
                        return handoff
                    }
                    return playerState.currentTrack.artwork
                }()
                PlayerArtworkView(
                    artwork: baseArtwork,
                    namespace: nil,
                    id: nil,
                    cornerRadius: cornerRadius,
                    shadowRadius: 0
                )

                // Overlay: Metal morph during crossfade
                if isCurrentTrack,
                   playerState.isCrossfading,
                   let nextTrack = playerState.crossfadeNextTrack,
                   LiquidMorphView.isMetalAvailable {
                    let fromArtwork = playerState.crossfadeFromArtwork.isEmpty
                        ? playerState.currentTrack.artwork
                        : playerState.crossfadeFromArtwork
                    LiquidMorphView(
                        fromArtworkURL: fromArtwork,
                        toArtworkURL: nextTrack.artwork,
                        progress: playerState.crossfadeProgress,
                        size: CGSize(width: artworkWidth, height: artworkWidth)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(width: artworkWidth, height: artworkWidth)
            .rotation3DEffect(
                .degrees(rotation),
                axis: (x: 0, y: 1, z: 0),
                anchor: anchor,
                perspective: 0.3
            )
            .opacity(opacity)
            .scaleEffect(scale)

            // Song info (doesn't rotate - stays flat)
            VStack(spacing: -2) {
                MarqueeGlassText(
                    text: track.title,
                    font: UIFont.systemFont(ofSize: 30, weight: .bold),
                    leftFade: 10,
                    rightFade: 10,
                    startDelay: 5.0,
                    isPlaying: isPlaying
                )
                .frame(width: contentWidth)

                Text(track.artist)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: contentWidth)
            }
            .opacity(opacity)
        }
        .frame(width: artworkWidth)
        .onChange(of: playerState.crossfadeNextTrack?.id) { _, _ in
            guard isCurrentTrack, let next = playerState.crossfadeNextTrack else { return }
            crossfadeHandoffTrackId = next.id
            crossfadeHandoffArtwork = next.artwork
        }
        .onChange(of: playerState.currentTrack.id) { _, _ in
            guard isCurrentTrack else { return }
            if let targetId = crossfadeHandoffTrackId, playerState.currentTrack.id == targetId {
                crossfadeHandoffTrackId = nil
                crossfadeHandoffArtwork = nil
            }
        }
        .onChange(of: playerState.crossfadeProgress) { _, progress in
            // Abort case: progress snaps back to 0 with no next track, and we never swapped tracks.
            // Keep the handoff alive across normal completion (where `currentTrack.id` becomes the target).
            guard isCurrentTrack else { return }
            guard progress <= 0.0001 else { return }
            guard !playerState.isCrossfading else { return }
            guard playerState.crossfadeNextTrack == nil else { return }
            guard let targetId = crossfadeHandoffTrackId else { return }
            guard playerState.currentTrack.id != targetId else { return }
            crossfadeHandoffTrackId = nil
            crossfadeHandoffArtwork = nil
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
        onPlayPause: {},
        onNext: {},
        onPrevious: {},
        onSeek: { _ in },
        onDismiss: {},
        previewQueueTracks: Track.sampleTracks,
        initialShowQueue: true
    )
    .environment(PlayerState.shared)
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
        .padding(.top, 8)
        .padding(.bottom, 6)

        List {
            let rows = Track.sampleTracks.indexedRows()
            ForEach(rows) { row in
                TrackRow(
                    row.item,
                    number: row.index + 1,
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
    .environment(PlayerState.shared)
    .preferredColorScheme(.dark)
}
