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
    let spotifyUrl: String?

    func body(content: Content) -> some View {
        content
            .onAppear {
                Task.detached(priority: .utility) { [trackId, spotifyUrl] in
                    await StreamURLCache.shared.prefetchStreamURL(for: trackId, spotifyUrl: spotifyUrl)
                }
            }
    }
}

extension View {
    /// Prefetch stream URL when this view appears
    /// Use on track rows to reduce playback latency
    func prefetchStream(for trackId: String, spotifyUrl: String? = nil) -> some View {
        modifier(TrackPrefetchModifier(trackId: trackId, spotifyUrl: spotifyUrl))
    }
}
