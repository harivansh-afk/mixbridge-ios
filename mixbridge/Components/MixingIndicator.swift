//
//  MixingIndicator.swift
//  mixbridge
//
//  Plain "mixing" text indicator (no shine animation).
//

import SwiftUI

/// "mixing" indicator shown during crossfade.
/// Compact design - takes zero extra vertical space.
struct MixingIndicator: View {
    private let text = "mixing"

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        .frame(height: 14)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            MixingIndicator()
        }
    }
    .preferredColorScheme(.dark)
}
