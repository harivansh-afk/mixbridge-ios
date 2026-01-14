//
//  PlayerState+PlaybackCoordinatorDelegate.swift
//  mixbridge
//

import Foundation
import MediaPlayer

extension PlayerState: PlaybackCoordinatorDelegate {
    func playbackCoordinator(_ coordinator: PlaybackCoordinator, didUpdate snapshot: PlaybackSnapshot) {
        var needsNowPlayingUpdate = false

        // Track changes
        if let track = snapshot.track {
            let trackChanged = track.id != currentTrack.id
            currentTrack = track
            if trackChanged {
                refreshArtwork(for: track)
                needsNowPlayingUpdate = true
            }
            // Always try to sync queue index when track changes
            if let index = snapshot.queueIndex {
                _currentQueueIndex = index
            } else if trackChanged {
                // Try to infer queue index from queue manager
                // This ensures navigation works even when track was played from outside the queue
                if let inferredIndex = queueManager.indexOfTrack(withId: track.id) {
                    _currentQueueIndex = inferredIndex
                    logDebug(.playback, "Inferred queue index \(inferredIndex) for track: \(track.title)")
                } else {
                    _currentQueueIndex = -1
                }
            }
        } else if snapshot.queueIndex == nil {
            // No track in snapshot - try to infer from current track
            if let inferredIndex = queueManager.indexOfTrack(withId: currentTrack.id) {
                _currentQueueIndex = inferredIndex
            } else {
                _currentQueueIndex = -1
            }
        }

        // Playing state changes
        let wasPlaying = isPlaying
        isPlaying = snapshot.isPlaying
        if wasPlaying != isPlaying {
            needsNowPlayingUpdate = true
        }

        // Status changes
        let statusChanged = playbackStatus != snapshot.status
        playbackStatus = snapshot.status
        if statusChanged {
            needsNowPlayingUpdate = true
        }

        // Perf: resolve pending interactions
        if let pending = pendingPlayback, let track = snapshot.track, track.id == pending.trackId {
            if let token = pending.uiUpdated {
                InteractionMetrics.end(token, result: "track=\(track.title)")
                pendingPlayback?.uiUpdated = nil
            }
            if case .playing = snapshot.status, let token = pending.startedPlaying {
                InteractionMetrics.end(token, result: "track=\(track.title)")
                pendingPlayback?.startedPlaying = nil
            }
            if pendingPlayback?.uiUpdated == nil, pendingPlayback?.startedPlaying == nil {
                pendingPlayback = nil
            }
        }

        if let pending = pendingNavigation, let track = snapshot.track, track.id != {
            switch pending.kind {
            case .next(let previousTrackId), .previous(let previousTrackId):
                return previousTrackId
            }
        }() {
            InteractionMetrics.end(pending.token, result: "track=\(track.title)")
            pendingNavigation = nil
        }

        if let pending = pendingSeek, abs(snapshot.currentTime - pending.target) < 0.25 {
            InteractionMetrics.end(pending.token, result: "t=\(String(format: "%.2f", snapshot.currentTime))")
            pendingSeek = nil
        }

        // Position and duration (update locally, but don't spam Now Playing)
        // CRITICAL: Only update playback position if user is NOT actively seeking
        // This prevents the time observer from fighting with user's slider dragging
        if !isSeeking {
            playbackPosition = snapshot.currentTime
        }

        // Only update duration if we get a valid value from AVPlayer
        // This prevents flicker when switching tracks - we keep the track's API duration
        // until AVPlayer provides a valid duration
        if snapshot.duration > 0 {
            duration = snapshot.duration
        }

        // Only update Now Playing when something meaningful changed
        if needsNowPlayingUpdate {
            updateNowPlayingInfo()
            logDebug(.playback, "Now Playing updated: \(self.currentTrack.title) [\(self.playbackStatus)]")
        } else {
            // Just update the elapsed time (lightweight operation)
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1 : 0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }

        lastPublishedStatus = playbackStatus

        if let token = pendingToggle, wasPlaying != isPlaying {
            InteractionMetrics.end(token, result: isPlaying ? "playing" : "paused")
            pendingToggle = nil
        }

        updateRemoteCommandEnabledState()
    }

    func playbackCoordinator(_ coordinator: PlaybackCoordinator, didEncounter error: Error) {
        handlePlaybackFailure(error)
        lastPublishedStatus = .failed(error.localizedDescription)
    }
}

