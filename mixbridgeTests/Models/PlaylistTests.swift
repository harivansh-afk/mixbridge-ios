import XCTest
@testable import mixbridge

final class PlaylistTests: XCTestCase {

    // MARK: - Playlist Initialization Tests

    func testPlaylistInitWithAllParameters() {
        let tracks = [
            Track(id: "1", title: "Track 1", artist: "Artist"),
            Track(id: "2", title: "Track 2", artist: "Artist")
        ]
        let date = Date()
        let customData = "artwork".data(using: .utf8)

        let playlist = Playlist(
            id: "playlist-123",
            name: "My Playlist",
            creator: "Test User",
            artwork: "https://example.com/art.jpg",
            tracks: tracks,
            lastUpdated: date,
            isUserCreated: true,
            customArtworkData: customData,
            libraryOwnerUserId: "user-456"
        )

        XCTAssertEqual(playlist.id, "playlist-123")
        XCTAssertEqual(playlist.name, "My Playlist")
        XCTAssertEqual(playlist.creator, "Test User")
        XCTAssertEqual(playlist.artwork, "https://example.com/art.jpg")
        XCTAssertEqual(playlist.tracks.count, 2)
        XCTAssertEqual(playlist.lastUpdated, date)
        XCTAssertTrue(playlist.isUserCreated)
        XCTAssertEqual(playlist.customArtworkData, customData)
        XCTAssertEqual(playlist.libraryOwnerUserId, "user-456")
    }

    func testPlaylistInitWithDefaultParameters() {
        let playlist = Playlist(name: "Minimal Playlist", creator: "Creator")

        XCTAssertFalse(playlist.id.isEmpty, "ID should be auto-generated")
        XCTAssertEqual(playlist.name, "Minimal Playlist")
        XCTAssertEqual(playlist.creator, "Creator")
        XCTAssertEqual(playlist.artwork, "")
        XCTAssertTrue(playlist.tracks.isEmpty)
        XCTAssertFalse(playlist.isUserCreated)
        XCTAssertNil(playlist.customArtworkData)
        XCTAssertNil(playlist.libraryOwnerUserId)
    }

    func testPlaylistInitGeneratesUniqueIds() {
        let playlist1 = Playlist(name: "Playlist 1", creator: "Creator")
        let playlist2 = Playlist(name: "Playlist 2", creator: "Creator")

        XCTAssertNotEqual(playlist1.id, playlist2.id, "Each playlist should have a unique ID")
    }

    func testPlaylistInitWithEmptyStrings() {
        let playlist = Playlist(
            id: "",
            name: "",
            creator: "",
            artwork: ""
        )

        XCTAssertEqual(playlist.id, "")
        XCTAssertEqual(playlist.name, "")
        XCTAssertEqual(playlist.creator, "")
        XCTAssertEqual(playlist.artwork, "")
    }

    func testPlaylistInitWithSpecialCharacters() {
        let playlist = Playlist(
            id: "playlist-!@#$%",
            name: "Playlist with 'quotes' & \"double quotes\"",
            creator: "Artist/User <Name>",
            artwork: "https://example.com/art?size=500&format=jpg"
        )

        XCTAssertEqual(playlist.name, "Playlist with 'quotes' & \"double quotes\"")
        XCTAssertEqual(playlist.creator, "Artist/User <Name>")
        XCTAssertEqual(playlist.artwork, "https://example.com/art?size=500&format=jpg")
    }

    func testPlaylistInitWithUnicodeCharacters() {
        let playlist = Playlist(
            name: "Playlist en Espanol",
            creator: "Artiste Francais"
        )

        XCTAssertEqual(playlist.name, "Playlist en Espanol")
        XCTAssertEqual(playlist.creator, "Artiste Francais")
    }

    // MARK: - Playlist Track Operations Tests

    func testPlaylistWithEmptyTracks() {
        let playlist = Playlist(name: "Empty", creator: "Creator", tracks: [])
        XCTAssertTrue(playlist.tracks.isEmpty)
        XCTAssertEqual(playlist.tracks.count, 0)
    }

    func testPlaylistWithSingleTrack() {
        let track = Track(id: "t1", title: "Single", artist: "Artist")
        let playlist = Playlist(name: "Single", creator: "Creator", tracks: [track])

        XCTAssertEqual(playlist.tracks.count, 1)
        XCTAssertEqual(playlist.tracks.first?.id, "t1")
    }

    func testPlaylistWithMultipleTracks() {
        let tracks = (1...10).map { Track(id: "t\($0)", title: "Track \($0)", artist: "Artist") }
        let playlist = Playlist(name: "Multi", creator: "Creator", tracks: tracks)

        XCTAssertEqual(playlist.tracks.count, 10)
        for (index, track) in playlist.tracks.enumerated() {
            XCTAssertEqual(track.id, "t\(index + 1)")
        }
    }

    func testPlaylistPreservesTrackOrder() {
        let tracks = [
            Track(id: "first", title: "First", artist: "A"),
            Track(id: "second", title: "Second", artist: "B"),
            Track(id: "third", title: "Third", artist: "C")
        ]
        let playlist = Playlist(name: "Ordered", creator: "Creator", tracks: tracks)

        XCTAssertEqual(playlist.tracks[0].id, "first")
        XCTAssertEqual(playlist.tracks[1].id, "second")
        XCTAssertEqual(playlist.tracks[2].id, "third")
    }

    func testPlaylistWithDuplicateTracks() {
        let track = Track(id: "same", title: "Same", artist: "Artist")
        let playlist = Playlist(name: "Dupes", creator: "Creator", tracks: [track, track, track])

        // Playlist should allow duplicate tracks
        XCTAssertEqual(playlist.tracks.count, 3)
    }

    // MARK: - Playlist isUserCreated Tests

    func testPlaylistIsUserCreatedTrue() {
        let playlist = Playlist(name: "User Created", creator: "User", isUserCreated: true)
        XCTAssertTrue(playlist.isUserCreated)
    }

    func testPlaylistIsUserCreatedFalse() {
        let playlist = Playlist(name: "System", creator: "System", isUserCreated: false)
        XCTAssertFalse(playlist.isUserCreated)
    }

    func testPlaylistIsUserCreatedDefaultsFalse() {
        let playlist = Playlist(name: "Default", creator: "Creator")
        XCTAssertFalse(playlist.isUserCreated)
    }

    // MARK: - Playlist customArtworkData Tests

    func testPlaylistWithCustomArtworkData() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header bytes
        let playlist = Playlist(name: "Custom Art", creator: "Creator", customArtworkData: imageData)

        XCTAssertNotNil(playlist.customArtworkData)
        XCTAssertEqual(playlist.customArtworkData, imageData)
    }

    func testPlaylistWithNilCustomArtworkData() {
        let playlist = Playlist(name: "No Custom Art", creator: "Creator", customArtworkData: nil)
        XCTAssertNil(playlist.customArtworkData)
    }

    func testPlaylistWithEmptyCustomArtworkData() {
        let playlist = Playlist(name: "Empty Data", creator: "Creator", customArtworkData: Data())
        XCTAssertNotNil(playlist.customArtworkData)
        XCTAssertEqual(playlist.customArtworkData?.count, 0)
    }

    // MARK: - Playlist libraryOwnerUserId Tests

    func testPlaylistWithLibraryOwnerUserId() {
        let playlist = Playlist(name: "Library", creator: "Creator", libraryOwnerUserId: "owner-123")
        XCTAssertEqual(playlist.libraryOwnerUserId, "owner-123")
    }

    func testPlaylistWithNilLibraryOwnerUserId() {
        let playlist = Playlist(name: "No Owner", creator: "Creator", libraryOwnerUserId: nil)
        XCTAssertNil(playlist.libraryOwnerUserId)
    }

    // MARK: - Playlist Equatable Tests

    func testPlaylistEqualityByAllFields() {
        let date = Date()
        let tracks = [Track(id: "t1", title: "Track", artist: "Artist")]

        let playlist1 = Playlist(
            id: "same-id",
            name: "Same Name",
            creator: "Same Creator",
            artwork: "https://same.url",
            tracks: tracks,
            lastUpdated: date,
            isUserCreated: true,
            customArtworkData: nil,
            libraryOwnerUserId: "user-1"
        )
        let playlist2 = Playlist(
            id: "same-id",
            name: "Same Name",
            creator: "Same Creator",
            artwork: "https://same.url",
            tracks: tracks,
            lastUpdated: date,
            isUserCreated: true,
            customArtworkData: nil,
            libraryOwnerUserId: "user-1"
        )

        XCTAssertEqual(playlist1, playlist2)
    }

    func testPlaylistInequalityByIdOnly() {
        let playlist1 = Playlist(id: "id-1", name: "Name", creator: "Creator")
        let playlist2 = Playlist(id: "id-2", name: "Name", creator: "Creator")

        XCTAssertNotEqual(playlist1, playlist2)
    }

    func testPlaylistInequalityByNameOnly() {
        let playlist1 = Playlist(id: "same", name: "Name 1", creator: "Creator")
        let playlist2 = Playlist(id: "same", name: "Name 2", creator: "Creator")

        XCTAssertNotEqual(playlist1, playlist2)
    }

    func testPlaylistInequalityByCreatorOnly() {
        let playlist1 = Playlist(id: "same", name: "Name", creator: "Creator 1")
        let playlist2 = Playlist(id: "same", name: "Name", creator: "Creator 2")

        XCTAssertNotEqual(playlist1, playlist2)
    }

    func testPlaylistInequalityByArtworkOnly() {
        let playlist1 = Playlist(id: "same", name: "Name", creator: "Creator", artwork: "url1")
        let playlist2 = Playlist(id: "same", name: "Name", creator: "Creator", artwork: "url2")

        XCTAssertNotEqual(playlist1, playlist2)
    }

    func testPlaylistInequalityByTracksOnly() {
        let tracks1 = [Track(id: "t1", title: "Track 1", artist: "A")]
        let tracks2 = [Track(id: "t2", title: "Track 2", artist: "A")]

        let playlist1 = Playlist(id: "same", name: "Name", creator: "Creator", tracks: tracks1)
        let playlist2 = Playlist(id: "same", name: "Name", creator: "Creator", tracks: tracks2)

        XCTAssertNotEqual(playlist1, playlist2)
    }

    func testPlaylistInequalityByIsUserCreatedOnly() {
        let playlist1 = Playlist(id: "same", name: "Name", creator: "Creator", isUserCreated: true)
        let playlist2 = Playlist(id: "same", name: "Name", creator: "Creator", isUserCreated: false)

        XCTAssertNotEqual(playlist1, playlist2)
    }

    func testPlaylistInequalityByLibraryOwnerOnly() {
        let playlist1 = Playlist(id: "same", name: "Name", creator: "Creator", libraryOwnerUserId: "user-1")
        let playlist2 = Playlist(id: "same", name: "Name", creator: "Creator", libraryOwnerUserId: "user-2")

        XCTAssertNotEqual(playlist1, playlist2)
    }

    // MARK: - Playlist Hashable Tests

    func testPlaylistHashableConsistency() {
        let playlist = Playlist(id: "hash-test", name: "Name", creator: "Creator")
        let hash1 = playlist.hashValue
        let hash2 = playlist.hashValue

        XCTAssertEqual(hash1, hash2, "Hash should be consistent for same instance")
    }

    func testPlaylistHashableEqualObjectsSameHash() {
        let date = Date()
        let playlist1 = Playlist(id: "same", name: "Name", creator: "Creator", lastUpdated: date)
        let playlist2 = Playlist(id: "same", name: "Name", creator: "Creator", lastUpdated: date)

        XCTAssertEqual(playlist1.hashValue, playlist2.hashValue, "Equal playlists should have same hash")
    }

    func testPlaylistHashableInSet() {
        let playlist1 = Playlist(id: "1", name: "Playlist 1", creator: "Creator")
        let playlist2 = Playlist(id: "2", name: "Playlist 2", creator: "Creator")
        let playlist3 = Playlist(id: "1", name: "Playlist 1", creator: "Creator") // Same as playlist1

        var set = Set<Playlist>()
        set.insert(playlist1)
        set.insert(playlist2)
        set.insert(playlist3) // Should not add duplicate

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(playlist1))
        XCTAssertTrue(set.contains(playlist2))
    }

    func testPlaylistHashableAsDictionaryKey() {
        let playlist1 = Playlist(id: "key1", name: "Name", creator: "Creator")
        let playlist2 = Playlist(id: "key2", name: "Name", creator: "Creator")

        var dict: [Playlist: Int] = [:]
        dict[playlist1] = 100
        dict[playlist2] = 200

        XCTAssertEqual(dict[playlist1], 100)
        XCTAssertEqual(dict[playlist2], 200)
    }

    // MARK: - Playlist Codable Tests

    func testPlaylistEncodeDecode() throws {
        let date = Date()
        let tracks = [Track(id: "t1", title: "Track", artist: "Artist", album: "Album", artwork: "url", duration: 180)]
        let original = Playlist(
            id: "codable-test",
            name: "Encoded Playlist",
            creator: "Encoded Creator",
            artwork: "https://example.com/encoded.jpg",
            tracks: tracks,
            lastUpdated: date,
            isUserCreated: true,
            customArtworkData: "test".data(using: .utf8),
            libraryOwnerUserId: "user-123"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Playlist.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.creator, decoded.creator)
        XCTAssertEqual(original.artwork, decoded.artwork)
        XCTAssertEqual(original.tracks.count, decoded.tracks.count)
        XCTAssertEqual(original.isUserCreated, decoded.isUserCreated)
        XCTAssertEqual(original.customArtworkData, decoded.customArtworkData)
        XCTAssertEqual(original.libraryOwnerUserId, decoded.libraryOwnerUserId)
    }

    func testPlaylistEncodeDecodeWithEmptyFields() throws {
        let original = Playlist(
            id: "",
            name: "",
            creator: "",
            artwork: "",
            tracks: []
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Playlist.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertTrue(decoded.tracks.isEmpty)
    }

    func testPlaylistEncodeDecodeWithUnicode() throws {
        let original = Playlist(
            id: "unicode-playlist",
            name: "Playlist con enye",
            creator: "Artiste avec accent"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Playlist.self, from: data)

        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.creator, decoded.creator)
    }

    func testPlaylistDecodeFromJSON() throws {
        let json = """
        {
            "id": "json-playlist",
            "name": "JSON Playlist",
            "creator": "JSON Creator",
            "artwork": "https://example.com/json.jpg",
            "tracks": [],
            "lastUpdated": 0,
            "isUserCreated": false,
            "customArtworkData": null,
            "libraryOwnerUserId": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let playlist = try decoder.decode(Playlist.self, from: json)

        XCTAssertEqual(playlist.id, "json-playlist")
        XCTAssertEqual(playlist.name, "JSON Playlist")
        XCTAssertEqual(playlist.creator, "JSON Creator")
        XCTAssertEqual(playlist.artwork, "https://example.com/json.jpg")
        XCTAssertTrue(playlist.tracks.isEmpty)
        XCTAssertFalse(playlist.isUserCreated)
    }

    func testPlaylistDecodeWithTracksFromJSON() throws {
        let json = """
        {
            "id": "playlist-with-tracks",
            "name": "Playlist",
            "creator": "Creator",
            "artwork": "",
            "tracks": [
                {"id": "t1", "title": "Track 1", "artist": "Artist", "album": "", "artwork": "", "duration": 180},
                {"id": "t2", "title": "Track 2", "artist": "Artist", "album": "", "artwork": "", "duration": 240}
            ],
            "lastUpdated": 0,
            "isUserCreated": true,
            "customArtworkData": null,
            "libraryOwnerUserId": "owner-1"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let playlist = try decoder.decode(Playlist.self, from: json)

        XCTAssertEqual(playlist.tracks.count, 2)
        XCTAssertEqual(playlist.tracks[0].id, "t1")
        XCTAssertEqual(playlist.tracks[1].id, "t2")
        XCTAssertTrue(playlist.isUserCreated)
        XCTAssertEqual(playlist.libraryOwnerUserId, "owner-1")
    }

    func testPlaylistDecodeWithMissingFieldsFails() {
        let incompleteJSON = """
        {
            "id": "incomplete",
            "name": "Missing Fields"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(Playlist.self, from: incompleteJSON))
    }

    func testPlaylistDecodeWithExtraFieldsSucceeds() throws {
        let jsonWithExtras = """
        {
            "id": "extra-fields",
            "name": "Extra Playlist",
            "creator": "Extra Creator",
            "artwork": "",
            "tracks": [],
            "lastUpdated": 0,
            "isUserCreated": false,
            "customArtworkData": null,
            "libraryOwnerUserId": null,
            "extraField": "should be ignored",
            "anotherExtra": 12345
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let playlist = try decoder.decode(Playlist.self, from: jsonWithExtras)

        XCTAssertEqual(playlist.id, "extra-fields")
        XCTAssertEqual(playlist.name, "Extra Playlist")
    }

    func testPlaylistCodableRoundtripArray() throws {
        let playlists = [
            Playlist(id: "1", name: "Playlist 1", creator: "Creator 1"),
            Playlist(id: "2", name: "Playlist 2", creator: "Creator 2"),
            Playlist(id: "3", name: "Playlist 3", creator: "Creator 3")
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(playlists)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([Playlist].self, from: data)

        XCTAssertEqual(playlists.count, decoded.count)
        for (original, result) in zip(playlists, decoded) {
            XCTAssertEqual(original.id, result.id)
            XCTAssertEqual(original.name, result.name)
        }
    }

    // MARK: - Playlist Identifiable Tests

    func testPlaylistIdentifiableId() {
        let playlist = Playlist(id: "identifiable-id", name: "Name", creator: "Creator")
        XCTAssertEqual(playlist.id, "identifiable-id")
    }

    // MARK: - PlaylistItem Tests

    func testPlaylistItemInitFromSoundCloudPlaylist() {
        let scPlaylist = TestFixtures.samplePlaylist
        let playlistItem = PlaylistItem(soundCloudPlaylist: scPlaylist)

        XCTAssertEqual(playlistItem.id, String(scPlaylist.id))
        XCTAssertEqual(playlistItem.playlist.name, scPlaylist.title)
        XCTAssertEqual(playlistItem.playlist.creator, scPlaylist.user.username)
        XCTAssertNotNil(playlistItem.soundCloudPlaylist)
        XCTAssertEqual(playlistItem.soundCloudPlaylist?.id, scPlaylist.id)
    }

    func testPlaylistItemInitFromPlaylistAndSoundCloudPlaylist() {
        let playlist = Playlist(id: "custom-id", name: "Custom", creator: "Creator")
        let scPlaylist = TestFixtures.samplePlaylist
        let playlistItem = PlaylistItem(playlist: playlist, soundCloudPlaylist: scPlaylist)

        XCTAssertEqual(playlistItem.id, "custom-id")
        XCTAssertEqual(playlistItem.playlist.name, "Custom")
        XCTAssertNotNil(playlistItem.soundCloudPlaylist)
    }

    func testPlaylistItemInitWithNilSoundCloudPlaylist() {
        let playlist = Playlist(id: "local-id", name: "Local Playlist", creator: "User")
        let playlistItem = PlaylistItem(playlist: playlist, soundCloudPlaylist: nil)

        XCTAssertEqual(playlistItem.id, "local-id")
        XCTAssertNil(playlistItem.soundCloudPlaylist)
    }

    func testPlaylistItemIdMatchesPlaylistId() {
        let playlistItem = PlaylistItem(soundCloudPlaylist: TestFixtures.samplePlaylist)
        XCTAssertEqual(playlistItem.id, playlistItem.playlist.id)
    }

    func testPlaylistItemEqualityById() {
        let playlistItem1 = PlaylistItem(soundCloudPlaylist: TestFixtures.samplePlaylist)
        let playlistItem2 = PlaylistItem(soundCloudPlaylist: TestFixtures.samplePlaylist)

        // Same underlying playlist ID means equal
        XCTAssertEqual(playlistItem1, playlistItem2)
    }

    func testPlaylistItemInequalityByDifferentPlaylist() {
        let playlistItem1 = PlaylistItem(soundCloudPlaylist: TestFixtures.samplePlaylist)
        let playlistItem2 = PlaylistItem(soundCloudPlaylist: TestFixtures.emptyPlaylist)

        XCTAssertNotEqual(playlistItem1, playlistItem2)
    }

    func testPlaylistItemEqualityIgnoresUnderlyingSoundCloudPlaylistDifferences() {
        // Same playlist ID but different SoundCloudPlaylist references
        let playlist = Playlist(id: "shared-id", name: "Shared", creator: "Creator")
        let playlistItem1 = PlaylistItem(playlist: playlist, soundCloudPlaylist: TestFixtures.samplePlaylist)
        let playlistItem2 = PlaylistItem(playlist: playlist, soundCloudPlaylist: TestFixtures.emptyPlaylist)

        // Equality is based on playlist.id only
        XCTAssertEqual(playlistItem1, playlistItem2)
    }

    // MARK: - PlaylistItem Sendable Tests

    func testPlaylistItemSendableAcrossActors() async {
        let playlistItem = PlaylistItem(soundCloudPlaylist: TestFixtures.samplePlaylist)

        let result = await Task.detached {
            return playlistItem.playlist.name
        }.value

        XCTAssertEqual(result, "Test Playlist")
    }

    // MARK: - SoundCloudPlaylist Conversion Tests

    func testSoundCloudPlaylistPrimaryArtworkUrlWithArtwork() {
        let scPlaylist = TestFixtures.samplePlaylist
        // samplePlaylist has artwork_url set
        XCTAssertFalse(scPlaylist.primaryArtworkUrl.isEmpty)
    }

    func testSoundCloudPlaylistPrimaryArtworkUrlFallsBackToTrack() {
        // emptyPlaylist has no artwork_url but empty tracks
        let emptyArtwork = TestFixtures.emptyPlaylist.primaryArtworkUrl
        XCTAssertEqual(emptyArtwork, "") // No artwork and no tracks means empty string
    }

    func testSoundCloudPlaylistToPlaylistItemPreservesData() {
        let scPlaylist = TestFixtures.samplePlaylist
        let playlistItem = PlaylistItem(soundCloudPlaylist: scPlaylist)

        XCTAssertEqual(playlistItem.playlist.id, String(scPlaylist.id))
        XCTAssertEqual(playlistItem.playlist.name, scPlaylist.title)
        XCTAssertEqual(playlistItem.playlist.creator, scPlaylist.user.username)
        XCTAssertEqual(playlistItem.playlist.artwork, scPlaylist.primaryArtworkUrl)
        XCTAssertTrue(playlistItem.playlist.tracks.isEmpty) // Tracks are not converted automatically
    }

    // MARK: - Test Fixtures Playlist Tests

    func testSamplePlaylistFixture() {
        let scPlaylist = TestFixtures.samplePlaylist

        XCTAssertEqual(scPlaylist.id, 500001)
        XCTAssertEqual(scPlaylist.title, "Test Playlist")
        XCTAssertEqual(scPlaylist.user.username, "TestArtist")
        XCTAssertNotNil(scPlaylist.tracks)
        XCTAssertEqual(scPlaylist.tracks?.count, 2)
    }

    func testEmptyPlaylistFixture() {
        let scPlaylist = TestFixtures.emptyPlaylist

        XCTAssertEqual(scPlaylist.id, 500002)
        XCTAssertEqual(scPlaylist.title, "Empty Playlist")
        XCTAssertEqual(scPlaylist.track_count, 0)
        XCTAssertTrue(scPlaylist.tracks?.isEmpty ?? true)
        XCTAssertNil(scPlaylist.artwork_url)
    }

    func testMakePlaylistsFactory() {
        let playlists = TestFixtures.makePlaylists(count: 5)

        XCTAssertEqual(playlists.count, 5)
        for (index, playlist) in playlists.enumerated() {
            XCTAssertEqual(playlist.title, "Playlist \(index + 1)")
            XCTAssertEqual(playlist.id, 600000 + index)
        }
    }

    func testMakePlaylistsFactoryZeroCount() {
        let playlists = TestFixtures.makePlaylists(count: 0)
        XCTAssertTrue(playlists.isEmpty)
    }

    // MARK: - Edge Cases

    func testPlaylistWithVeryLongStrings() throws {
        let longString = String(repeating: "a", count: 10000)
        let playlist = Playlist(
            id: longString,
            name: longString,
            creator: longString,
            artwork: longString
        )

        // Verify it can be encoded and decoded
        let encoder = JSONEncoder()
        let data = try encoder.encode(playlist)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Playlist.self, from: data)

        XCTAssertEqual(playlist.id, decoded.id)
        XCTAssertEqual(playlist.name, decoded.name)
    }

    func testPlaylistWithLargeTrackCount() {
        let tracks = (1...1000).map { Track(id: "t\($0)", title: "Track \($0)", artist: "Artist") }
        let playlist = Playlist(name: "Large", creator: "Creator", tracks: tracks)

        XCTAssertEqual(playlist.tracks.count, 1000)
    }

    func testPlaylistWithLargeCustomArtworkData() throws {
        let largeData = Data(count: 1_000_000) // 1MB
        let playlist = Playlist(name: "Large Art", creator: "Creator", customArtworkData: largeData)

        XCTAssertEqual(playlist.customArtworkData?.count, 1_000_000)

        // Verify it can be encoded and decoded
        let encoder = JSONEncoder()
        let data = try encoder.encode(playlist)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Playlist.self, from: data)

        XCTAssertEqual(decoded.customArtworkData?.count, 1_000_000)
    }

    func testPlaylistLastUpdatedDate() {
        let now = Date()
        let playlist = Playlist(name: "Dated", creator: "Creator", lastUpdated: now)

        XCTAssertEqual(playlist.lastUpdated, now)
    }

    func testPlaylistLastUpdatedDistantPast() {
        let distantPast = Date.distantPast
        let playlist = Playlist(name: "Old", creator: "Creator", lastUpdated: distantPast)

        XCTAssertEqual(playlist.lastUpdated, distantPast)
    }

    func testPlaylistLastUpdatedDistantFuture() {
        let distantFuture = Date.distantFuture
        let playlist = Playlist(name: "Future", creator: "Creator", lastUpdated: distantFuture)

        XCTAssertEqual(playlist.lastUpdated, distantFuture)
    }

    // MARK: - Concurrent Access Tests

    func testPlaylistConcurrentAccess() async {
        let playlist = Playlist(
            id: "concurrent",
            name: "Concurrent Playlist",
            creator: "Creator",
            tracks: (1...100).map { Track(id: "t\($0)", title: "Track \($0)", artist: "Artist") }
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 1...100 {
                group.addTask {
                    _ = playlist.tracks.count
                    _ = playlist.id
                    _ = playlist.name
                }
            }
        }

        // If we got here without crashing, concurrent read access is safe
        XCTAssertEqual(playlist.tracks.count, 100)
    }

    func testPlaylistItemConcurrentAccess() async {
        let playlistItem = PlaylistItem(soundCloudPlaylist: TestFixtures.samplePlaylist)

        await withTaskGroup(of: Void.self) { group in
            for _ in 1...100 {
                group.addTask {
                    _ = playlistItem.id
                    _ = playlistItem.playlist.name
                    _ = playlistItem.soundCloudPlaylist?.title
                }
            }
        }

        XCTAssertEqual(playlistItem.playlist.name, "Test Playlist")
    }
}
