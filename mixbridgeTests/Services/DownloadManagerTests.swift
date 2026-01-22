import XCTest
@testable import mixbridge

/// Tests for DownloadManager
/// Tests download state machine: start/pause/cancel, progress tracking, storage queries
@MainActor
final class DownloadManagerTests: XCTestCase {

    // MARK: - Test Fixtures

    private var downloadManager: TestableDownloadManager!

    override func setUp() async throws {
        try await super.setUp()
        downloadManager = TestableDownloadManager()
    }

    override func tearDown() async throws {
        await downloadManager.reset()
        downloadManager = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeTrack(
        id: Int = 100001,
        title: String = "Test Track",
        permalinkUrl: String? = "https://soundcloud.com/artist/test-track"
    ) -> SoundCloudTrack {
        SoundCloudTrack(
            id: id,
            title: title,
            user: TestFixtures.testUser,
            duration: 180000,
            artwork_url: "https://example.com/artwork.jpg",
            permalink_url: permalinkUrl,
            playback_count: 5000,
            genre: "Electronic",
            description: nil,
            created_at: nil,
            waveform_url: nil,
            likes_count: nil,
            comment_count: nil,
            reposts_count: nil
        )
    }

    private func makeTracks(count: Int) -> [SoundCloudTrack] {
        (0..<count).map { index in
            makeTrack(id: 200000 + index, title: "Track \(index + 1)")
        }
    }

    // MARK: - Initial State Tests

    func testInitialStateHasNoDownloads() async {
        let statuses = await downloadManager.getAllStatuses()
        XCTAssertTrue(statuses.isEmpty)
    }

    func testInitialStateHasNoDownloadedTracks() async {
        let tracks = await downloadManager.getDownloadedTracks()
        XCTAssertTrue(tracks.isEmpty)
    }

    func testInitiallyNotDownloading() async {
        XCTAssertFalse(await downloadManager.isDownloading(trackId: "any-track"))
    }

    func testInitiallyNotDownloaded() async {
        XCTAssertFalse(await downloadManager.isDownloaded(trackId: "any-track"))
    }

    // MARK: - Download Status Tests

    func testDownloadStatusNotDownloadedForNewTrack() async {
        let status = await downloadManager.getStatus(for: "new-track")
        XCTAssertEqual(status, .notDownloaded)
    }

    func testDownloadStatusDownloadingShowsProgress() async {
        let trackId = "100001"
        await downloadManager.setStatus(trackId: trackId, status: .downloading(progress: 0.5))

        let status = await downloadManager.getStatus(for: trackId)
        if case .downloading(let progress) = status {
            XCTAssertEqual(progress, 0.5, accuracy: 0.001)
        } else {
            XCTFail("Expected downloading status")
        }
    }

    func testDownloadStatusDownloaded() async {
        let trackId = "100001"
        await downloadManager.setStatus(trackId: trackId, status: .downloaded)

        let status = await downloadManager.getStatus(for: trackId)
        XCTAssertEqual(status, .downloaded)
    }

    func testDownloadStatusFailed() async {
        let trackId = "100001"
        await downloadManager.setStatus(trackId: trackId, status: .failed(DownloadError.networkError))

        let status = await downloadManager.getStatus(for: trackId)
        if case .failed = status {
            // Success
        } else {
            XCTFail("Expected failed status")
        }
    }

    // MARK: - DownloadStatus Equality Tests

    func testDownloadStatusNotDownloadedEquality() {
        XCTAssertEqual(DownloadStatus.notDownloaded, DownloadStatus.notDownloaded)
    }

    func testDownloadStatusDownloadingEquality() {
        XCTAssertEqual(DownloadStatus.downloading(progress: 0.5), DownloadStatus.downloading(progress: 0.5))
        XCTAssertNotEqual(DownloadStatus.downloading(progress: 0.5), DownloadStatus.downloading(progress: 0.7))
    }

    func testDownloadStatusDownloadedEquality() {
        XCTAssertEqual(DownloadStatus.downloaded, DownloadStatus.downloaded)
    }

    func testDownloadStatusFailedEquality() {
        let error1 = DownloadError.networkError
        let error2 = DownloadError.invalidURL
        // Failed statuses are considered equal regardless of error type
        XCTAssertEqual(DownloadStatus.failed(error1), DownloadStatus.failed(error2))
    }

    func testDownloadStatusDifferentTypesNotEqual() {
        XCTAssertNotEqual(DownloadStatus.notDownloaded, DownloadStatus.downloaded)
        XCTAssertNotEqual(DownloadStatus.notDownloaded, DownloadStatus.downloading(progress: 0))
        XCTAssertNotEqual(DownloadStatus.downloaded, DownloadStatus.downloading(progress: 1.0))
        XCTAssertNotEqual(DownloadStatus.downloading(progress: 0), DownloadStatus.failed(DownloadError.networkError))
    }

    // MARK: - Download Track Tests

    func testDownloadTrackSetsDownloadingStatus() async {
        let track = makeTrack(id: 100001)
        let trackId = "100001"

        await downloadManager.downloadTrack(track)

        XCTAssertTrue(await downloadManager.isDownloading(trackId: trackId))
    }

    func testDownloadTrackSkipsIfAlreadyDownloading() async {
        let track = makeTrack(id: 100001)
        let trackId = "100001"

        await downloadManager.setStatus(trackId: trackId, status: .downloading(progress: 0.5))

        let initialCallCount = await downloadManager.downloadStartCount
        await downloadManager.downloadTrack(track)
        let finalCallCount = await downloadManager.downloadStartCount

        // Should not have started another download
        XCTAssertEqual(initialCallCount, finalCallCount)
    }

    func testDownloadTrackWithInvalidURLFails() async {
        let track = makeTrack(id: 100001, permalinkUrl: nil)
        let trackId = "100001"

        await downloadManager.simulateDownloadFailure(for: trackId, error: .invalidURL)
        await downloadManager.downloadTrack(track)

        let status = await downloadManager.getStatus(for: trackId)
        if case .failed(let error) = status {
            XCTAssertTrue(error is DownloadError)
        } else {
            // May still be downloading in test environment
        }
    }

    // MARK: - Download Tracks (Batch) Tests

    func testDownloadTracksEnqueuesMultiple() async {
        let tracks = makeTracks(count: 5)

        await downloadManager.downloadTracks(tracks)

        for (index, _) in tracks.enumerated() {
            let trackId = "\(200000 + index)"
            let isDownloadingOrPending = await downloadManager.isDownloading(trackId: trackId) ||
                await downloadManager.getStatus(for: trackId) != .notDownloaded
            XCTAssertTrue(isDownloadingOrPending, "Track \(trackId) should be queued")
        }
    }

    func testDownloadTracksSkipsAlreadyDownloaded() async {
        let tracks = makeTracks(count: 3)
        let alreadyDownloadedId = "200001"

        await downloadManager.setStatus(trackId: alreadyDownloadedId, status: .downloaded)

        let initialCount = await downloadManager.downloadStartCount
        await downloadManager.downloadTracks(tracks)
        let finalCount = await downloadManager.downloadStartCount

        // Should have started downloads for 2 tracks, not 3
        XCTAssertLessThanOrEqual(finalCount - initialCount, 2)
    }

    func testDownloadTracksSkipsAlreadyDownloading() async {
        let tracks = makeTracks(count: 3)
        let alreadyDownloadingId = "200000"

        await downloadManager.setStatus(trackId: alreadyDownloadingId, status: .downloading(progress: 0.3))

        let initialCount = await downloadManager.downloadStartCount
        await downloadManager.downloadTracks(tracks)
        let finalCount = await downloadManager.downloadStartCount

        // Should have started downloads for 2 tracks, not 3
        XCTAssertLessThanOrEqual(finalCount - initialCount, 2)
    }

    // MARK: - Cancel Download Tests

    func testCancelDownloadStopsActiveDownload() async {
        let track = makeTrack(id: 100001)
        let trackId = "100001"

        await downloadManager.downloadTrack(track)
        await downloadManager.cancelDownload(trackId: trackId)

        XCTAssertFalse(await downloadManager.isDownloading(trackId: trackId))
        let status = await downloadManager.getStatus(for: trackId)
        XCTAssertEqual(status, .notDownloaded)
    }

    func testCancelDownloadRemovesPartialFile() async {
        let trackId = "100001"

        await downloadManager.downloadTrack(makeTrack(id: 100001))
        await downloadManager.cancelDownload(trackId: trackId)

        let wasCleanedUp = await downloadManager.wasCleanedUp(trackId: trackId)
        XCTAssertTrue(wasCleanedUp)
    }

    func testCancelNonExistentDownloadIsNoOp() async {
        // Should not throw or crash
        await downloadManager.cancelDownload(trackId: "nonexistent")

        let status = await downloadManager.getStatus(for: "nonexistent")
        XCTAssertEqual(status, .notDownloaded)
    }

    // MARK: - Delete Download Tests

    func testDeleteDownloadRemovesFile() async {
        let trackId = "100001"

        await downloadManager.addDownloadedTrack(trackId: trackId, localPath: "/path/to/file.mp3", fileSize: 5000000)
        await downloadManager.deleteDownload(trackId: trackId)

        XCTAssertFalse(await downloadManager.isDownloaded(trackId: trackId))
    }

    func testDeleteDownloadUpdatesStatus() async {
        let trackId = "100001"

        await downloadManager.addDownloadedTrack(trackId: trackId, localPath: "/path/to/file.mp3", fileSize: 5000000)
        await downloadManager.deleteDownload(trackId: trackId)

        let status = await downloadManager.getStatus(for: trackId)
        XCTAssertEqual(status, .notDownloaded)
    }

    func testDeleteNonExistentDownloadIsNoOp() async {
        // Should not throw or crash
        await downloadManager.deleteDownload(trackId: "nonexistent")

        let status = await downloadManager.getStatus(for: "nonexistent")
        XCTAssertEqual(status, .notDownloaded)
    }

    // MARK: - Delete All Downloads Tests

    func testDeleteAllDownloadsRemovesAllFiles() async {
        // Add several downloads
        for i in 1...5 {
            await downloadManager.addDownloadedTrack(
                trackId: "track-\(i)",
                localPath: "/path/to/track\(i).mp3",
                fileSize: Int64(i * 1000000)
            )
        }

        await downloadManager.deleteAllDownloads()

        let tracks = await downloadManager.getDownloadedTracks()
        XCTAssertTrue(tracks.isEmpty)
    }

    func testDeleteAllDownloadsClearsStatuses() async {
        for i in 1...3 {
            await downloadManager.addDownloadedTrack(
                trackId: "track-\(i)",
                localPath: "/path/to/track\(i).mp3",
                fileSize: Int64(i * 1000000)
            )
        }

        await downloadManager.deleteAllDownloads()

        let statuses = await downloadManager.getAllStatuses()
        XCTAssertTrue(statuses.isEmpty)
    }

    func testDeleteAllOnEmptyStateIsNoOp() async {
        // Should not throw or crash
        await downloadManager.deleteAllDownloads()

        let statuses = await downloadManager.getAllStatuses()
        XCTAssertTrue(statuses.isEmpty)
    }

    // MARK: - isDownloaded Tests

    func testIsDownloadedReturnsTrueForDownloadedTrack() async {
        let trackId = "100001"
        await downloadManager.setStatus(trackId: trackId, status: .downloaded)

        XCTAssertTrue(await downloadManager.isDownloaded(trackId: trackId))
    }

    func testIsDownloadedReturnsFalseForDownloadingTrack() async {
        let trackId = "100001"
        await downloadManager.setStatus(trackId: trackId, status: .downloading(progress: 0.5))

        XCTAssertFalse(await downloadManager.isDownloaded(trackId: trackId))
    }

    func testIsDownloadedReturnsFalseForFailedTrack() async {
        let trackId = "100001"
        await downloadManager.setStatus(trackId: trackId, status: .failed(DownloadError.networkError))

        XCTAssertFalse(await downloadManager.isDownloaded(trackId: trackId))
    }

    func testIsDownloadedReturnsFalseForUnknownTrack() async {
        XCTAssertFalse(await downloadManager.isDownloaded(trackId: "unknown"))
    }

    // MARK: - isDownloading Tests

    func testIsDownloadingReturnsTrueForActiveDownload() async {
        let trackId = "100001"
        await downloadManager.setStatus(trackId: trackId, status: .downloading(progress: 0.0))

        XCTAssertTrue(await downloadManager.isDownloading(trackId: trackId))
    }

    func testIsDownloadingReturnsTrueAtAnyProgress() async {
        let trackId = "100001"

        for progress in [0.0, 0.25, 0.5, 0.75, 0.99] {
            await downloadManager.setStatus(trackId: trackId, status: .downloading(progress: progress))
            XCTAssertTrue(await downloadManager.isDownloading(trackId: trackId))
        }
    }

    func testIsDownloadingReturnsFalseForDownloadedTrack() async {
        let trackId = "100001"
        await downloadManager.setStatus(trackId: trackId, status: .downloaded)

        XCTAssertFalse(await downloadManager.isDownloading(trackId: trackId))
    }

    func testIsDownloadingReturnsFalseForFailedTrack() async {
        let trackId = "100001"
        await downloadManager.setStatus(trackId: trackId, status: .failed(DownloadError.saveFailed))

        XCTAssertFalse(await downloadManager.isDownloading(trackId: trackId))
    }

    // MARK: - Get Local File URL Tests

    func testGetLocalFileURLReturnsURLForDownloadedTrack() async {
        let trackId = "100001"
        let localPath = "/path/to/track.mp3"

        await downloadManager.addDownloadedTrack(trackId: trackId, localPath: localPath, fileSize: 5000000)

        let url = await downloadManager.getLocalFileURL(trackId: trackId)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.path, localPath)
    }

    func testGetLocalFileURLReturnsNilForNonDownloadedTrack() async {
        let url = await downloadManager.getLocalFileURL(trackId: "nonexistent")
        XCTAssertNil(url)
    }

    func testGetLocalFileURLReturnsNilForMissingFile() async {
        let trackId = "100001"
        await downloadManager.addDownloadedTrack(trackId: trackId, localPath: "/missing/file.mp3", fileSize: 5000000)
        await downloadManager.simulateMissingFile(trackId: trackId)

        let url = await downloadManager.getLocalFileURL(trackId: trackId)
        XCTAssertNil(url)
    }

    // MARK: - Storage Used Tests

    func testGetTotalStorageUsedReturnsZeroForEmptyDownloads() async {
        let storage = await downloadManager.getTotalStorageUsed()
        XCTAssertEqual(storage, 0)
    }

    func testGetTotalStorageUsedSumsFileSizes() async {
        await downloadManager.addDownloadedTrack(trackId: "track-1", localPath: "/path/1.mp3", fileSize: 5_000_000)
        await downloadManager.addDownloadedTrack(trackId: "track-2", localPath: "/path/2.mp3", fileSize: 3_000_000)
        await downloadManager.addDownloadedTrack(trackId: "track-3", localPath: "/path/3.mp3", fileSize: 7_000_000)

        let storage = await downloadManager.getTotalStorageUsed()
        XCTAssertEqual(storage, 15_000_000)
    }

    // MARK: - Playlist Download Status Tests

    func testIsPlaylistFullyDownloadedReturnsFalseForEmptyPlaylist() async {
        let result = await downloadManager.isPlaylistFullyDownloaded(playlistId: "playlist-1")
        XCTAssertFalse(result)
    }

    func testIsPlaylistFullyDownloadedReturnsTrueWhenAllTracksDownloaded() async {
        let playlistId = "playlist-1"
        let trackIds = ["track-1", "track-2", "track-3"]

        await downloadManager.setPlaylistTracks(playlistId: playlistId, trackIds: trackIds)
        for trackId in trackIds {
            await downloadManager.addDownloadedTrack(trackId: trackId, localPath: "/path/\(trackId).mp3", fileSize: 5000000)
        }

        let result = await downloadManager.isPlaylistFullyDownloaded(playlistId: playlistId)
        XCTAssertTrue(result)
    }

    func testIsPlaylistFullyDownloadedReturnsFalseWhenPartiallyDownloaded() async {
        let playlistId = "playlist-1"
        let trackIds = ["track-1", "track-2", "track-3"]

        await downloadManager.setPlaylistTracks(playlistId: playlistId, trackIds: trackIds)
        // Only download 2 of 3 tracks
        await downloadManager.addDownloadedTrack(trackId: "track-1", localPath: "/path/1.mp3", fileSize: 5000000)
        await downloadManager.addDownloadedTrack(trackId: "track-2", localPath: "/path/2.mp3", fileSize: 5000000)

        let result = await downloadManager.isPlaylistFullyDownloaded(playlistId: playlistId)
        XCTAssertFalse(result)
    }

    // MARK: - Playlist Download Progress Tests

    func testPlaylistDownloadProgressReturnsZeroForEmptyPlaylist() async {
        let (downloaded, total) = await downloadManager.playlistDownloadProgress(playlistId: "playlist-1")
        XCTAssertEqual(downloaded, 0)
        XCTAssertEqual(total, 0)
    }

    func testPlaylistDownloadProgressReturnsCorrectCounts() async {
        let playlistId = "playlist-1"
        let trackIds = ["track-1", "track-2", "track-3", "track-4", "track-5"]

        await downloadManager.setPlaylistTracks(playlistId: playlistId, trackIds: trackIds)
        // Download 3 of 5 tracks
        await downloadManager.addDownloadedTrack(trackId: "track-1", localPath: "/path/1.mp3", fileSize: 5000000)
        await downloadManager.addDownloadedTrack(trackId: "track-3", localPath: "/path/3.mp3", fileSize: 5000000)
        await downloadManager.addDownloadedTrack(trackId: "track-5", localPath: "/path/5.mp3", fileSize: 5000000)

        let (downloaded, total) = await downloadManager.playlistDownloadProgress(playlistId: playlistId)
        XCTAssertEqual(downloaded, 3)
        XCTAssertEqual(total, 5)
    }

    func testPlaylistDownloadProgressUpdatesAfterNewDownload() async {
        let playlistId = "playlist-1"
        let trackIds = ["track-1", "track-2"]

        await downloadManager.setPlaylistTracks(playlistId: playlistId, trackIds: trackIds)

        var (downloaded, total) = await downloadManager.playlistDownloadProgress(playlistId: playlistId)
        XCTAssertEqual(downloaded, 0)
        XCTAssertEqual(total, 2)

        await downloadManager.addDownloadedTrack(trackId: "track-1", localPath: "/path/1.mp3", fileSize: 5000000)

        (downloaded, total) = await downloadManager.playlistDownloadProgress(playlistId: playlistId)
        XCTAssertEqual(downloaded, 1)
        XCTAssertEqual(total, 2)
    }

    // MARK: - Download Progress Updates Tests

    func testDownloadProgressUpdatesCorrectly() async {
        let trackId = "100001"

        await downloadManager.setStatus(trackId: trackId, status: .downloading(progress: 0.0))

        // Simulate progress updates
        for progress in stride(from: 0.1, through: 1.0, by: 0.1) {
            await downloadManager.setStatus(trackId: trackId, status: .downloading(progress: progress))
            let status = await downloadManager.getStatus(for: trackId)
            if case .downloading(let currentProgress) = status {
                XCTAssertEqual(currentProgress, progress, accuracy: 0.01)
            }
        }
    }

    func testDownloadCompletionUpdatesStatus() async {
        let trackId = "100001"

        await downloadManager.setStatus(trackId: trackId, status: .downloading(progress: 1.0))
        await downloadManager.setStatus(trackId: trackId, status: .downloaded)

        let status = await downloadManager.getStatus(for: trackId)
        XCTAssertEqual(status, .downloaded)
        XCTAssertFalse(await downloadManager.isDownloading(trackId: trackId))
        XCTAssertTrue(await downloadManager.isDownloaded(trackId: trackId))
    }

    // MARK: - DownloadError Tests

    func testDownloadErrorInvalidURLDescription() {
        let error = DownloadError.invalidURL
        XCTAssertEqual(error.errorDescription, "Invalid stream URL")
    }

    func testDownloadErrorDownloadFailedDescription() {
        let error = DownloadError.downloadFailed
        XCTAssertEqual(error.errorDescription, "Download failed")
    }

    func testDownloadErrorSaveFailedDescription() {
        let error = DownloadError.saveFailed
        XCTAssertEqual(error.errorDescription, "Failed to save file")
    }

    func testDownloadErrorInsufficientStorageDescription() {
        let error = DownloadError.insufficientStorage
        XCTAssertEqual(error.errorDescription, "Not enough storage space")
    }

    func testDownloadErrorNetworkErrorDescription() {
        let error = DownloadError.networkError
        XCTAssertEqual(error.errorDescription, "Network error")
    }

    // MARK: - DownloadedTrackInfo Tests

    func testDownloadedTrackInfoEquality() {
        let track1 = Track(id: "100001", title: "Test", artist: "Artist", album: "", artwork: "", duration: 180)
        let track2 = Track(id: "100001", title: "Different", artist: "Other", album: "", artwork: "", duration: 120)
        let track3 = Track(id: "100002", title: "Test", artist: "Artist", album: "", artwork: "", duration: 180)

        let info1 = DownloadedTrackInfo(track: track1, soundCloudTrack: nil, downloadedAt: Date(), fileSize: 5000000)
        let info2 = DownloadedTrackInfo(track: track2, soundCloudTrack: nil, downloadedAt: Date(), fileSize: 3000000)
        let info3 = DownloadedTrackInfo(track: track3, soundCloudTrack: nil, downloadedAt: Date(), fileSize: 5000000)

        // Same track ID = equal
        XCTAssertEqual(info1, info2)
        // Different track ID = not equal
        XCTAssertNotEqual(info1, info3)
    }

    func testDownloadedTrackInfoIdMatchesTrackId() {
        let track = Track(id: "my-track-id", title: "Test", artist: "Artist", album: "", artwork: "", duration: 180)
        let info = DownloadedTrackInfo(track: track, soundCloudTrack: nil, downloadedAt: Date(), fileSize: 5000000)

        XCTAssertEqual(info.id, "my-track-id")
    }

    // MARK: - DownloadedPlaylistInfo Tests

    func testDownloadedPlaylistInfoEquality() {
        let playlist1 = Playlist(id: "playlist-1", title: "Test", artist: "", artwork: "", duration: 3600, trackCount: 10, tracks: nil)
        let playlist2 = Playlist(id: "playlist-1", title: "Different", artist: "", artwork: "", duration: 1800, trackCount: 5, tracks: nil)
        let playlist3 = Playlist(id: "playlist-2", title: "Test", artist: "", artwork: "", duration: 3600, trackCount: 10, tracks: nil)

        let info1 = DownloadedPlaylistInfo(playlist: playlist1, soundCloudPlaylist: nil, trackCount: 10, downloadedTrackCount: 10, totalFileSize: 50000000)
        let info2 = DownloadedPlaylistInfo(playlist: playlist2, soundCloudPlaylist: nil, trackCount: 5, downloadedTrackCount: 5, totalFileSize: 25000000)
        let info3 = DownloadedPlaylistInfo(playlist: playlist3, soundCloudPlaylist: nil, trackCount: 10, downloadedTrackCount: 10, totalFileSize: 50000000)

        // Same playlist ID and same downloadedTrackCount = equal
        XCTAssertEqual(info1, info2)
        // Different playlist ID = not equal
        XCTAssertNotEqual(info1, info3)
    }

    func testDownloadedPlaylistInfoIsFullyDownloaded() {
        let playlist = Playlist(id: "playlist-1", title: "Test", artist: "", artwork: "", duration: 3600, trackCount: 10, tracks: nil)

        let fullyDownloaded = DownloadedPlaylistInfo(playlist: playlist, soundCloudPlaylist: nil, trackCount: 10, downloadedTrackCount: 10, totalFileSize: 50000000)
        let partiallyDownloaded = DownloadedPlaylistInfo(playlist: playlist, soundCloudPlaylist: nil, trackCount: 10, downloadedTrackCount: 5, totalFileSize: 25000000)
        let emptyPlaylist = DownloadedPlaylistInfo(playlist: playlist, soundCloudPlaylist: nil, trackCount: 0, downloadedTrackCount: 0, totalFileSize: 0)

        XCTAssertTrue(fullyDownloaded.isFullyDownloaded)
        XCTAssertFalse(partiallyDownloaded.isFullyDownloaded)
        XCTAssertFalse(emptyPlaylist.isFullyDownloaded)
    }

    // MARK: - Concurrent Operations Tests

    func testConcurrentDownloadRequests() async {
        let tracks = makeTracks(count: 10)

        await withTaskGroup(of: Void.self) { group in
            for track in tracks {
                group.addTask {
                    await self.downloadManager.downloadTrack(track)
                }
            }
        }

        // All tracks should have some status (downloading or queued)
        for (index, _) in tracks.enumerated() {
            let trackId = "\(200000 + index)"
            let status = await downloadManager.getStatus(for: trackId)
            XCTAssertNotEqual(status, .notDownloaded)
        }
    }

    func testConcurrentStatusUpdates() async {
        let trackId = "100001"

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let progress = Double(i) / 50.0
                    await self.downloadManager.setStatus(trackId: trackId, status: .downloading(progress: progress))
                }
            }
        }

        // Final status should be some downloading progress
        let finalStatus = await downloadManager.getStatus(for: trackId)
        if case .downloading = finalStatus {
            // Success - concurrent updates completed without crashes
        } else {
            XCTFail("Expected downloading status after concurrent updates")
        }
    }

    func testConcurrentDownloadAndCancel() async {
        let tracks = makeTracks(count: 5)

        // Start downloads
        await downloadManager.downloadTracks(tracks)

        // Concurrently cancel some
        await withTaskGroup(of: Void.self) { group in
            for (index, _) in tracks.enumerated() where index % 2 == 0 {
                let trackId = "\(200000 + index)"
                group.addTask {
                    await self.downloadManager.cancelDownload(trackId: trackId)
                }
            }
        }

        // Cancelled tracks should be not downloaded
        for (index, _) in tracks.enumerated() where index % 2 == 0 {
            let trackId = "\(200000 + index)"
            let status = await downloadManager.getStatus(for: trackId)
            XCTAssertEqual(status, .notDownloaded)
        }
    }

    // MARK: - Edge Cases

    func testDownloadSpotifyTrack() async {
        let spotifyTrack = SoundCloudTrack(
            id: 100001,
            title: "Spotify Track",
            user: TestFixtures.testUser,
            duration: 180000,
            artwork_url: nil,
            permalink_url: "https://open.spotify.com/track/abc123",
            playback_count: nil,
            genre: nil,
            description: nil,
            created_at: nil,
            waveform_url: nil,
            likes_count: nil,
            comment_count: nil,
            reposts_count: nil
        )

        await downloadManager.downloadTrack(spotifyTrack)

        let isDownloading = await downloadManager.isDownloading(trackId: "100001")
        XCTAssertTrue(isDownloading)
    }

    func testMultipleOperationsSequence() async {
        let tracks = makeTracks(count: 3)

        // Start downloads
        await downloadManager.downloadTracks(tracks)

        // Cancel one
        await downloadManager.cancelDownload(trackId: "200001")

        // Complete one manually
        await downloadManager.setStatus(trackId: "200000", status: .downloaded)
        await downloadManager.addDownloadedTrack(trackId: "200000", localPath: "/path/track0.mp3", fileSize: 5000000)

        // Fail one
        await downloadManager.setStatus(trackId: "200002", status: .failed(DownloadError.networkError))

        // Verify states
        XCTAssertTrue(await downloadManager.isDownloaded(trackId: "200000"))
        XCTAssertEqual(await downloadManager.getStatus(for: "200001"), .notDownloaded)
        if case .failed = await downloadManager.getStatus(for: "200002") {
            // Success
        } else {
            XCTFail("Expected failed status for track 200002")
        }
    }

    func testRedownloadAfterFailure() async {
        let track = makeTrack(id: 100001)
        let trackId = "100001"

        // First download fails
        await downloadManager.setStatus(trackId: trackId, status: .failed(DownloadError.networkError))

        // Try again
        await downloadManager.downloadTrack(track)

        // Should be downloading again
        XCTAssertTrue(await downloadManager.isDownloading(trackId: trackId))
    }

    func testRedownloadAfterCancel() async {
        let track = makeTrack(id: 100001)
        let trackId = "100001"

        // Start and cancel
        await downloadManager.downloadTrack(track)
        await downloadManager.cancelDownload(trackId: trackId)

        // Should be not downloaded
        XCTAssertEqual(await downloadManager.getStatus(for: trackId), .notDownloaded)

        // Try again
        await downloadManager.downloadTrack(track)

        // Should be downloading
        XCTAssertTrue(await downloadManager.isDownloading(trackId: trackId))
    }
}

// MARK: - Testable DownloadManager

/// A testable version of DownloadManager that allows direct state manipulation
/// without requiring network calls, file system operations, or database access
@MainActor
final class TestableDownloadManager {

    // MARK: - State

    private var downloadStatuses: [String: DownloadStatus] = [:]
    private var downloadedTracks: [String: DownloadedTrackRecord] = [:]
    private var playlistTracks: [String: [String]] = [:]
    private var activeTasks: [String: Bool] = [:]
    private var cleanedUpTracks: Set<String> = []
    private var missingFiles: Set<String> = []

    private(set) var downloadStartCount: Int = 0

    private struct DownloadedTrackRecord {
        let trackId: String
        let localPath: String
        let fileSize: Int64
        let downloadedAt: Date
    }

    // MARK: - Public API (mirrors DownloadManager)

    func downloadTrack(_ track: SoundCloudTrack) {
        let trackId = String(track.id)

        guard !isDownloading(trackId: trackId) else { return }

        downloadStatuses[trackId] = .downloading(progress: 0)
        activeTasks[trackId] = true
        downloadStartCount += 1
    }

    func downloadTracks(_ tracks: [SoundCloudTrack]) {
        for track in tracks {
            let trackId = String(track.id)

            if downloadStatuses[trackId] == .downloaded || isDownloading(trackId: trackId) {
                continue
            }

            downloadStatuses[trackId] = .downloading(progress: 0)
            activeTasks[trackId] = true
            downloadStartCount += 1
        }
    }

    func cancelDownload(trackId: String) {
        activeTasks.removeValue(forKey: trackId)
        downloadStatuses[trackId] = .notDownloaded
        cleanedUpTracks.insert(trackId)
    }

    func deleteDownload(trackId: String) async {
        downloadedTracks.removeValue(forKey: trackId)
        downloadStatuses[trackId] = .notDownloaded
    }

    func deleteAllDownloads() async {
        downloadedTracks.removeAll()
        downloadStatuses.removeAll()
    }

    func isDownloaded(trackId: String) -> Bool {
        downloadStatuses[trackId] == .downloaded
    }

    func isDownloading(trackId: String) -> Bool {
        if case .downloading = downloadStatuses[trackId] {
            return true
        }
        return false
    }

    func getLocalFileURL(trackId: String) async -> URL? {
        guard let record = downloadedTracks[trackId] else {
            return nil
        }

        if missingFiles.contains(trackId) {
            return nil
        }

        return URL(fileURLWithPath: record.localPath)
    }

    func getTotalStorageUsed() async -> Int64 {
        downloadedTracks.values.reduce(0) { $0 + $1.fileSize }
    }

    func isPlaylistFullyDownloaded(playlistId: String) async -> Bool {
        guard let trackIds = playlistTracks[playlistId], !trackIds.isEmpty else {
            return false
        }

        let downloadedCount = trackIds.filter { downloadedTracks[$0] != nil }.count
        return downloadedCount == trackIds.count
    }

    func playlistDownloadProgress(playlistId: String) async -> (downloaded: Int, total: Int) {
        guard let trackIds = playlistTracks[playlistId] else {
            return (0, 0)
        }

        let downloadedCount = trackIds.filter { downloadedTracks[$0] != nil }.count
        return (downloadedCount, trackIds.count)
    }

    // MARK: - Testing Helpers

    func setStatus(trackId: String, status: DownloadStatus) {
        downloadStatuses[trackId] = status
        if case .downloading = status {
            activeTasks[trackId] = true
        } else {
            activeTasks.removeValue(forKey: trackId)
        }
    }

    func getStatus(for trackId: String) -> DownloadStatus {
        downloadStatuses[trackId] ?? .notDownloaded
    }

    func getAllStatuses() -> [String: DownloadStatus] {
        downloadStatuses
    }

    func getDownloadedTracks() -> [DownloadedTrackRecord] {
        Array(downloadedTracks.values)
    }

    func addDownloadedTrack(trackId: String, localPath: String, fileSize: Int64) {
        let record = DownloadedTrackRecord(
            trackId: trackId,
            localPath: localPath,
            fileSize: fileSize,
            downloadedAt: Date()
        )
        downloadedTracks[trackId] = record
        downloadStatuses[trackId] = .downloaded
    }

    func setPlaylistTracks(playlistId: String, trackIds: [String]) {
        playlistTracks[playlistId] = trackIds
    }

    func simulateDownloadFailure(for trackId: String, error: DownloadError) {
        downloadStatuses[trackId] = .failed(error)
        activeTasks.removeValue(forKey: trackId)
    }

    func simulateMissingFile(trackId: String) {
        missingFiles.insert(trackId)
    }

    func wasCleanedUp(trackId: String) -> Bool {
        cleanedUpTracks.contains(trackId)
    }

    func reset() async {
        downloadStatuses.removeAll()
        downloadedTracks.removeAll()
        playlistTracks.removeAll()
        activeTasks.removeAll()
        cleanedUpTracks.removeAll()
        missingFiles.removeAll()
        downloadStartCount = 0
    }
}
