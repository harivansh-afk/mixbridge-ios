import XCTest
@testable import mixbridge

final class TrackTests: XCTestCase {

    // MARK: - Track Initialization Tests

    func testTrackInitWithAllParameters() {
        let track = Track(
            id: "track-123",
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            artwork: "https://example.com/art.jpg",
            duration: 180.5
        )

        XCTAssertEqual(track.id, "track-123")
        XCTAssertEqual(track.title, "Test Song")
        XCTAssertEqual(track.artist, "Test Artist")
        XCTAssertEqual(track.album, "Test Album")
        XCTAssertEqual(track.artwork, "https://example.com/art.jpg")
        XCTAssertEqual(track.duration, 180.5)
    }

    func testTrackInitWithDefaultParameters() {
        let track = Track(title: "Minimal Track", artist: "Minimal Artist")

        XCTAssertFalse(track.id.isEmpty, "ID should be auto-generated")
        XCTAssertEqual(track.title, "Minimal Track")
        XCTAssertEqual(track.artist, "Minimal Artist")
        XCTAssertEqual(track.album, "")
        XCTAssertEqual(track.artwork, "")
        XCTAssertEqual(track.duration, 0.0)
    }

    func testTrackInitGeneratesUniqueIds() {
        let track1 = Track(title: "Track 1", artist: "Artist")
        let track2 = Track(title: "Track 2", artist: "Artist")

        XCTAssertNotEqual(track1.id, track2.id, "Each track should have a unique ID")
    }

    func testTrackInitWithEmptyStrings() {
        let track = Track(
            id: "",
            title: "",
            artist: "",
            album: "",
            artwork: "",
            duration: 0.0
        )

        XCTAssertEqual(track.id, "")
        XCTAssertEqual(track.title, "")
        XCTAssertEqual(track.artist, "")
        XCTAssertEqual(track.album, "")
        XCTAssertEqual(track.artwork, "")
        XCTAssertEqual(track.duration, 0.0)
    }

    func testTrackInitWithSpecialCharacters() {
        let track = Track(
            id: "track-!@#$%",
            title: "Song with 'quotes' & \"double quotes\"",
            artist: "Artist/Band <Name>",
            album: "Album: The Sequel",
            artwork: "https://example.com/art?size=500&format=jpg",
            duration: 245.7
        )

        XCTAssertEqual(track.title, "Song with 'quotes' & \"double quotes\"")
        XCTAssertEqual(track.artist, "Artist/Band <Name>")
        XCTAssertEqual(track.album, "Album: The Sequel")
    }

    func testTrackInitWithUnicodeCharacters() {
        let track = Track(
            title: "Cancion en Espanol",
            artist: "Artiste Francais",
            album: "nihongo no arubamu"
        )

        XCTAssertEqual(track.title, "Cancion en Espanol")
        XCTAssertEqual(track.artist, "Artiste Francais")
        XCTAssertEqual(track.album, "nihongo no arubamu")
    }

    func testTrackInitWithNegativeDuration() {
        let track = Track(title: "Negative", artist: "Test", duration: -10.0)
        XCTAssertEqual(track.duration, -10.0, "Track should accept negative duration (validation is caller's responsibility)")
    }

    func testTrackInitWithVeryLargeDuration() {
        let track = Track(title: "Long", artist: "Test", duration: 86400.0) // 24 hours
        XCTAssertEqual(track.duration, 86400.0)
    }

    // MARK: - Track Equatable Tests

    func testTrackEqualityByAllFields() {
        let track1 = Track(
            id: "same-id",
            title: "Same Title",
            artist: "Same Artist",
            album: "Same Album",
            artwork: "https://same.url",
            duration: 180.0
        )
        let track2 = Track(
            id: "same-id",
            title: "Same Title",
            artist: "Same Artist",
            album: "Same Album",
            artwork: "https://same.url",
            duration: 180.0
        )

        XCTAssertEqual(track1, track2)
    }

    func testTrackInequalityByIdOnly() {
        let track1 = Track(id: "id-1", title: "Title", artist: "Artist")
        let track2 = Track(id: "id-2", title: "Title", artist: "Artist")

        XCTAssertNotEqual(track1, track2)
    }

    func testTrackInequalityByTitleOnly() {
        let track1 = Track(id: "same", title: "Title 1", artist: "Artist")
        let track2 = Track(id: "same", title: "Title 2", artist: "Artist")

        XCTAssertNotEqual(track1, track2)
    }

    func testTrackInequalityByArtistOnly() {
        let track1 = Track(id: "same", title: "Title", artist: "Artist 1")
        let track2 = Track(id: "same", title: "Title", artist: "Artist 2")

        XCTAssertNotEqual(track1, track2)
    }

    func testTrackInequalityByAlbumOnly() {
        let track1 = Track(id: "same", title: "Title", artist: "Artist", album: "Album 1")
        let track2 = Track(id: "same", title: "Title", artist: "Artist", album: "Album 2")

        XCTAssertNotEqual(track1, track2)
    }

    func testTrackInequalityByArtworkOnly() {
        let track1 = Track(id: "same", title: "Title", artist: "Artist", artwork: "url1")
        let track2 = Track(id: "same", title: "Title", artist: "Artist", artwork: "url2")

        XCTAssertNotEqual(track1, track2)
    }

    func testTrackInequalityByDurationOnly() {
        let track1 = Track(id: "same", title: "Title", artist: "Artist", duration: 180.0)
        let track2 = Track(id: "same", title: "Title", artist: "Artist", duration: 181.0)

        XCTAssertNotEqual(track1, track2)
    }

    // MARK: - Track Hashable Tests

    func testTrackHashableConsistency() {
        let track = Track(id: "hash-test", title: "Title", artist: "Artist")
        let hash1 = track.hashValue
        let hash2 = track.hashValue

        XCTAssertEqual(hash1, hash2, "Hash should be consistent for same instance")
    }

    func testTrackHashableEqualObjectsSameHash() {
        let track1 = Track(id: "same", title: "Title", artist: "Artist", album: "Album", artwork: "url", duration: 180)
        let track2 = Track(id: "same", title: "Title", artist: "Artist", album: "Album", artwork: "url", duration: 180)

        XCTAssertEqual(track1.hashValue, track2.hashValue, "Equal tracks should have same hash")
    }

    func testTrackHashableInSet() {
        let track1 = Track(id: "1", title: "Title 1", artist: "Artist")
        let track2 = Track(id: "2", title: "Title 2", artist: "Artist")
        let track3 = Track(id: "1", title: "Title 1", artist: "Artist") // Same as track1

        var set = Set<Track>()
        set.insert(track1)
        set.insert(track2)
        set.insert(track3) // Should not add duplicate

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(track1))
        XCTAssertTrue(set.contains(track2))
    }

    func testTrackHashableAsDictionaryKey() {
        let track1 = Track(id: "key1", title: "Title", artist: "Artist")
        let track2 = Track(id: "key2", title: "Title", artist: "Artist")

        var dict: [Track: Int] = [:]
        dict[track1] = 100
        dict[track2] = 200

        XCTAssertEqual(dict[track1], 100)
        XCTAssertEqual(dict[track2], 200)
    }

    // MARK: - Track Codable Tests

    func testTrackEncodeDecode() throws {
        let original = Track(
            id: "codable-test",
            title: "Encoded Song",
            artist: "Encoded Artist",
            album: "Encoded Album",
            artwork: "https://example.com/encoded.jpg",
            duration: 245.5
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Track.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testTrackEncodeDecodeWithEmptyFields() throws {
        let original = Track(
            id: "",
            title: "",
            artist: "",
            album: "",
            artwork: "",
            duration: 0.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Track.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testTrackEncodeDecodeWithUnicode() throws {
        let original = Track(
            id: "unicode-track",
            title: "Titulo con enye",
            artist: "Artiste avec accent",
            album: "Nihongo Album",
            artwork: "",
            duration: 180.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Track.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testTrackDecodeFromJSON() throws {
        let json = """
        {
            "id": "json-track",
            "title": "JSON Song",
            "artist": "JSON Artist",
            "album": "JSON Album",
            "artwork": "https://example.com/json.jpg",
            "duration": 300.25
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let track = try decoder.decode(Track.self, from: json)

        XCTAssertEqual(track.id, "json-track")
        XCTAssertEqual(track.title, "JSON Song")
        XCTAssertEqual(track.artist, "JSON Artist")
        XCTAssertEqual(track.album, "JSON Album")
        XCTAssertEqual(track.artwork, "https://example.com/json.jpg")
        XCTAssertEqual(track.duration, 300.25)
    }

    func testTrackDecodeWithMissingFieldsFails() {
        let incompleteJSON = """
        {
            "id": "incomplete",
            "title": "Missing Fields"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(Track.self, from: incompleteJSON))
    }

    func testTrackDecodeWithExtraFieldsSucceeds() throws {
        let jsonWithExtras = """
        {
            "id": "extra-fields",
            "title": "Extra Song",
            "artist": "Extra Artist",
            "album": "Extra Album",
            "artwork": "",
            "duration": 180.0,
            "extraField": "should be ignored",
            "anotherExtra": 12345
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let track = try decoder.decode(Track.self, from: jsonWithExtras)

        XCTAssertEqual(track.id, "extra-fields")
        XCTAssertEqual(track.title, "Extra Song")
    }

    func testTrackEncodeProducesValidJSON() throws {
        let track = Track(
            id: "json-valid",
            title: "Valid Song",
            artist: "Valid Artist",
            album: "Valid Album",
            artwork: "https://example.com/valid.jpg",
            duration: 200.0
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(track)
        let jsonString = String(data: data, encoding: .utf8)

        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("\"id\" : \"json-valid\""))
        XCTAssertTrue(jsonString!.contains("\"title\" : \"Valid Song\""))
    }

    func testTrackCodableRoundtripArray() throws {
        let tracks = [
            Track(id: "1", title: "Song 1", artist: "Artist 1", duration: 100),
            Track(id: "2", title: "Song 2", artist: "Artist 2", duration: 200),
            Track(id: "3", title: "Song 3", artist: "Artist 3", duration: 300)
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(tracks)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([Track].self, from: data)

        XCTAssertEqual(tracks.count, decoded.count)
        for (original, result) in zip(tracks, decoded) {
            XCTAssertEqual(original, result)
        }
    }

    // MARK: - Track Identifiable Tests

    func testTrackIdentifiableId() {
        let track = Track(id: "identifiable-id", title: "Title", artist: "Artist")
        XCTAssertEqual(track.id, "identifiable-id")
    }

    // MARK: - Track Sendable Tests

    func testTrackSendableAcrossActors() async {
        let track = Track(id: "sendable", title: "Sendable Song", artist: "Artist")

        // Verify track can be passed across actor boundaries
        let result = await Task.detached {
            return track.title
        }.value

        XCTAssertEqual(result, "Sendable Song")
    }

    // MARK: - Track Sample Data Tests

    func testSampleTracksNotEmpty() {
        XCTAssertFalse(Track.sampleTracks.isEmpty)
    }

    func testSampleTracksHaveValidData() {
        for track in Track.sampleTracks {
            XCTAssertFalse(track.id.isEmpty, "Sample track should have non-empty ID")
            XCTAssertFalse(track.title.isEmpty, "Sample track should have non-empty title")
            XCTAssertFalse(track.artist.isEmpty, "Sample track should have non-empty artist")
        }
    }

    func testSampleTracksAreUnique() {
        let ids = Track.sampleTracks.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "Sample tracks should have unique IDs")
    }

    // MARK: - TrackItem Tests

    func testTrackItemInitFromSoundCloudTrack() {
        let scTrack = TestFixtures.sampleTrack
        let trackItem = TrackItem(soundCloudTrack: scTrack)

        XCTAssertEqual(trackItem.id, String(scTrack.id))
        XCTAssertEqual(trackItem.track.title, scTrack.title)
        XCTAssertEqual(trackItem.track.artist, scTrack.user.username)
        XCTAssertEqual(trackItem.soundCloudTrack.id, scTrack.id)
        XCTAssertEqual(trackItem.playCount, 1)
        XCTAssertEqual(trackItem.lastPlayedPosition, 0)
        XCTAssertEqual(trackItem.listenedPercentage, 0)
    }

    func testTrackItemInitWithPlayHistory() {
        let scTrack = TestFixtures.sampleTrack
        let trackItem = TrackItem(
            soundCloudTrack: scTrack,
            playCount: 5,
            lastPlayedPosition: 90.5,
            listenedPercentage: 0.75
        )

        XCTAssertEqual(trackItem.playCount, 5)
        XCTAssertEqual(trackItem.lastPlayedPosition, 90.5)
        XCTAssertEqual(trackItem.listenedPercentage, 0.75)
    }

    func testTrackItemIdMatchesTrackId() {
        let trackItem = TrackItem(soundCloudTrack: TestFixtures.sampleTrack)
        XCTAssertEqual(trackItem.id, trackItem.track.id)
    }

    func testTrackItemEqualityById() {
        let trackItem1 = TrackItem(soundCloudTrack: TestFixtures.sampleTrack)
        let trackItem2 = TrackItem(soundCloudTrack: TestFixtures.sampleTrack)

        // Same underlying track ID means equal
        XCTAssertEqual(trackItem1, trackItem2)
    }

    func testTrackItemInequalityByDifferentTrack() {
        let trackItem1 = TrackItem(soundCloudTrack: TestFixtures.sampleTrack)
        let trackItem2 = TrackItem(soundCloudTrack: TestFixtures.secondaryTrack)

        XCTAssertNotEqual(trackItem1, trackItem2)
    }

    func testTrackItemEqualityIgnoresPlayHistory() {
        let trackItem1 = TrackItem(
            soundCloudTrack: TestFixtures.sampleTrack,
            playCount: 1,
            lastPlayedPosition: 0,
            listenedPercentage: 0
        )
        let trackItem2 = TrackItem(
            soundCloudTrack: TestFixtures.sampleTrack,
            playCount: 100,
            lastPlayedPosition: 500.0,
            listenedPercentage: 1.0
        )

        // Equality is based on track.id only
        XCTAssertEqual(trackItem1, trackItem2)
    }

    func testTrackItemPlayCountMutability() {
        var trackItem = TrackItem(soundCloudTrack: TestFixtures.sampleTrack)
        XCTAssertEqual(trackItem.playCount, 1)

        trackItem.playCount = 10
        XCTAssertEqual(trackItem.playCount, 10)
    }

    func testTrackItemLastPlayedPositionMutability() {
        var trackItem = TrackItem(soundCloudTrack: TestFixtures.sampleTrack)
        trackItem.lastPlayedPosition = 120.5
        XCTAssertEqual(trackItem.lastPlayedPosition, 120.5)
    }

    func testTrackItemListenedPercentageMutability() {
        var trackItem = TrackItem(soundCloudTrack: TestFixtures.sampleTrack)
        trackItem.listenedPercentage = 0.5
        XCTAssertEqual(trackItem.listenedPercentage, 0.5)
    }

    // MARK: - SoundCloudTrack to Track Conversion Tests

    func testSoundCloudTrackToTrackConversion() {
        let scTrack = TestFixtures.sampleTrack
        let track = scTrack.toTrack()

        XCTAssertEqual(track.id, String(scTrack.id))
        XCTAssertEqual(track.title, scTrack.title)
        XCTAssertEqual(track.artist, scTrack.user.username)
        XCTAssertEqual(track.album, scTrack.genre ?? "")
    }

    func testSoundCloudTrackToTrackDurationConversion() {
        let scTrack = TestFixtures.sampleTrack
        let track = scTrack.toTrack()

        // Duration should be converted from milliseconds to seconds
        let expectedDuration = Double(scTrack.duration) / 1000.0
        XCTAssertEqual(track.duration, expectedDuration, accuracy: 0.001)
    }

    func testSoundCloudTrackToTrackArtworkUpgrade() {
        // Create track with -large in artwork URL
        let scUser = SoundCloudUser(
            id: 1,
            username: "Artist",
            avatar_url: nil,
            permalink_url: nil,
            followers_count: nil,
            followings_count: nil
        )
        let scTrack = SoundCloudTrack(
            id: 999,
            title: "Test",
            user: scUser,
            duration: 60000,
            artwork_url: "https://example.com/artwork-large.jpg",
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

        let track = scTrack.toTrack()

        // Artwork URL should be upgraded to t500x500
        XCTAssertEqual(track.artwork, "https://example.com/artwork-t500x500.jpg")
    }

    func testSoundCloudTrackToTrackWithNilArtworkUsesAvatar() {
        let scUser = SoundCloudUser(
            id: 1,
            username: "Artist",
            avatar_url: "https://example.com/avatar-large.jpg",
            permalink_url: nil,
            followers_count: nil,
            followings_count: nil
        )
        let scTrack = SoundCloudTrack(
            id: 999,
            title: "Test",
            user: scUser,
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

        let track = scTrack.toTrack()

        // Should use user avatar when track artwork is nil
        XCTAssertEqual(track.artwork, "https://example.com/avatar-t500x500.jpg")
    }

    func testSoundCloudTrackToTrackWithNilGenre() {
        let track = TestFixtures.minimalTrack.toTrack()
        XCTAssertEqual(track.album, "", "Album should be empty string when genre is nil")
    }

    // MARK: - Array Extension Tests

    func testSoundCloudTrackArrayToTrackItems() {
        let scTracks = [TestFixtures.sampleTrack, TestFixtures.secondaryTrack]
        let trackItems = scTracks.toTrackItems()

        XCTAssertEqual(trackItems.count, 2)
        XCTAssertEqual(trackItems[0].track.id, String(TestFixtures.sampleTrack.id))
        XCTAssertEqual(trackItems[1].track.id, String(TestFixtures.secondaryTrack.id))
    }

    func testEmptySoundCloudTrackArrayToTrackItems() {
        let scTracks: [SoundCloudTrack] = []
        let trackItems = scTracks.toTrackItems()

        XCTAssertTrue(trackItems.isEmpty)
    }

    func testSoundCloudTrackArrayToTracks() {
        let scTracks = [TestFixtures.sampleTrack, TestFixtures.secondaryTrack]
        let tracks = scTracks.toTracks()

        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks[0].id, String(TestFixtures.sampleTrack.id))
        XCTAssertEqual(tracks[1].id, String(TestFixtures.secondaryTrack.id))
    }

    func testEmptySoundCloudTrackArrayToTracks() {
        let scTracks: [SoundCloudTrack] = []
        let tracks = scTracks.toTracks()

        XCTAssertTrue(tracks.isEmpty)
    }

    // MARK: - Edge Cases

    func testTrackWithVeryLongStrings() throws {
        let longString = String(repeating: "a", count: 10000)
        let track = Track(
            id: longString,
            title: longString,
            artist: longString,
            album: longString,
            artwork: longString,
            duration: 180.0
        )

        // Verify it can be encoded and decoded
        let encoder = JSONEncoder()
        let data = try encoder.encode(track)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Track.self, from: data)

        XCTAssertEqual(track, decoded)
    }

    func testTrackWithZeroDuration() {
        let track = Track(title: "Zero", artist: "Test", duration: 0.0)
        XCTAssertEqual(track.duration, 0.0)
    }

    func testTrackWithFractionalDuration() {
        let track = Track(title: "Fractional", artist: "Test", duration: 123.456789)
        XCTAssertEqual(track.duration, 123.456789)
    }

    func testTrackItemWithMinimalSoundCloudTrack() {
        let trackItem = TrackItem(soundCloudTrack: TestFixtures.minimalTrack)

        XCTAssertEqual(trackItem.track.title, "Minimal Track")
        XCTAssertEqual(trackItem.track.album, "") // nil genre becomes empty string
    }

    func testMakeTracksFactory() {
        let tracks = TestFixtures.makeTracks(count: 5)

        XCTAssertEqual(tracks.count, 5)
        for (index, track) in tracks.enumerated() {
            XCTAssertEqual(track.title, "Track \(index + 1)")
        }
    }

    func testMakeTracksFactoryZeroCount() {
        let tracks = TestFixtures.makeTracks(count: 0)
        XCTAssertTrue(tracks.isEmpty)
    }

    func testTrackItemsPreserveOrder() {
        let scTracks = TestFixtures.makeTracks(count: 10)
        let trackItems = scTracks.toTrackItems()

        for (index, item) in trackItems.enumerated() {
            XCTAssertEqual(item.track.title, "Track \(index + 1)")
        }
    }
}
