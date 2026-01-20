//
//  AppleMusicService.swift
//  mixbridge
//
//  Apple Music service using native MusicKit APIs.
//  Provides profile, playlists, likes, search, and playback functionality.
//

import Foundation
import MusicKit

/// Apple Music service using MusicKit
actor AppleMusicService {
    static let shared = AppleMusicService()

    private init() {}

    // MARK: - Profile

    /// Get current user's subscription info
    func getCurrentSubscription() async throws -> MusicSubscription {
        return try await MusicSubscription.current
    }

    /// Get current storefront (region)
    func getCurrentStorefront() async throws -> String {
        return try await MusicDataRequest.currentCountryCode
    }

    // MARK: - Library Playlists

    /// Fetch user's library playlists
    func getLibraryPlaylists(limit: Int = 50) async throws -> [AppleMusicPlaylist] {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = limit

        let response = try await request.response()

        return response.items.map { playlist in
            AppleMusicPlaylist(
                id: playlist.id.rawValue,
                name: playlist.name,
                description: playlist.standardDescription ?? "",
                artwork: playlist.artwork?.url(width: 500, height: 500)?.absoluteString ?? "",
                trackCount: 0 // MusicKit doesn't expose count directly
            )
        }
    }

    /// Fetch tracks from a playlist
    func getPlaylistTracks(playlistId: String, limit: Int = 100) async throws -> [AppleMusicTrack] {
        guard let id = MusicItemID(playlistId) else {
            throw AppleMusicServiceError.invalidId
        }

        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: id)

        let response = try await request.response()
        guard let playlist = response.items.first else {
            throw AppleMusicServiceError.notFound
        }

        let detailedPlaylist = try await playlist.with([.tracks])

        return detailedPlaylist.tracks?.compactMap { track in
            AppleMusicTrack(
                id: track.id.rawValue,
                title: track.title,
                artist: track.artistName,
                album: track.albumTitle ?? "",
                duration: track.duration ?? 0,
                artwork: track.artwork?.url(width: 500, height: 500)?.absoluteString ?? "",
                isExplicit: track.contentRating == .explicit,
                appleMusicUrl: track.url?.absoluteString ?? ""
            )
        } ?? []
    }

    // MARK: - Library Songs (Likes)

    /// Fetch user's library songs
    func getLibrarySongs(limit: Int = 100) async throws -> [AppleMusicTrack] {
        var request = MusicLibraryRequest<Song>()
        request.limit = limit

        let response = try await request.response()

        return response.items.map { song in
            AppleMusicTrack(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle ?? "",
                duration: song.duration ?? 0,
                artwork: song.artwork?.url(width: 500, height: 500)?.absoluteString ?? "",
                isExplicit: song.contentRating == .explicit,
                appleMusicUrl: song.url?.absoluteString ?? ""
            )
        }
    }

    /// Fetch recently added songs
    func getRecentlyAddedSongs(limit: Int = 25) async throws -> [AppleMusicTrack] {
        var request = MusicLibraryRequest<Song>()
        request.limit = limit
        request.sort(by: \.libraryAddedDate, ascending: false)

        let response = try await request.response()

        return response.items.map { song in
            AppleMusicTrack(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle ?? "",
                duration: song.duration ?? 0,
                artwork: song.artwork?.url(width: 500, height: 500)?.absoluteString ?? "",
                isExplicit: song.contentRating == .explicit,
                appleMusicUrl: song.url?.absoluteString ?? ""
            )
        }
    }

    // MARK: - Search

    /// Search Apple Music catalog
    func search(query: String, limit: Int = 25) async throws -> AppleMusicSearchResult {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self, Album.self, Artist.self, Playlist.self])
        request.limit = limit

        let response = try await request.response()

        let tracks = response.songs.map { song in
            AppleMusicTrack(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle ?? "",
                duration: song.duration ?? 0,
                artwork: song.artwork?.url(width: 500, height: 500)?.absoluteString ?? "",
                isExplicit: song.contentRating == .explicit,
                appleMusicUrl: song.url?.absoluteString ?? ""
            )
        }

        let playlists = response.playlists.map { playlist in
            AppleMusicPlaylist(
                id: playlist.id.rawValue,
                name: playlist.name,
                description: playlist.standardDescription ?? "",
                artwork: playlist.artwork?.url(width: 500, height: 500)?.absoluteString ?? "",
                trackCount: 0
            )
        }

        let artists = response.artists.map { artist in
            AppleMusicArtist(
                id: artist.id.rawValue,
                name: artist.name,
                artwork: artist.artwork?.url(width: 500, height: 500)?.absoluteString ?? ""
            )
        }

        return AppleMusicSearchResult(
            tracks: Array(tracks),
            playlists: Array(playlists),
            artists: Array(artists)
        )
    }

    /// Search user's library
    func searchLibrary(query: String, limit: Int = 25) async throws -> [AppleMusicTrack] {
        var request = MusicLibrarySearchRequest(term: query, types: [Song.self])
        request.limit = limit

        let response = try await request.response()

        return response.songs.map { song in
            AppleMusicTrack(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle ?? "",
                duration: song.duration ?? 0,
                artwork: song.artwork?.url(width: 500, height: 500)?.absoluteString ?? "",
                isExplicit: song.contentRating == .explicit,
                appleMusicUrl: song.url?.absoluteString ?? ""
            )
        }
    }

    // MARK: - Playback

    /// Get a Song item for playback by ID
    func getSongForPlayback(trackId: String) async throws -> Song {
        guard let id = MusicItemID(trackId) else {
            throw AppleMusicServiceError.invalidId
        }

        var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
        let response = try await request.response()

        guard let song = response.items.first else {
            // Try library if not in catalog
            return try await getLibrarySongForPlayback(trackId: trackId)
        }

        return song
    }

    /// Get a Song from user's library for playback
    private func getLibrarySongForPlayback(trackId: String) async throws -> Song {
        guard let id = MusicItemID(trackId) else {
            throw AppleMusicServiceError.invalidId
        }

        var request = MusicLibraryRequest<Song>()
        request.filter(matching: \.id, equalTo: id)

        let response = try await request.response()

        guard let song = response.items.first else {
            throw AppleMusicServiceError.notFound
        }

        return song
    }

    /// Create a queue from tracks for playback
    func createQueue(from tracks: [AppleMusicTrack]) async throws -> [Song] {
        var songs: [Song] = []

        for track in tracks {
            if let song = try? await getSongForPlayback(trackId: track.id) {
                songs.append(song)
            }
        }

        return songs
    }

    // MARK: - Albums

    /// Fetch user's library albums
    func getLibraryAlbums(limit: Int = 50) async throws -> [AppleMusicAlbum] {
        var request = MusicLibraryRequest<Album>()
        request.limit = limit

        let response = try await request.response()

        return response.items.map { album in
            AppleMusicAlbum(
                id: album.id.rawValue,
                title: album.title,
                artist: album.artistName,
                artwork: album.artwork?.url(width: 500, height: 500)?.absoluteString ?? "",
                trackCount: album.trackCount
            )
        }
    }

    // MARK: - Artists

    /// Fetch user's library artists
    func getLibraryArtists(limit: Int = 50) async throws -> [AppleMusicArtist] {
        var request = MusicLibraryRequest<Artist>()
        request.limit = limit

        let response = try await request.response()

        return response.items.map { artist in
            AppleMusicArtist(
                id: artist.id.rawValue,
                name: artist.name,
                artwork: artist.artwork?.url(width: 500, height: 500)?.absoluteString ?? ""
            )
        }
    }
}

// MARK: - Types

struct AppleMusicTrack: Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artwork: String
    let isExplicit: Bool
    let appleMusicUrl: String

    /// Convert to the app's Track model
    func toTrack() -> Track {
        Track(
            id: "applemusic:\(id)",
            title: title,
            artist: artist,
            artwork: artwork,
            duration: duration,
            provider: .applemusic
        )
    }
}

struct AppleMusicPlaylist: Sendable {
    let id: String
    let name: String
    let description: String
    let artwork: String
    let trackCount: Int
}

struct AppleMusicAlbum: Sendable {
    let id: String
    let title: String
    let artist: String
    let artwork: String
    let trackCount: Int
}

struct AppleMusicArtist: Sendable {
    let id: String
    let name: String
    let artwork: String
}

struct AppleMusicSearchResult: Sendable {
    let tracks: [AppleMusicTrack]
    let playlists: [AppleMusicPlaylist]
    let artists: [AppleMusicArtist]
}

enum AppleMusicServiceError: LocalizedError {
    case invalidId
    case notFound
    case notAuthorized
    case noSubscription

    var errorDescription: String? {
        switch self {
        case .invalidId:
            return "Invalid Apple Music ID"
        case .notFound:
            return "Item not found in Apple Music"
        case .notAuthorized:
            return "Apple Music access not authorized"
        case .noSubscription:
            return "Apple Music subscription required"
        }
    }
}
