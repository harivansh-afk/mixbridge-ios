//
//  View+Animations.swift
//  mixbridge
//
//  Created for smooth Apple Music-like animations
//

import SwiftUI

extension View {
    /// Adds a smooth spring animation on appearance (Apple Music style)
    func smoothAppear(delay: Double = 0) -> some View {
        self.modifier(SmoothAppearModifier(delay: delay))
    }

    /// Adds a subtle scale animation on tap
    func subtleScale(isPressed: Bool) -> some View {
        self.scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }
}

struct SmoothAppearModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.95)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension Animation {
    /// Smooth spring animation matching Apple Music's feel
    static var appleMusic: Animation {
        .spring(response: 0.4, dampingFraction: 0.75)
    }

    /// Bouncy spring for interactive elements
    static var appleInteractive: Animation {
        .spring(response: 0.3, dampingFraction: 0.7)
    }
}
