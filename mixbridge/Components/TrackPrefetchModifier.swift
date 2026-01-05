//
//  TrackPrefetchModifier.swift
//  mixbridge
//
//  Prefetch stream URL when track becomes visible in list views.
//  Reduces time-to-first-audio by ~100-300ms for visible tracks.
//

import SwiftUI

/// Prefetch stream URL when track becomes visible
struct TrackPrefetchModifier: ViewModifier {
    let trackId: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                Task.detached(priority: .utility) { [trackId] in
                    await StreamURLCache.shared.prefetchStreamURL(for: trackId)
                }
            }
    }
}

extension View {
    /// Prefetch stream URL when this view appears
    /// Use on track rows to reduce playback latency
    func prefetchStream(for trackId: String) -> some View {
        modifier(TrackPrefetchModifier(trackId: trackId))
    }
}
