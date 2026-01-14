//
//  ExpandedPlayerBackgroundStack.swift
//  mixbridge
//

import SwiftUI

struct ExpandedPlayerBackgroundStack: View, Equatable {
    let previousArtwork: String?
    let nextArtwork: String?
    let stableArtwork: String

    let pendingArtwork: String?
    let pendingReady: Bool

    let isCrossfading: Bool
    let crossfadeProgress: Double

    let dragOffset: CGFloat
    let previousSwipeOpacity: Double
    let nextSwipeOpacity: Double

    let animationKey: String

    var body: some View {
        ZStack {
            // Layer 0: Solid black base - prevents GPU garbage from showing through
            Color.black
                .ignoresSafeArea()

            // Layer 1: Previous track background (fades in when swiping right)
            if let previousArtwork, dragOffset > 0 {
                PlayerBackgroundView(artwork: previousArtwork)
                    .opacity(previousSwipeOpacity)
                    .blur(radius: 80)
            }

            // Layer 2: Stable background (never swaps to an unready image)
            PlayerBackgroundView(artwork: stableArtwork)
                .blur(radius: 60)
                .opacity(isCrossfading && pendingReady ? 1.0 - crossfadeProgress : 1.0)

            // Layer 3: Next track background during crossfade (fades in)
            if isCrossfading,
               pendingReady,
               let pendingArtwork {
                PlayerBackgroundView(artwork: pendingArtwork)
                    .blur(radius: 60)
                    .opacity(crossfadeProgress)
            }

            // Layer 4: Next track background (fades in when swiping left)
            if let nextArtwork, dragOffset < 0 {
                PlayerBackgroundView(artwork: nextArtwork)
                    .opacity(nextSwipeOpacity)
                    .blur(radius: 80)
                    .blendMode(.screen)
            }

            // Layer 5: Subtle overlay for depth
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.12)
                .ignoresSafeArea()
        }
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.75), value: dragOffset)
        .animation(.smooth(duration: 0.7), value: animationKey)
    }
}

