//
//  DownloadManager.swift
//  mixbridge
//
//  Manages offline track downloads using existing stream endpoints.
//  Uses AVAssetExportSession to download HLS streams as M4A files.
//

import Foundation
import AVFoundation
import MixBridgeDB
import Combine

// MARK: - HLS URL Resolver

enum StreamResolveError: Error {
    case missingFinalURL
    case notM3U8Response
    case httpError(Int)
}

/// Result of resolving SoundCloud HLS URL
struct ResolvedHLSStream {
    let url: URL
    let playlistContent: String
}

/// Resolves SoundCloud API HLS URL to signed CDN URL
/// The API URL requires OAuth headers, but the resolved CDN URL has auth in query params
func resolveSoundCloudHLS(apiHLSURL: URL, accessToken: String) async throws -> ResolvedHLSStream {
    var request = URLRequest(url: apiHLSURL)
    request.setValue("OAuth \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("*/*", forHTTPHeaderField: "Accept")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw StreamResolveError.missingFinalURL
    }

    if httpResponse.statusCode != 200 {
        throw StreamResolveError.httpError(httpResponse.statusCode)
    }

    guard let finalURL = response.url else {
        throw StreamResolveError.missingFinalURL
    }

    guard let content = String(data: data, encoding: .utf8) else {
        throw StreamResolveError.notM3U8Response
    }

    // Sanity check: the body should be an m3u8 playlist
    if !content.hasPrefix("#EXTM3U") {
        print("Response is not m3u8: \(content.prefix(100))")
        throw StreamResolveError.notM3U8Response
    }

    return ResolvedHLSStream(url: finalURL, playlistContent: content)
}

// MARK: - HLS Download Diagnostic

/// Test function to diagnose HLS download capability
/// Call this from a button or debug menu to see console output
func diagnoseHLSDownload(streamURL: URL, accessToken: String) async {
    print("=== HLS Download Diagnostic ===")
    print("Original API URL: \(streamURL)")

    // Step 1: Try to resolve the API URL to a signed CDN URL
    print("\n--- Step 1: Resolving API URL ---")
    var resolvedURL: URL = streamURL
    var playlistContent: String = ""
    do {
        let resolved = try await resolveSoundCloudHLS(apiHLSURL: streamURL, accessToken: accessToken)
        resolvedURL = resolved.url
        playlistContent = resolved.playlistContent
        print("Resolved CDN URL: \(resolvedURL)")
        print("Host changed: \(streamURL.host ?? "?") -> \(resolvedURL.host ?? "?")")

        if resolvedURL.host != streamURL.host {
            print("SUCCESS: URL was redirected to CDN (auth likely in query params)")
        } else {
            print("WARNING: URL host unchanged - may still need headers for segments")
        }

        // Print the playlist content to understand its structure
        print("\n--- Playlist Content (m3u8) ---")
        print(playlistContent)
        print("--- End Playlist Content ---\n")
    } catch {
        print("FAILED to resolve: \(error)")
        print("Falling back to original URL with headers...")
    }

    // Step 2: Test the resolved URL WITHOUT headers (CDN should have auth in query)
    print("\n--- Step 2: Testing resolved URL WITHOUT headers ---")
    let assetNoHeaders = AVURLAsset(url: resolvedURL)
    do {
        let tracks = try await assetNoHeaders.load(.tracks)
        print("Tracks (no headers): \(tracks.count)")
        if tracks.count > 0 {
            print("SUCCESS: CDN URL works without headers - offline download WILL work!")
            for track in tracks {
                print("   - Track: \(track.mediaType.rawValue)")
            }
        } else {
            print("WARNING: 0 tracks - CDN URL may still need auth")
        }
    } catch {
        print("FAILED (no headers): \(error.localizedDescription)")
    }

    // Step 3: Test with headers (for comparison)
    print("\n--- Step 3: Testing with OAuth headers ---")
    let headers = ["Authorization": "OAuth \(accessToken)"]
    let assetWithHeaders = AVURLAsset(url: resolvedURL, options: [
        "AVURLAssetHTTPHeaderFieldsKey": headers
    ])
    do {
        let tracks = try await assetWithHeaders.load(.tracks)
        print("Tracks (with headers): \(tracks.count)")
    } catch {
        print("FAILED (with headers): \(error.localizedDescription)")
    }

    // Step 4: Check other properties
    print("\n--- Step 4: Asset Properties ---")
    do {
        let hasProtectedContent = try await assetNoHeaders.load(.hasProtectedContent)
        print("Has DRM: \(hasProtectedContent)")
    } catch {
        print("DRM check failed: \(error.localizedDescription)")
    }

    do {
        let isExportable = try await assetNoHeaders.load(.isExportable)
        print("Is Exportable: \(isExportable)")
    } catch {
        print("Exportable check failed: \(error.localizedDescription)")
    }

    print("\n=== End Diagnostic ===")
}

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

    private let db = MixBridgeDB.shared
    private let convexService = ConvexService.shared
    private let streamCache = StreamURLCache.shared

    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var exportSessions: [String: AVAssetExportSession] = [:]

    private init() {
        Task {
            await loadDownloadedTracks()
        }
    }

    // MARK: - Diagnostic

    /// Run diagnostic on a track to check HLS download capability
    /// Check Xcode console for output
    func runDiagnostic(for track: SoundCloudTrack) {
        let trackId = String(track.id)
        Task {
            do {
                let streamData = try await streamCache.ensureStream(for: trackId, priority: .userInitiated)
                guard let streamURL = URL(string: streamData.url) else {
                    print("DIAGNOSTIC: Invalid stream URL")
                    return
                }
                await diagnoseHLSDownload(streamURL: streamURL, accessToken: streamData.accessToken)
            } catch {
                print("DIAGNOSTIC: Failed to get stream - \(error)")
            }
        }
    }

    // MARK: - Public API

    /// Download a track for offline playback
    func downloadTrack(_ track: SoundCloudTrack) {
        let trackId = String(track.id)

        guard downloadStatuses[trackId] != .downloading(progress: 0) else { return }

        downloadStatuses[trackId] = .downloading(progress: 0)

        let task = Task {
            await performDownload(track: track)
        }
        downloadTasks[trackId] = task
    }

    /// Download multiple tracks
    func downloadTracks(_ tracks: [SoundCloudTrack]) {
        for track in tracks {
            downloadTrack(track)
        }
    }

    /// Cancel a download in progress
    func cancelDownload(trackId: String) {
        downloadTasks[trackId]?.cancel()
        downloadTasks.removeValue(forKey: trackId)
        exportSessions[trackId]?.cancelExport()
        exportSessions.removeValue(forKey: trackId)
        downloadStatuses[trackId] = .notDownloaded
    }

    /// Delete a downloaded track
    func deleteDownload(trackId: String) async {
        do {
            if let downloaded = try await getDownloadedTrack(trackId: trackId) {
                let fileURL = URL(fileURLWithPath: downloaded.localPath)
                try? FileManager.default.removeItem(at: fileURL)
            }

            try await db.writer.write { db in
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

            for download in downloads {
                let fileURL = URL(fileURLWithPath: download.localPath)
                try? FileManager.default.removeItem(at: fileURL)
            }

            try await db.writer.write { db in
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

    /// Get the local file URL for a downloaded track
    func getLocalFileURL(trackId: String) async -> URL? {
        guard let downloaded = try? await getDownloadedTrack(trackId: trackId) else {
            return nil
        }
        let url = URL(fileURLWithPath: downloaded.localPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
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

    // MARK: - Private

    private func performDownload(track: SoundCloudTrack) async {
        let trackId = String(track.id)

        do {
            logInfo(.downloads, "Starting download for: \(track.title)")

            let streamData = try await streamCache.ensureStream(for: trackId, priority: .userInitiated)

            guard let streamURL = URL(string: streamData.url) else {
                throw DownloadError.invalidURL
            }

            let downloadsDir = try getDownloadsDirectory()

            // Determine file extension based on stream type
            // Progressive streams are typically AAC (.m4a) or MP3
            let fileExtension = streamURL.pathExtension.isEmpty ? "m4a" : streamURL.pathExtension
            let destinationURL = downloadsDir.appendingPathComponent("\(trackId).\(fileExtension)")

            try? FileManager.default.removeItem(at: destinationURL)

            // Check if this is a progressive (http) stream or HLS
            let isProgressiveStream = streamData.url.contains("/http") ||
                                      streamData.streamType == "http" ||
                                      !streamData.url.contains(".m3u8")

            if isProgressiveStream {
                // Use simple URLSession download for progressive streams
                logInfo(.downloads, "Using progressive download for: \(track.title)")
                try await downloadProgressiveStream(
                    url: streamURL,
                    accessToken: streamData.accessToken,
                    destination: destinationURL,
                    trackId: trackId
                )
            } else {
                // Fall back to HLS approach (may not work for all streams)
                logInfo(.downloads, "Using HLS download for: \(track.title)")
                let headers = ["Authorization": "OAuth \(streamData.accessToken)"]
                let asset = AVURLAsset(url: streamURL, options: [
                    "AVURLAssetHTTPHeaderFieldsKey": headers
                ])
                try await exportAsset(asset, to: destinationURL, trackId: trackId)
            }

            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: destinationURL)
                downloadStatuses[trackId] = .notDownloaded
                return
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0

            guard fileSize > 0 else {
                throw DownloadError.exportFailed
            }

            try await persistTrackIfNeeded(track)

            let downloaded = DownloadedTrack(
                trackId: trackId,
                localPath: destinationURL.path,
                fileSize: fileSize,
                downloadedAt: Date()
            )

            try await db.writer.write { db in
                try downloaded.save(db)
            }

            downloadStatuses[trackId] = .downloaded
            exportSessions.removeValue(forKey: trackId)
            await loadDownloadedTracks()

            logInfo(.downloads, "Downloaded track: \(track.title) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))")
        } catch is CancellationError {
            downloadStatuses[trackId] = .notDownloaded
            exportSessions.removeValue(forKey: trackId)
        } catch {
            logError(.downloads, "Download failed for \(track.title): \(error)")
            downloadStatuses[trackId] = .failed(error)
            exportSessions.removeValue(forKey: trackId)
        }

        downloadTasks.removeValue(forKey: trackId)
    }

    /// Download a progressive (non-HLS) stream directly using URLSession
    private func downloadProgressiveStream(
        url: URL,
        accessToken: String,
        destination: URL,
        trackId: String
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("OAuth \(accessToken)", forHTTPHeaderField: "Authorization")

        // Get expected content length first with HEAD request
        var headRequest = request
        headRequest.httpMethod = "HEAD"
        let (_, headResponse) = try await URLSession.shared.data(for: headRequest)
        let expectedLength = (headResponse as? HTTPURLResponse)?.expectedContentLength ?? -1

        // Download with progress tracking using bytes stream
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.downloadFailed
        }

        guard httpResponse.statusCode == 200 else {
            logError(.downloads, "Download failed with status: \(httpResponse.statusCode)")
            throw DownloadError.downloadFailed
        }

        let totalBytes = expectedLength > 0 ? expectedLength : httpResponse.expectedContentLength

        // Create output file
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: destination)

        var downloadedBytes: Int64 = 0
        var buffer = Data()
        let bufferSize = 65536 // 64KB chunks

        for try await byte in asyncBytes {
            try Task.checkCancellation()

            buffer.append(byte)
            downloadedBytes += 1

            // Write in chunks for efficiency
            if buffer.count >= bufferSize {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)

                // Update progress
                if totalBytes > 0 {
                    let progress = Double(downloadedBytes) / Double(totalBytes)
                    downloadStatuses[trackId] = .downloading(progress: progress)
                }
            }
        }

        // Write remaining buffer
        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
        }

        try fileHandle.close()

        logInfo(.downloads, "Downloaded \(ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file))")
    }

    private func exportAsset(_ asset: AVURLAsset, to outputURL: URL, trackId: String) async throws {
        // First, ensure the asset is playable (forces HLS manifest to load)
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            logError(.downloads, "Asset is not playable")
            throw DownloadError.exportFailed
        }
        
        // Load all tracks first
        let allTracks = try await asset.load(.tracks)
        logInfo(.downloads, "Asset has \(allTracks.count) tracks")
        
        // Find audio tracks
        let audioTracks = allTracks.filter { $0.mediaType == .audio }
        logInfo(.downloads, "Found \(audioTracks.count) audio tracks")
        
        guard let audioTrack = audioTracks.first else {
            logError(.downloads, "No audio track found in asset")
            throw DownloadError.noAudioTrack
        }
        
        logInfo(.downloads, "Found audio track, creating audio-only composition")
        
        // Create a composition with just the audio track
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw DownloadError.exportFailed
        }
        
        let duration = try await asset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        
        try compositionTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        
        logInfo(.downloads, "Audio duration: \(CMTimeGetSeconds(duration))s")
        
        // Now export the audio-only composition
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                continuation.resume(throwing: DownloadError.exportFailed)
                return
            }

            exportSession.outputURL = outputURL
            exportSession.outputFileType = .m4a

            self.exportSessions[trackId] = exportSession

            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                let progress = Double(exportSession.progress)
                Task { @MainActor in
                    self.downloadStatuses[trackId] = .downloading(progress: progress)
                }
            }
            RunLoop.main.add(progressTimer, forMode: .common)

            exportSession.exportAsynchronously {
                progressTimer.invalidate()

                switch exportSession.status {
                case .completed:
                    logInfo(.downloads, "Export completed successfully")
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .failed:
                    logError(.downloads, "Export failed: \(exportSession.error?.localizedDescription ?? "unknown")")
                    continuation.resume(throwing: exportSession.error ?? DownloadError.exportFailed)
                default:
                    continuation.resume(throwing: DownloadError.exportFailed)
                }
            }
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
            try await db.writer.write { db in
                try persisted.save(db)
            }
        }
    }

    private func loadDownloadedTracks() async {
        do {
            let downloads = try await db.reader.read { db in
                try DownloadedTrack
                    .order(DownloadedTrack.Columns.downloadedAt.desc)
                    .fetchAll(db)
            }

            for download in downloads {
                downloadStatuses[download.trackId] = .downloaded
            }

            let trackIds = downloads.map { $0.trackId }
            let tracks = try await db.reader.read { db in
                try PersistedTrack.filter(keys: trackIds).fetchAll(db)
            }

            let trackMap = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })

            downloadedTracks = downloads.compactMap { download in
                guard let track = trackMap[download.trackId] else { return nil }
                return DownloadedTrackInfo(
                    track: track.toTrack(),
                    soundCloudTrack: track.soundCloudTrack,
                    downloadedAt: download.downloadedAt,
                    fileSize: download.fileSize
                )
            }
        } catch {
            logError(.downloads, "Failed to load downloaded tracks: \(error)")
        }
    }
}

// MARK: - Supporting Types

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

enum DownloadError: LocalizedError {
    case invalidURL
    case downloadFailed
    case exportFailed
    case noAudioTrack
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid stream URL"
        case .downloadFailed: return "Download failed"
        case .exportFailed: return "Failed to export audio"
        case .noAudioTrack: return "No audio track found"
        case .saveFailed: return "Failed to save file"
        }
    }
}
