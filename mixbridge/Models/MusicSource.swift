//
//  MusicSource.swift
//  mixbridge
//
//  Platform-aware music source enum for multi-platform track/playlist support.
//

import Foundation

/// Represents the source platform for a track or playlist
public enum MusicSource: String, Codable, Sendable, CaseIterable {
    case soundcloud
    case spotify
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .soundcloud:
            return "SoundCloud"
        case .spotify:
            return "Spotify"
        }
    }
    
    /// SF Symbol icon name for the source
    public var iconName: String {
        switch self {
        case .soundcloud:
            return "cloud.fill"
        case .spotify:
            return "music.note"
        }
    }
}
