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

        let pending = tracks.filter { track in
            let trackId = String(track.id)
            return downloadStatuses[trackId] != .downloaded && !isDownloading(trackId: trackId)
        }

        // Mark all as queued up front so the UI reflects the batch immediately
        for track in pending {
            downloadStatuses[String(track.id)] = .downloading(progress: 0)
        }

        Task {
            await withTaskGroup(of: Void.self) { group in
                var nextIndex = 0

                while nextIndex < min(maxConcurrent, pending.count) {
                    let track = pending[nextIndex]
                    nextIndex += 1
                    let task = await self.registerDownloadTask(for: track)
                    group.addTask { _ = await task.value }
                }

                // Start one new download for each one that finishes
                while await group.next() != nil {
                    guard nextIndex < pending.count else { continue }
                    let track = pending[nextIndex]
                    nextIndex += 1
                    let task = await self.registerDownloadTask(for: track)
                    group.addTask { _ = await task.value }
                }
            }
        }
    }

    /// Create and track the download task for a track (main-actor state)
    private func registerDownloadTask(for track: SoundCloudTrack) -> Task<Void, Never> {
        let task = Task {
            await self.performDownload(track: track)
        }
        downloadTasks[String(track.id)] = task
        return task
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
        if let resolvedPath = resolveLocalPath(for: downloaded) {
            if resolvedPath != downloaded.localPath {
                await updateDownloadedTrackPath(trackId: trackId, localPath: resolvedPath)
            }
            return URL(fileURLWithPath: resolvedPath)
        }

        // File missing - clean up stale database entry
        Task {
            await cleanupStaleDownload(trackId: trackId)
        }
        return nil
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

    private func resolveLocalPath(for download: DownloadedTrack) -> String? {
        if FileManager.default.fileExists(atPath: download.localPath) {
            return download.localPath
        }

        guard let downloadsDir = try? getDownloadsDirectory() else {
            return nil
        }

        if !download.localPath.hasPrefix("/") {
            let candidate = downloadsDir.appendingPathComponent(download.localPath).path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        let mp3Path = downloadsDir.appendingPathComponent("\(download.trackId).mp3").path
        if FileManager.default.fileExists(atPath: mp3Path) {
            return mp3Path
        }

        let m4aPath = downloadsDir.appendingPathComponent("\(download.trackId).m4a").path
        if FileManager.default.fileExists(atPath: m4aPath) {
            return m4aPath
        }

        return nil
    }

    private func updateDownloadedTrackPath(trackId: String, localPath: String) async {
        _ = try? await db.writer.write { db in
            try DownloadedTrack
                .filter(key: trackId)
                .updateAll(db, [DownloadedTrack.Columns.localPath.set(to: localPath)])
        }
    }

    private func performDownload(track: SoundCloudTrack) async {
        let trackId = String(track.id)
        let permalinkUrl = track.permalink_url

        do {
            logInfo(.downloads, "Starting download for: \(track.title)")

            guard let permalinkUrl else {
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

            // Remove any existing files (both .mp3 and .m4a)
            try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent("\(trackId).mp3"))
            try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent("\(trackId).m4a"))

            let finalPath: URL

            if permalinkUrl.contains("spotify.com") || permalinkUrl.contains("spotify:") {
                finalPath = try await performSpotifyDownload(
                    spotifyUrl: permalinkUrl,
                    trackId: trackId,
                    downloadsDir: downloadsDir
                )
            } else {
                finalPath = try await performSoundCloudDownload(
                    soundcloudUrl: permalinkUrl,
                    trackId: trackId,
                    downloadsDir: downloadsDir
                )
            }

            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: finalPath)
                downloadStatuses[trackId] = .notDownloaded
                downloadTasks.removeValue(forKey: trackId)
                return
            }

            // Verify file exists and get size
            guard FileManager.default.fileExists(atPath: finalPath.path) else {
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

            // Clean up partial files on failure
            if let downloadsDir = try? getDownloadsDirectory() {
                try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent("\(trackId).mp3"))
                try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent("\(trackId).m4a"))
            }

            downloadStatuses[trackId] = .failed(error)
            downloadTasks.removeValue(forKey: trackId)
        }
    }

    private func performSpotifyDownload(spotifyUrl: String, trackId: String, downloadsDir: URL) async throws -> URL {
        logInfo(.downloads, "Downloading Spotify track via spotdl")

        // Use SpotifyStreamService to get stream URL (direct HTTPS)
        let streamResponse = try await SpotifyStreamService.shared.getStreamURL(spotifyUrl: spotifyUrl)

        guard let streamURL = URL(string: streamResponse.streamURL) else {
            throw DownloadError.invalidURL
        }

        // Spotify streams are typically m4a (mp4a.40.2)
        let fileExtension = streamResponse.format.contains("mp3") ? "mp3" : "m4a"
        let destinationURL = downloadsDir.appendingPathComponent("\(trackId).\(fileExtension)")

        logInfo(.downloads, "Downloading Spotify stream (format: \(streamResponse.format))")
        try await downloadDirectFile(from: streamURL, to: destinationURL, trackId: trackId)

        return destinationURL
    }

    private func performSoundCloudDownload(soundcloudUrl: String, trackId: String, downloadsDir: URL) async throws -> URL {
        // Get signed stream URL via Railway yt-dlp API
        let ytdlpResponse = try await getStreamURL(soundcloudUrl: soundcloudUrl)

        guard let streamURL = URL(string: ytdlpResponse.streamURL) else {
            throw DownloadError.invalidURL
        }

        let fileExtension = ytdlpResponse.format.contains("mp3") ? "mp3" : "m4a"
        let destinationURL = downloadsDir.appendingPathComponent("\(trackId).\(fileExtension)")

        if ytdlpResponse.isDirect {
            logInfo(.downloads, "Downloading via direct HTTP URL (format: \(ytdlpResponse.format))")
            try await downloadDirectFile(from: streamURL, to: destinationURL, trackId: trackId)
        } else {
            logInfo(.downloads, "Downloading via server (HLS track)")
            let mp3Destination = downloadsDir.appendingPathComponent("\(trackId).mp3")
            try await downloadViaServer(soundcloudUrl: soundcloudUrl, to: mp3Destination, trackId: trackId)
        }

        // Find the actual downloaded file
        let mp3Path = downloadsDir.appendingPathComponent("\(trackId).mp3")
        let m4aPath = downloadsDir.appendingPathComponent("\(trackId).m4a")

        if FileManager.default.fileExists(atPath: mp3Path.path) {
            return mp3Path
        } else if FileManager.default.fileExists(atPath: m4aPath.path) {
            return m4aPath
        } else {
            throw DownloadError.saveFailed
        }
    }

    /// Get stream URL from the yt-dlp API
    private func getStreamURL(soundcloudUrl: String) async throws -> StreamURLResponse {
        // Validate it's a SoundCloud URL
        guard soundcloudUrl.contains("soundcloud.com") else {
            throw DownloadError.invalidURL
        }

        guard let url = URL(string: "\(StreamAPI.baseURL)/stream") else {
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
            let detail = StreamAPI.serverDetail(from: data) ?? "Extraction failed (HTTP \(httpResponse.statusCode))"
            logError(.downloads, "Stream URL request failed: HTTP \(httpResponse.statusCode) - \(detail)")
            throw DownloadError.serverMessage(detail)
        }

        let decoded = try JSONDecoder().decode(StreamURLResponse.self, from: data)
        logInfo(.downloads, "Extracted \(decoded.format) stream for download")
        return decoded
    }

    private func downloadDirectFile(from url: URL, to destinationURL: URL, trackId: String) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        try await streamToFile(request: request, destinationURL: destinationURL, trackId: trackId)
        logInfo(.downloads, "Direct download complete: \(destinationURL.lastPathComponent)")
    }

    private func downloadViaServer(soundcloudUrl: String, to destinationURL: URL, trackId: String) async throws {
        guard let url = URL(string: "\(StreamAPI.baseURL)/download") else {
            throw DownloadError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": soundcloudUrl])
        request.timeoutInterval = 120 // Server-side HLS download + transcode can take time

        try await streamToFile(request: request, destinationURL: destinationURL, trackId: trackId)
        logInfo(.downloads, "Server download complete: \(destinationURL.lastPathComponent)")
    }

    /// Stream an HTTP response body to disk, reporting real progress to `downloadStatuses`.
    /// Runs off the main actor - the byte loop is hot.
    nonisolated private func streamToFile(request: URLRequest, destinationURL: URL, trackId: String) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            // Collect a bounded amount of the error body for the FastAPI detail message
            var errorBody = Data()
            for try await byte in bytes {
                errorBody.append(byte)
                if errorBody.count >= 4096 { break }
            }
            let detail = StreamAPI.serverDetail(from: errorBody) ?? "Download failed (HTTP \(httpResponse.statusCode))"
            logError(.downloads, "Download request failed: HTTP \(httpResponse.statusCode) - \(detail)")
            throw DownloadError.serverMessage(detail)
        }

        let expectedLength = httpResponse.expectedContentLength

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destinationURL)

        do {
            var buffer = Data()
            buffer.reserveCapacity(128 * 1024)
            var received: Int64 = 0
            var lastReportedProgress: Double = 0

            for try await byte in bytes {
                buffer.append(byte)

                if buffer.count >= 128 * 1024 {
                    try Task.checkCancellation()
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)

                    if expectedLength > 0 {
                        let progress = min(Double(received) / Double(expectedLength), 1)
                        if progress - lastReportedProgress >= 0.01 {
                            lastReportedProgress = progress
                            await setProgress(trackId: trackId, progress: progress)
                        }
                    }
                }
            }

            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
            }

            try handle.close()

            guard received > 0 else {
                try? FileManager.default.removeItem(at: destinationURL)
                throw DownloadError.saveFailed
            }
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    /// Update progress for an in-flight download without clobbering a terminal state
    private func setProgress(trackId: String, progress: Double) {
        if case .downloading = downloadStatuses[trackId] {
            downloadStatuses[trackId] = .downloading(progress: progress)
        }
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
                if let resolvedPath = resolveLocalPath(for: download) {
                    if resolvedPath != download.localPath {
                        await updateDownloadedTrackPath(trackId: download.trackId, localPath: resolvedPath)
                        var updatedDownload = download
                        updatedDownload.localPath = resolvedPath
                        validDownloads.append(updatedDownload)
                    } else {
                        validDownloads.append(download)
                    }
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
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid stream URL"
        case .downloadFailed: return "Download failed"
        case .saveFailed: return "Failed to save file"
        case .insufficientStorage: return "Not enough storage space"
        case .networkError: return "Network error"
        case .serverMessage(let message): return message
        }
    }
}
