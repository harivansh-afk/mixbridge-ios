//
//  PlayerState+Persistence.swift
//  mixbridge
//

import Foundation
import UIKit
import MixBridgeDB
import MixBridgeDJ

extension PlayerState {
    // MARK: - Persistence

    func loadMixSettings() {
        // Load Mix Mode settings with defaults
        let defaults = UserDefaults.standard

        // Only load if values exist, otherwise use defaults
        if defaults.object(forKey: kMixEnabled) != nil {
            mixEnabled = defaults.bool(forKey: kMixEnabled)
        }
        if defaults.object(forKey: kCrossfadeSeconds) != nil {
            crossfadeSeconds = max(1, min(20, defaults.double(forKey: kCrossfadeSeconds)))
        }
        if defaults.object(forKey: kPrewarmSeconds) != nil {
            prewarmSeconds = max(5, min(60, defaults.double(forKey: kPrewarmSeconds)))
        }
        if let curveRaw = defaults.string(forKey: kFadeCurve),
           let curve = DJCrossfadeCurve(rawValue: curveRaw) {
            fadeCurve = curve
        }

        // Load DJ Mode settings
        if defaults.object(forKey: kDJEnabled) != nil {
            djEnabled = defaults.bool(forKey: kDJEnabled)
        }
        if defaults.object(forKey: kDJStrictMode) != nil {
            djStrictMode = defaults.bool(forKey: kDJStrictMode)
        }
        if defaults.object(forKey: kDJDownloadAheadCount) != nil {
            djDownloadAheadCount = max(1, min(5, defaults.integer(forKey: kDJDownloadAheadCount)))
        }
        if defaults.object(forKey: kDJAutoDownloadAhead) != nil {
            djAutoDownloadAhead = defaults.bool(forKey: kDJAutoDownloadAhead)
        }

        // Sync to coordinator
        playbackCoordinator.mixEnabled = mixEnabled
        playbackCoordinator.crossfadeSeconds = crossfadeSeconds
        playbackCoordinator.prewarmSeconds = prewarmSeconds
        playbackCoordinator.fadeCurve = fadeCurve
    }

    func scheduleSavePlaybackState(immediate: Bool = false) {
        let track = currentTrack
        let position = playbackPosition
        let duration = self.duration
        let savedTrackKey = kSavedTrack
        let savedPositionKey = kSavedPosition
        let savedDurationKey = kSavedDuration

        saveStateTask?.cancel()
        saveStateTask = Task.detached(priority: .utility) {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(150))
            }

            if let encoded = try? JSONEncoder().encode(track) {
                UserDefaults.standard.set(encoded, forKey: savedTrackKey)
            }
            UserDefaults.standard.set(position, forKey: savedPositionKey)
            UserDefaults.standard.set(duration, forKey: savedDurationKey)
        }
    }

    func loadPlaybackState() {
        // Load track
        if let savedTrackData = UserDefaults.standard.data(forKey: kSavedTrack),
           let savedTrack = try? JSONDecoder().decode(Track.self, from: savedTrackData) {
            currentTrack = savedTrack

            // Load position and duration
            let savedPosition = UserDefaults.standard.double(forKey: kSavedPosition)
            let savedDuration = UserDefaults.standard.double(forKey: kSavedDuration)

            if savedDuration > 0 {
                playbackPosition = savedPosition
                duration = savedDuration
                // Set status to paused so UI shows it
                playbackStatus = .paused
                // Load artwork and update Now Playing info
                refreshArtwork(for: savedTrack)
                updateNowPlayingInfo(playbackRate: 0)
            }
        }
    }

    func fetchRemoteHistoryIfNeeded() async {
        // Double check we still need it
        if hasActiveTrack { return }

        // We need authentication to fetch history
        guard let userId = KeychainManager.shared.getUserId() else { return }

        // Local-first: prefer the sync engine DB for instant startup + offline support.
        do {
            if let local = try await HistorySync.shared.getLocalHistory(limit: 1).first,
               let scTrack = local.track.soundCloudTrack {
                await setDefaultTrack(from: scTrack)
                return
            }
        } catch {
            logDebug(.db, "PlayerState: no local history available: \(error)")
        }

        do {
            if let local = try await LikedSync.shared.getLocalLikedTracks().first,
               let scTrack = local.track.soundCloudTrack {
                await setDefaultTrack(from: scTrack)
                return
            }
        } catch {
            logDebug(.db, "PlayerState: no local liked tracks available: \(error)")
        }

        // Try 1: Get last played song from play history
        do {
            let history = try await ConvexService.shared.getPlayHistory(userId: userId, limit: 1)
            if let lastPlayed = history.first {
                await setDefaultTrack(from: lastPlayed.trackData)
                return
            }
        } catch {
            logError(.network, "Failed to fetch play history: \(error)")
        }

        // Fallback: Get most recently liked song
        if !hasActiveTrack {
            do {
                let likedTracks = try await ConvexService.shared.getLikedTracks(userId: userId, forceRefresh: false)
                if let firstLiked = likedTracks.first {
                    await setDefaultTrack(from: firstLiked)
                    return
                }
            } catch {
                logError(.network, "Failed to fetch liked tracks: \(error)")
            }
        }
    }

    func setDefaultTrack(from soundCloudTrack: SoundCloudTrack) async {
        let artworkUrl = soundCloudTrack.artwork_url ?? soundCloudTrack.user.avatar_url ?? ""
        let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

        let track = Track(
            id: String(soundCloudTrack.id),
            title: soundCloudTrack.title,
            artist: soundCloudTrack.user.username,
            album: soundCloudTrack.genre ?? "",
            artwork: highQualityArtwork,
            duration: Double(soundCloudTrack.duration) / 1000.0 // Convert ms to seconds
        )

        await MainActor.run {
            // Only update if we still don't have an active track
            if !self.hasActiveTrack {
                self.currentTrack = track
                self.duration = track.duration
                self.playbackPosition = 0
                self.playbackStatus = .paused // Ready to play
                // Load artwork and update Now Playing info
                self.refreshArtwork(for: track)
                self.updateNowPlayingInfo(playbackRate: 0)
                self.scheduleSavePlaybackState(immediate: true) // Save so we don't fetch next time
            }
        }
    }

    @objc func handleAppBackground() {
        scheduleSavePlaybackState(immediate: true)
    }
}
