//
//  DownloadManager.swift
//  mixbridge
//
//  Manages offline track downloads using yt-dlp backend for signed URLs.
//  Downloads MP3/M4A files directly without needing OAuth headers.
//

import Foundation
import Combine
import MixBridgeDB

/// Download status for a track
enum DownloadStatus: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(Error)

    static func == (lhs: DownloadStatus, rhs: DownloadStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded): return true
        case (.downloading(let p1), .downloading(let p2)): return p1 == p2
        case (.downloaded, .downloaded): return true
        case (.failed, .failed): return true
        default: return false
        }
    }
}

/// Manages track downloads for offline playback
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloadStatuses: [String: DownloadStatus] = [:]
    @Published private(set) var downloadedTracks: [DownloadedTrackInfo] = []
    @Published private(set) var downloadedPlaylists: [DownloadedPlaylistInfo] = []
    @Published private(set) var isLoading: Bool = false

    private let db = MixBridgeDB.shared

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    private init() {
        Task {
            await loadDownloadedTracks()
        }
    }

    // MARK: - Public API

    /// Download a track for offline playback
    func downloadTrack(_ track: SoundCloudTrack) {
        let trackId = String(track.id)

        guard !isDownloading(trackId: trackId) else { return }

        downloadStatuses[trackId] = .downloading(progress: 0)

        let task = Task {
            await performDownload(track: track)
        }
        downloadTasks[trackId] = task
    }

    /// Download multiple tracks with throttled concurrency
    func downloadTracks(_ tracks: [SoundCloudTrack]) {
        let maxConcurrent = 3

        Task {
            await withTaskGroup(of: Void.self) { group in
                var activeCount = 0
                var trackIndex = 0

                while trackIndex < tracks.count {
                    while activeCount < maxConcurrent && trackIndex < tracks.count {
                        let track = tracks[trackIndex]
                        let trackId = String(track.id)

                        if downloadStatuses[trackId] == .downloaded || isDownloading(trackId: trackId) {
                            trackIndex += 1
                            continue
                        }

                        downloadStatuses[trackId] = .downloading(progress: 0)
                        
                        let capturedTrack = track
                        let capturedTrackId = trackId
                        let taskForGroup = Task {
                            await self.performDownload(track: capturedTrack)
                        }
                        downloadTasks[capturedTrackId] = taskForGroup

                        group.addTask {
                            _ = await taskForGroup.value
                        }

                        activeCount += 1
                        trackIndex += 1
                    }

                    if activeCount >= maxConcurrent {
                        await group.next()
                        activeCount -= 1
                    }
                }

                await group.waitForAll()
            }
        }
    }

    /// Cancel a download in progress
    func cancelDownload(trackId: String) {
        downloadTasks[trackId]?.cancel()
        downloadTasks.removeValue(forKey: trackId)
        downloadStatuses[trackId] = .notDownloaded
        
        // Clean up any partial files (could be .mp3 or .m4a)
        Task {
            if let downloadsDir = try? getDownloadsDirectory() {
                try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent("\(trackId).mp3"))
                try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent("\(trackId).m4a"))
            }
        }
    }

    /// Delete a downloaded track
    func deleteDownload(trackId: String) async {
        do {
            if let downloaded = try await getDownloadedTrack(trackId: trackId) {
                let fileURL = URL(fileURLWithPath: downloaded.localPath)
                try? FileManager.default.removeItem(at: fileURL)
            }

            _ = try await db.writer.write { db in
                try DownloadedTrack.deleteOne(db, key: trackId)
            }

            downloadStatuses[trackId] = .notDownloaded
            await loadDownloadedTracks()
        } catch {
            logError(.downloads, "Failed to delete download for \(trackId): \(error)")
        }
    }

    /// Delete all downloaded tracks
    func deleteAllDownloads() async {
        do {
            let downloads = try await db.reader.read { db in
                try DownloadedTrack.fetchAll(db)
            }

            // Delete files first
            for download in downloads {
                let fileURL = URL(fileURLWithPath: download.localPath)
                try? FileManager.default.removeItem(at: fileURL)
            }

            // Then clear database
            _ = try await db.writer.write { db in
                try DownloadedTrack.deleteAll(db)
            }

            downloadStatuses.removeAll()
            downloadedTracks.removeAll()
        } catch {
            logError(.downloads, "Failed to delete all downloads: \(error)")
        }
    }

    /// Check if a track is downloaded
    func isDownloaded(trackId: String) -> Bool {
        downloadStatuses[trackId] == .downloaded
    }
    
    /// Check if a track is currently downloading (any progress)
    func isDownloading(trackId: String) -> Bool {
        if case .downloading = downloadStatuses[trackId] {
            return true
        }
        return false
    }

    /// Get the local file URL for a downloaded track
    func getLocalFileURL(trackId: String) async -> URL? {
        guard let downloaded = try? await getDownloadedTrack(trackId: trackId) else {
            return nil
        }
        let url = URL(fileURLWithPath: downloaded.localPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // File missing - clean up stale database entry
            Task {
                await cleanupStaleDownload(trackId: trackId)
            }
            return nil
        }
        return url
    }

    /// Get total storage used by downloads
    func getTotalStorageUsed() async -> Int64 {
        do {
            return try await db.reader.read { db in
                try DownloadedTrack.select(sum(DownloadedTrack.Columns.fileSize)).fetchOne(db) ?? 0
            }
        } catch {
            return 0
        }
    }

    /// Check if all tracks in a playlist are downloaded
    func isPlaylistFullyDownloaded(playlistId: String) async -> Bool {
        do {
            let (trackCount, downloadedCount) = try await db.reader.read { db -> (Int, Int) in
                // Get all track IDs in the playlist
                let trackIds = try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlistId)
                    .select(PlaylistTrack.Columns.trackId)
                    .fetchAll(db)
                    .map { $0.trackId }

                guard !trackIds.isEmpty else { return (0, 0) }

                // Count how many are downloaded
                let downloadedCount = try DownloadedTrack
                    .filter(keys: trackIds)
                    .fetchCount(db)

                return (trackIds.count, downloadedCount)
            }

            return trackCount > 0 && downloadedCount == trackCount
        } catch {
            logError(.downloads, "Failed to check playlist download status: \(error)")
            return false
        }
    }

    /// Get download progress for a playlist (downloaded / total tracks)
    func playlistDownloadProgress(playlistId: String) async -> (downloaded: Int, total: Int) {
        do {
            return try await db.reader.read { db in
                let trackIds = try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlistId)
                    .select(PlaylistTrack.Columns.trackId)
                    .fetchAll(db)
                    .map { $0.trackId }

                guard !trackIds.isEmpty else { return (0, 0) }

                let downloadedCount = try DownloadedTrack
                    .filter(keys: trackIds)
                    .fetchCount(db)

                return (downloadedCount, trackIds.count)
            }
        } catch {
            return (0, 0)
        }
    }

    // MARK: - Private
    
    private func cleanupStaleDownload(trackId: String) async {
        _ = try? await db.writer.write { db in
            try DownloadedTrack.deleteOne(db, key: trackId)
        }
        downloadStatuses[trackId] = .notDownloaded
    }

    private func performDownload(track: SoundCloudTrack) async {
        let trackId = String(track.id)

        do {
            logInfo(.downloads, "Starting download for: \(track.title)")

            // Build SoundCloud URL from track permalink_url
            guard let soundcloudUrl = track.permalink_url else {
                throw DownloadError.invalidURL
            }
            
            // Check disk space before downloading (require at least 50MB free)
            let downloadsDir = try getDownloadsDirectory()
            if let freeSpace = try? URL(fileURLWithPath: NSHomeDirectory())
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage,
               freeSpace < 50_000_000 {
                throw DownloadError.insufficientStorage
            }
            
            // Get signed stream URL via Railway yt-dlp API directly (no OAuth headers needed!)
            let ytdlpResponse = try await getStreamURL(soundcloudUrl: soundcloudUrl)

            guard let streamURL = URL(string: ytdlpResponse.streamURL) else {
                throw DownloadError.invalidURL
            }

            // Determine file extension based on format
            let fileExtension = ytdlpResponse.format.contains("mp3") ? "mp3" : "m4a"
            let destinationURL = downloadsDir.appendingPathComponent("\(trackId).\(fileExtension)")

            // Remove any existing files (both .mp3 and .m4a)
            try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent("\(trackId).mp3"))
            try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent("\(trackId).m4a"))

            if ytdlpResponse.isDirect {
                // Direct HTTP URL - download file directly
                logInfo(.downloads, "Downloading via direct HTTP URL (format: \(ytdlpResponse.format))")
                try await downloadDirectFile(from: streamURL, to: destinationURL, trackId: trackId)
            } else {
                // HLS-only track - use server-side download endpoint (returns MP3)
                logInfo(.downloads, "Downloading via server (HLS track)")
                let mp3Destination = downloadsDir.appendingPathComponent("\(trackId).mp3")
                try await downloadViaServer(soundcloudUrl: soundcloudUrl, to: mp3Destination, trackId: trackId)
            }

            // Find the actual downloaded file (could be .mp3 or .m4a)
            let mp3Path = downloadsDir.appendingPathComponent("\(trackId).mp3")
            let m4aPath = downloadsDir.appendingPathComponent("\(trackId).m4a")
            let actualPath = FileManager.default.fileExists(atPath: mp3Path.path) ? mp3Path :
                             FileManager.default.fileExists(atPath: m4aPath.path) ? m4aPath : nil

            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: mp3Path)
                try? FileManager.default.removeItem(at: m4aPath)
                downloadStatuses[trackId] = .notDownloaded
                downloadTasks.removeValue(forKey: trackId)
                return
            }

            // Verify file exists and get size
            guard let finalPath = actualPath, FileManager.default.fileExists(atPath: finalPath.path) else {
                throw DownloadError.saveFailed
            }
            
            let attrs = try FileManager.default.attributesOfItem(atPath: finalPath.path)
            guard let fileSize = attrs[.size] as? Int64, fileSize > 0 else {
                try? FileManager.default.removeItem(at: finalPath)
                throw DownloadError.saveFailed
            }

            // Persist track metadata if needed
            try await persistTrackIfNeeded(track)

            // Save download record
            let downloadRecord = DownloadedTrack(
                trackId: trackId,
                localPath: finalPath.path,
                fileSize: fileSize,
                downloadedAt: Date()
            )

            _ = try await db.writer.write { db in
                try downloadRecord.save(db)
            }

            downloadStatuses[trackId] = .downloaded
            downloadTasks.removeValue(forKey: trackId)
            await loadDownloadedTracks()

            logInfo(.downloads, "Download complete: \(track.title) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))")
        } catch {
            logError(.downloads, "Download failed for \(track.title): \(error)")
            
            // Clean up partial files on failure (could be .mp3 or .m4a)
            if let downloadsDir = try? getDownloadsDirectory() {
                try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent("\(trackId).mp3"))
                try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent("\(trackId).m4a"))
            }
            
            downloadStatuses[trackId] = .failed(error)
            downloadTasks.removeValue(forKey: trackId)
        }
    }

    private static let ytdlpAPIURL = "https://exemplary-mindfulness-production.up.railway.app"

    /// Get stream URL directly from Railway yt-dlp API
    private func getStreamURL(soundcloudUrl: String) async throws -> StreamURLResponse {
        // Validate it's a SoundCloud URL
        guard soundcloudUrl.contains("soundcloud.com") else {
            throw DownloadError.invalidURL
        }

        guard let url = URL(string: "\(Self.ytdlpAPIURL)/stream") else {
            throw DownloadError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": soundcloudUrl])
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            logError(.downloads, "Stream URL request failed: HTTP \(httpResponse.statusCode)")
            throw DownloadError.networkError
        }

        let decoded = try JSONDecoder().decode(StreamURLResponse.self, from: data)
        logInfo(.downloads, "Extracted \(decoded.format) stream for download")
        return decoded
    }

    private func downloadDirectFile(from url: URL, to destinationURL: URL, trackId: String) async throws {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DownloadError.networkError
        }
        
        // Move downloaded file to destination
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        logInfo(.downloads, "Direct download complete: \(destinationURL.lastPathComponent)")
    }
    
    private func downloadViaServer(soundcloudUrl: String, to destinationURL: URL, trackId: String) async throws {
        guard let url = URL(string: "\(Self.ytdlpAPIURL)/download") else {
            throw DownloadError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": soundcloudUrl])
        request.timeoutInterval = 120 // HLS download can take time
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            logError(.downloads, "Server download failed: HTTP \(httpResponse.statusCode)")
            throw DownloadError.networkError
        }
        
        guard !data.isEmpty else {
            throw DownloadError.saveFailed
        }
        
        // Write MP3 data directly (server already converts to MP3)
        try data.write(to: destinationURL)
        
        logInfo(.downloads, "Server download complete: \(destinationURL.lastPathComponent)")
    }
    
    private func getDownloadsDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let downloadsURL = appSupportURL.appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        return downloadsURL
    }

    private func getDownloadedTrack(trackId: String) async throws -> DownloadedTrack? {
        try await db.reader.read { db in
            try DownloadedTrack.fetchOne(db, key: trackId)
        }
    }

    private func persistTrackIfNeeded(_ scTrack: SoundCloudTrack) async throws {
        let trackId = String(scTrack.id)
        let exists = try await db.reader.read { db in
            try PersistedTrack.exists(db, key: trackId)
        }

        if !exists {
            let persisted = PersistedTrack(from: scTrack)
            _ = try await db.writer.write { db in
                try persisted.save(db)
            }
        }
    }

    private func loadDownloadedTracks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let downloads = try await db.reader.read { db in
                try DownloadedTrack
                    .order(DownloadedTrack.Columns.downloadedAt.desc)
                    .fetchAll(db)
            }

            // Verify files exist and clean up stale entries
            var validDownloads: [DownloadedTrack] = []
            var staleTrackIds: [String] = []

            for download in downloads {
                if FileManager.default.fileExists(atPath: download.localPath) {
                    validDownloads.append(download)
                    downloadStatuses[download.trackId] = .downloaded
                } else {
                    staleTrackIds.append(download.trackId)
                    downloadStatuses[download.trackId] = .notDownloaded
                }
            }

            // Clean up stale database entries
            if !staleTrackIds.isEmpty {
                _ = try? await db.writer.write { db in
                    try DownloadedTrack.filter(keys: staleTrackIds).deleteAll(db)
                }
                logInfo(.downloads, "Cleaned up \(staleTrackIds.count) stale download entries")
            }

            let trackIds = validDownloads.map { $0.trackId }
            let tracks = try await db.reader.read { db in
                try PersistedTrack.filter(keys: trackIds).fetchAll(db)
            }

            let trackMap = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })

            downloadedTracks = validDownloads.compactMap { download in
                guard let track = trackMap[download.trackId] else { return nil }
                return DownloadedTrackInfo(
                    track: track.toTrack(),
                    soundCloudTrack: track.soundCloudTrack,
                    downloadedAt: download.downloadedAt,
                    fileSize: download.fileSize
                )
            }

            // Also load downloaded playlists
            await loadDownloadedPlaylists()
        } catch {
            logError(.downloads, "Failed to load downloaded tracks: \(error)")
        }
    }

    private func loadDownloadedPlaylists() async {
        do {
            // Get all downloaded track IDs
            let downloadedTrackIds = Set(downloadedTracks.map { $0.track.id })

            // Find playlists where all tracks are downloaded
            let playlistsWithDownloads = try await db.reader.read { db -> [DownloadedPlaylistInfo] in
                // Get all playlists that have tracks
                let playlists = try PersistedPlaylist.fetchAll(db)

                return try playlists.compactMap { playlist -> DownloadedPlaylistInfo? in
                    // Get track IDs for this playlist
                    let playlistTrackIds = try PlaylistTrack
                        .filter(PlaylistTrack.Columns.playlistId == playlist.id)
                        .order(PlaylistTrack.Columns.position)
                        .fetchAll(db)
                        .map { $0.trackId }

                    guard !playlistTrackIds.isEmpty else { return nil }

                    // Count downloaded tracks
                    let downloadedCount = playlistTrackIds.filter { downloadedTrackIds.contains($0) }.count

                    // Only include if fully downloaded
                    guard downloadedCount == playlistTrackIds.count else { return nil }

                    // Calculate total file size for downloaded tracks in this playlist
                    let totalSize = try DownloadedTrack
                        .filter(keys: playlistTrackIds)
                        .select(sum(DownloadedTrack.Columns.fileSize))
                        .fetchOne(db) ?? 0

                    return DownloadedPlaylistInfo(
                        playlist: playlist.toPlaylist(),
                        soundCloudPlaylist: playlist.soundCloudPlaylist,
                        trackCount: playlistTrackIds.count,
                        downloadedTrackCount: downloadedCount,
                        totalFileSize: Int64(totalSize)
                    )
                }
            }

            downloadedPlaylists = playlistsWithDownloads
            logInfo(.downloads, "Found \(downloadedPlaylists.count) fully downloaded playlists")
        } catch {
            logError(.downloads, "Failed to load downloaded playlists: \(error)")
        }
    }
}

// MARK: - Supporting Types

/// Response from Railway yt-dlp API /stream endpoint
private struct StreamURLResponse: Codable {
    let streamURL: String
    let format: String
    let isDirect: Bool

    enum CodingKeys: String, CodingKey {
        case streamURL = "stream_url"
        case format
        case isDirect = "is_direct"
    }
}

struct DownloadedTrackInfo: Identifiable, Equatable {
    let track: Track
    let soundCloudTrack: SoundCloudTrack?
    let downloadedAt: Date
    let fileSize: Int64

    var id: String { track.id }

    static func == (lhs: DownloadedTrackInfo, rhs: DownloadedTrackInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct DownloadedPlaylistInfo: Identifiable, Equatable {
    let playlist: Playlist
    let soundCloudPlaylist: SoundCloudPlaylist?
    let trackCount: Int
    let downloadedTrackCount: Int
    let totalFileSize: Int64

    var id: String { playlist.id }

    var isFullyDownloaded: Bool {
        trackCount > 0 && downloadedTrackCount == trackCount
    }

    static func == (lhs: DownloadedPlaylistInfo, rhs: DownloadedPlaylistInfo) -> Bool {
        lhs.id == rhs.id && lhs.downloadedTrackCount == rhs.downloadedTrackCount
    }
}

enum DownloadError: LocalizedError {
    case invalidURL
    case downloadFailed
    case saveFailed
    case insufficientStorage
    case networkError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid stream URL"
        case .downloadFailed: return "Download failed"
        case .saveFailed: return "Failed to save file"
        case .insufficientStorage: return "Not enough storage space"
        case .networkError: return "Network error"
        }
    }
}
