//
//  CarouselState.swift
//  mixbridge
//
//  State machine for smooth carousel navigation
//

import SwiftUI

@Observable
@MainActor
final class CarouselState {
    enum AnimationPhase {
        case idle
        case dragging(offset: CGFloat)
        case settling
        case committed

        var isInteractive: Bool {
            if case .dragging = self { return true }
            return false
        }
    }

    // Current animation state
    var phase: AnimationPhase = .idle
    var dragOffset: CGFloat = 0

    // Display tracks (independent of player state)
    var displayedTrack: Track
    var displayedNext: Track?
    var displayedPrevious: Track?

    init(current: Track, next: Track?, previous: Track?) {
        self.displayedTrack = current
        self.displayedNext = next
        self.displayedPrevious = previous
    }

    // MARK: - State Transitions

    func beginDrag() {
        guard case .idle = phase else { return }
        phase = .dragging(offset: 0)
    }

    func updateDrag(offset: CGFloat) {
        dragOffset = offset
        phase = .dragging(offset: offset)
    }

    func commitNext() {
        guard let next = displayedNext else { return }

        // Instant visual update - no waiting for player
        displayedPrevious = displayedTrack
        displayedTrack = next
        displayedNext = nil // Will be updated by syncWithPlayer
        dragOffset = 0
        phase = .committed
    }

    func commitPrevious() {
        guard let previous = displayedPrevious else { return }

        // Instant visual update - no waiting for player
        displayedNext = displayedTrack
        displayedTrack = previous
        displayedPrevious = nil // Will be updated by syncWithPlayer
        dragOffset = 0
        phase = .committed
    }

    func cancelDrag() {
        phase = .settling
        dragOffset = 0

        // Return to idle after animation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
            if case .settling = phase {
                phase = .idle
            }
        }
    }

    func syncWithPlayer(current: Track, next: Track?, previous: Track?) {
        // Only update if out of sync
        if displayedTrack.id != current.id {
            displayedTrack = current
            displayedNext = next
            displayedPrevious = previous
            dragOffset = 0
            phase = .idle
        } else {
            // Update adjacent tracks without disrupting current display
            displayedNext = next
            displayedPrevious = previous

            // If we were waiting for sync after commit, now we're idle
            if case .committed = phase {
                phase = .idle
            }
        }
    }

    func reset(current: Track, next: Track?, previous: Track?) {
        displayedTrack = current
        displayedNext = next
        displayedPrevious = previous
        dragOffset = 0
        phase = .idle
    }
}
