import Foundation
@testable import mixbridge

/// Provides reusable test data fixtures for unit tests
enum TestFixtures {

    // MARK: - Users

    static let testUser = SoundCloudUser(
        id: 12345,
        username: "TestArtist",
        avatar_url: "https://example.com/avatar.jpg",
        permalink_url: "https://soundcloud.com/testartist",
        followers_count: 1000,
        followings_count: 50
    )

    static let secondaryUser = SoundCloudUser(
        id: 67890,
        username: "SecondArtist",
        avatar_url: "https://example.com/avatar2.jpg",
        permalink_url: "https://soundcloud.com/secondartist",
        followers_count: 500,
        followings_count: 25
    )

    // MARK: - Tracks

    static let sampleTrack = SoundCloudTrack(
        id: 100001,
        title: "Test Track",
        user: testUser,
        duration: 180000, // 3 minutes in ms
        artwork_url: "https://example.com/artwork.jpg",
        permalink_url: "https://soundcloud.com/testartist/test-track",
        playback_count: 5000,
        genre: "Electronic",
        description: "A test track for unit testing",
        created_at: "2024-01-15T10:30:00Z",
        waveform_url: "https://example.com/waveform.png",
        likes_count: 250,
        comment_count: 15,
        reposts_count: 30
    )

    static let secondaryTrack = SoundCloudTrack(
        id: 100002,
        title: "Another Track",
        user: secondaryUser,
        duration: 240000, // 4 minutes in ms
        artwork_url: "https://example.com/artwork2.jpg",
        permalink_url: "https://soundcloud.com/secondartist/another-track",
        playback_count: 3000,
        genre: "House",
        description: "Another test track",
        created_at: "2024-01-20T14:00:00Z",
        waveform_url: nil,
        likes_count: 150,
        comment_count: 8,
        reposts_count: 12
    )

    static let minimalTrack = SoundCloudTrack(
        id: 100003,
        title: "Minimal Track",
        user: testUser,
        duration: 60000,
        artwork_url: nil,
        permalink_url: nil,
        playback_count: nil,
        genre: nil,
        description: nil,
        created_at: nil,
        waveform_url: nil,
        likes_count: nil,
        comment_count: nil,
        reposts_count: nil
    )

    static func makeTracks(count: Int) -> [SoundCloudTrack] {
        (0..<count).map { index in
            SoundCloudTrack(
                id: 200000 + index,
                title: "Track \(index + 1)",
                user: testUser,
                duration: (60 + index * 30) * 1000,
                artwork_url: "https://example.com/artwork\(index).jpg",
                permalink_url: nil,
                playback_count: 1000 * index,
                genre: "Electronic",
                description: nil,
                created_at: nil,
                waveform_url: nil,
                likes_count: nil,
                comment_count: nil,
                reposts_count: nil
            )
        }
    }

    // MARK: - Playlists

    static let samplePlaylist = SoundCloudPlaylist(
        id: 500001,
        title: "Test Playlist",
        user: testUser,
        duration: 3600000, // 1 hour in ms
        artwork_url: "https://example.com/playlist-art.jpg",
        permalink_url: "https://soundcloud.com/testartist/sets/test-playlist",
        track_count: 15,
        tracks: [sampleTrack, secondaryTrack],
        description: "A test playlist for unit testing",
        genre: "Electronic",
        created_at: "2024-01-10T08:00:00Z"
    )

    static let emptyPlaylist = SoundCloudPlaylist(
        id: 500002,
        title: "Empty Playlist",
        user: testUser,
        duration: 0,
        artwork_url: nil,
        permalink_url: nil,
        track_count: 0,
        tracks: [],
        description: nil,
        genre: nil,
        created_at: nil
    )

    static func makePlaylists(count: Int) -> [SoundCloudPlaylist] {
        (0..<count).map { index in
            SoundCloudPlaylist(
                id: 600000 + index,
                title: "Playlist \(index + 1)",
                user: testUser,
                duration: 1800000 * (index + 1),
                artwork_url: "https://example.com/playlist\(index).jpg",
                permalink_url: nil,
                track_count: 10 + index,
                tracks: nil,
                description: "Playlist description \(index)",
                genre: "Mixed",
                created_at: nil
            )
        }
    }

    // MARK: - Profiles

    static let sampleProfile = SoundCloudProfile(
        id: 12345,
        username: "TestArtist",
        full_name: "Test Artist Name",
        first_name: "Test",
        last_name: "Artist",
        avatar_url: "https://example.com/avatar.jpg",
        permalink_url: "https://soundcloud.com/testartist",
        followers_count: 1000,
        followings_count: 50,
        track_count: 25,
        playlist_count: 5,
        likes_count: 500,
        plan: "Pro",
        description: "A test artist profile",
        city: "San Francisco",
        country: "USA"
    )

    static let minimalProfile = SoundCloudProfile(
        id: 99999,
        username: "minimal_user",
        full_name: nil,
        first_name: nil,
        last_name: nil,
        avatar_url: nil,
        permalink_url: nil,
        followers_count: nil,
        followings_count: nil,
        track_count: nil,
        playlist_count: nil,
        likes_count: nil,
        plan: nil,
        description: nil,
        city: nil,
        country: nil
    )

    // MARK: - Search Results

    static let sampleSearchResult = SearchResult(
        tracks: [sampleTrack, secondaryTrack],
        playlists: [samplePlaylist],
        users: [testUser, secondaryUser]
    )

    static let emptySearchResult = SearchResult(
        tracks: [],
        playlists: [],
        users: []
    )

    // MARK: - IDs

    static let testUserId = "user-123456"
    static let testTrackId = "100001"
    static let testPlaylistId = "500001"
    static let testQueueTrackId = "queue-track-abc123"

    // MARK: - Custom Playlists

    static let sampleCustomPlaylist = ConvexCustomPlaylist(
        playlistId: "custom-playlist-001",
        name: "My Custom Playlist",
        description: "A custom playlist created by the user",
        artwork: "https://example.com/custom-artwork.jpg",
        trackIds: ["100001", "100002", "100003"],
        createdAt: 1704067200000, // Jan 1, 2024
        updatedAt: 1704153600000  // Jan 2, 2024
    )

    static func makeCustomPlaylists(count: Int) -> [ConvexCustomPlaylist] {
        (0..<count).map { index in
            ConvexCustomPlaylist(
                playlistId: "custom-\(index)",
                name: "Custom Playlist \(index + 1)",
                description: nil,
                artwork: nil,
                trackIds: [],
                createdAt: 1704067200000 + index * 86400000,
                updatedAt: 1704067200000 + index * 86400000
            )
        }
    }
}

// MARK: - Track Comparison Helpers

extension SoundCloudTrack: Equatable {
    public static func == (lhs: SoundCloudTrack, rhs: SoundCloudTrack) -> Bool {
        lhs.id == rhs.id
    }
}

extension SoundCloudTrack: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension SoundCloudPlaylist: Equatable {
    public static func == (lhs: SoundCloudPlaylist, rhs: SoundCloudPlaylist) -> Bool {
        lhs.id == rhs.id
    }
}

extension SoundCloudUser: Equatable {
    public static func == (lhs: SoundCloudUser, rhs: SoundCloudUser) -> Bool {
        lhs.id == rhs.id
    }
}
