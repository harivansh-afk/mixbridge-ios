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
            Button(action: {
                HapticManager.medium()
                onPlay()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .imageScale(.small)
                    Text("Play")
                }
                .font(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.primary)
                .glassEffect(.clear, in: .capsule)
            }
            .buttonStyle(.plain)

            Button(action: {
                HapticManager.medium()
                onShuffle()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                        .imageScale(.small)
                    Text("Shuffle")
                }
                .font(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.primary)
                .glassEffect(.clear, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("Light Mode") {
    PlaylistActionButtons(
        onPlay: {},
        onShuffle: {}
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    PlaylistActionButtons(
        onPlay: {},
        onShuffle: {}
    )
    .padding()
    .preferredColorScheme(.dark)
}
