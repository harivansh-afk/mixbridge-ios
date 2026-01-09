//
//  MixingIndicator.swift
//  mixbridge
//
//  Glass effect "mixing" text with subtle shine animation.
//

import SwiftUI
import UIKit

/// Animated "mixing" indicator with liquid glass effect and subtle shine.
/// Compact design - takes zero extra vertical space.
struct MixingIndicator: View {
    var isAnimating: Bool = true

    private let font = UIFont.systemFont(ofSize: 13, weight: .medium)
    private let text = "mixing"

    var body: some View {
        ShineGlassText(
            text: text,
            font: font,
            isAnimating: isAnimating
        )
        .frame(height: 14)
    }
}

/// Glass text with a subtle animated shine layer underneath.
struct ShineGlassText: View {
    let text: String
    let font: UIFont
    var isAnimating: Bool = true

    /// Total cycle duration (continuous sweep)
    private let cycleDuration: Double = 1.8
    /// Fraction of cycle spent sweeping (1.0 = no pause)
    private let sweepFraction: Double = 1.0

    private let startDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { context in
            let progress = shineProgress(at: context.date)

            ZStack {
                // Shine layer - positioned below the glass
                ShineLayer(progress: progress)
                    .mask(TextToShape(value: text, font: font))

                // Glass text on top
                Text(text)
                    .font(Font(font))
                    .opacity(0)
                    .glassEffect(.clear, in: TextToShape(value: text, font: font))
            }
        }
    }

    private func shineProgress(at date: Date) -> CGFloat {
        guard isAnimating else { return -1 }
        let elapsed = date.timeIntervalSince(startDate)
        let cyclePosition = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration

        // During sweep phase, animate from -0.3 to 1.3
        // During pause phase, stay off-screen
        if cyclePosition < sweepFraction {
            let t = cyclePosition / sweepFraction
            return -0.3 + (t * 1.6) // -0.3 to 1.3
        } else {
            return -1 // Off-screen during pause
        }
    }
}

/// Subtle gradient shine layer - narrow band that sweeps across
struct ShineLayer: View {
    /// Progress from 0 to 1 (left to right)
    var progress: CGFloat

    /// Width of shine band as fraction of total width
    private let bandWidth: CGFloat = 0.85

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let shineW = width * bandWidth
            // Position: progress 0 = left edge, progress 1 = right edge
            let xPos = (progress * (width + shineW)) - shineW

            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.25), location: 0.4),
                            .init(color: .white.opacity(0.5), location: 0.5),
                            .init(color: .white.opacity(0.25), location: 0.6),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: shineW, height: geo.size.height)
                .position(x: xPos + shineW / 2, y: geo.size.height / 2)
                .blur(radius: 0.5)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            MixingIndicator()

            MixingIndicator(isAnimating: false)
        }
    }
    .preferredColorScheme(.dark)
}
