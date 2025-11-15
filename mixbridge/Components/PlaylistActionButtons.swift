//
//  PlaylistActionButtons.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI

struct PlaylistActionButtons: View {
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(action: onShuffle) {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

#Preview("Light Mode") {
    PlaylistActionButtons(
        onPlay: { print("Play tapped") },
        onShuffle: { print("Shuffle tapped") }
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    PlaylistActionButtons(
        onPlay: { print("Play tapped") },
        onShuffle: { print("Shuffle tapped") }
    )
    .padding()
    .preferredColorScheme(.dark)
}
