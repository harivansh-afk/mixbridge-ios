//
//  PlayerState.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI

@Observable
class PlayerState {
    static let shared = PlayerState()

    var currentTrack: Track = Track.sampleTracks.first ?? Track(
        title: "Some Music Title",
        artist: "Unknown Artist",
        album: "Unknown Album"
    )

    var isPlaying: Bool = false
    var playbackPosition: Double = 0

    private init() {}
}
