//
//  DJPrepService.swift
//  mixbridge
//
//  Background service that prepares upcoming queue tracks for DJ mixing.
//  Downloads tracks (if not already downloaded) and runs BPM analysis.
//  Only active when PlayerState.djEnabled is true.
//

import Combine
import Foundation
import MixBridgeDJ

/// Prep status for a track.
enum DJPrepStatus: Equatable, Sendable {
    case pending
    case downloading
    case analyzing
    case ready(DJAnalysisResult)
    case failed(String)
}

/// Background service that prepares upcoming tracks for DJ mixing.
/// Coordinates downloads and analysis for N tracks ahead in the queue.
@MainActor
final class DJPrepService: ObservableObject {
    static let shared = DJPrepService()

    /// Current prep status per track ID.
    @Published private(set) var prepStatuses: [String: DJPrepStatus] = [:]

    private let downloadManager = DownloadManager.shared
    private let analysisManager = DJAnalysisManager.shared
    private let queueManager = QueueManager.shared

    /// Active prep task - cancelled when queue changes.
    private var prepTask: Task<Void, Never>?

    /// Debounce duration to avoid rapid re-prep on queue changes.
    private let debounceInterval: Duration = .milliseconds(300)

    private init() {
        logInfo(.dj, "DJPrepService: initialized")
    }

    // MARK: - Public API

    /// Called when the queue changes. Preps the next N tracks.
    /// No-op if DJ mode is disabled.
    func prepNextTracks() {
        guard PlayerState.shared.djEnabled else {
            logDebug(.dj, "DJPrepService: DJ mode disabled, skipping prep")
            return
        }

        // Cancel any existing prep task
        prepTask?.cancel()

        prepTask = Task { [weak self] in
            guard let self else { return }

            // Debounce rapid queue changes
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }

            await self.performPrep()
        }
    }

    /// Returns the analysis result for a track if it's been prepped.
    func getAnalysis(trackId: String) -> DJAnalysisResult? {
        if case .ready(let result) = prepStatuses[trackId] {
            return result
        }
        return nil
    }

    /// Returns true if a track is fully prepped (downloaded + analyzed).
    func isPrepped(trackId: String) -> Bool {
        if case .ready = prepStatuses[trackId] {
            return true
        }
        return false
    }

    /// Manually triggers prep for a specific track (used by DJ Lab).
    func prepTrack(_ track: Track) async {
        guard let scTrack = queueManager.soundCloudTrack(for: track.id) else {
            prepStatuses[track.id] = .failed("No SoundCloud metadata")
            return
        }

        do {
            try await prepSingleTrack(track: track, soundCloudTrack: scTrack)
        } catch {
            prepStatuses[track.id] = .failed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func performPrep() async {
        let count = PlayerState.shared.djDownloadAheadCount
        let autoDownload = PlayerState.shared.djAutoDownloadAhead

        let upcomingTracks = Array(queueManager.queue.items.prefix(count))

        guard !upcomingTracks.isEmpty else {
            logDebug(.dj, "DJPrepService: no upcoming tracks to prep")
            return
        }

        logInfo(.dj, "DJPrepService: prepping \(upcomingTracks.count) tracks")

        for item in upcomingTracks {
            guard !Task.isCancelled else { break }

            let trackId = item.trackId
            let track = item.track

            // Skip if already prepped
            if case .ready = prepStatuses[trackId] {
                continue
            }

            guard let scTrack = item.soundCloudTrack else {
                prepStatuses[trackId] = .failed("No SoundCloud metadata")
                continue
            }

            do {
                try await prepSingleTrack(
                    track: track,
                    soundCloudTrack: scTrack,
                    autoDownload: autoDownload
                )
            } catch {
                logError(.dj, "DJPrepService: failed to prep \(track.title): \(error)")
                prepStatuses[trackId] = .failed(error.localizedDescription)
            }
        }
    }

    private func prepSingleTrack(
        track: Track,
        soundCloudTrack: SoundCloudTrack,
        autoDownload: Bool = true
    ) async throws {
        let trackId = track.id

        // Step 1: Ensure track is downloaded
        if !downloadManager.isDownloaded(trackId: trackId) {
            if autoDownload {
                prepStatuses[trackId] = .downloading
                logDebug(.dj, "DJPrepService: downloading \(track.title)")

                // Trigger download and wait for completion
                downloadManager.downloadTrack(soundCloudTrack)

                // Poll for download completion (with timeout)
                let timeout = Date().addingTimeInterval(120) // 2 min timeout
                while !downloadManager.isDownloaded(trackId: trackId) {
                    if Date() > timeout {
                        throw DJPrepError.downloadTimeout
                    }
                    if case .failed = downloadManager.downloadStatuses[trackId] {
                        throw DJPrepError.downloadFailed
                    }
                    try await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else {
                        throw CancellationError()
                    }
                }
            } else {
                // Track not downloaded and auto-download disabled
                prepStatuses[trackId] = .failed("Not downloaded")
                return
            }
        }

        // Step 2: Get local file URL
        guard let fileURL = await downloadManager.getLocalFileURL(trackId: trackId) else {
            throw DJPrepError.fileNotFound
        }

        // Step 3: Run analysis
        prepStatuses[trackId] = .analyzing
        logDebug(.dj, "DJPrepService: analyzing \(track.title)")

        let result = try await analysisManager.analyze(url: fileURL, trackId: trackId)

        prepStatuses[trackId] = .ready(result)
        logInfo(.dj, "DJPrepService: prepped \(track.title) - BPM: \(String(format: "%.1f", result.bpm))")
    }
}

// MARK: - Errors

enum DJPrepError: Error, LocalizedError {
    case downloadTimeout
    case downloadFailed
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .downloadTimeout:
            return "Download timed out"
        case .downloadFailed:
            return "Download failed"
        case .fileNotFound:
            return "Downloaded file not found"
        }
    }
}
