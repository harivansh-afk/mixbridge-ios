//
//  PlayerState+RemoteCommands.swift
//  mixbridge
//

import Foundation
import MediaPlayer

extension PlayerState {
    // MARK: - Remote Commands

    func setupRemoteCommands() {
        teardownRemoteCommands()

        // Basic playback controls
        remoteCommandTargets.play = commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.resume()
            }
            return .success
        }

        remoteCommandTargets.pause = commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        remoteCommandTargets.togglePlayPause = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayback()
            }
            return .success
        }

        // Track navigation
        remoteCommandTargets.nextTrack = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playNextFromQueue()
            }
            return .success
        }

        remoteCommandTargets.previousTrack = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playPreviousFromQueue()
            }
            return .success
        }

        // Playback position (lock screen scrubbing)
        remoteCommandTargets.changePlaybackPosition = commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            Task { @MainActor in
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }

        // Repeat mode (CarPlay / external controllers)
        commandCenter.changeRepeatModeCommand.currentRepeatType = repeatMode.mpRepeatType
        remoteCommandTargets.changeRepeatMode = commandCenter.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let repeatEvent = event as? MPChangeRepeatModeCommandEvent else {
                return .commandFailed
            }

            Task { @MainActor in
                self?.repeatMode = RepeatMode(mpRepeatType: repeatEvent.repeatType)
            }
            return .success
        }

        // Disable skip commands so iOS shows next/previous track buttons instead
        // (Skip buttons are for podcast-style apps, not music players)
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false

        // Disable commands we don't support
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false

        updateRemoteCommandEnabledState()
    }

    func teardownRemoteCommands() {
        if let target = remoteCommandTargets.play { commandCenter.playCommand.removeTarget(target) }
        if let target = remoteCommandTargets.pause { commandCenter.pauseCommand.removeTarget(target) }
        if let target = remoteCommandTargets.togglePlayPause { commandCenter.togglePlayPauseCommand.removeTarget(target) }
        if let target = remoteCommandTargets.nextTrack { commandCenter.nextTrackCommand.removeTarget(target) }
        if let target = remoteCommandTargets.previousTrack { commandCenter.previousTrackCommand.removeTarget(target) }
        if let target = remoteCommandTargets.changePlaybackPosition {
            commandCenter.changePlaybackPositionCommand.removeTarget(target)
        }
        if let target = remoteCommandTargets.changeRepeatMode {
            commandCenter.changeRepeatModeCommand.removeTarget(target)
        }

        remoteCommandTargets = RemoteCommandTargets()
    }

    func updateRemoteCommandEnabledState() {
        commandCenter.playCommand.isEnabled = !isPlaying
        commandCenter.pauseCommand.isEnabled = isPlaying
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = canPlayNext
        commandCenter.previousTrackCommand.isEnabled = canPlayPrevious
        commandCenter.changePlaybackPositionCommand.isEnabled = duration > 0
        commandCenter.changeRepeatModeCommand.isEnabled = true
    }

    struct RemoteCommandTargets {
        var play: Any?
        var pause: Any?
        var togglePlayPause: Any?
        var nextTrack: Any?
        var previousTrack: Any?
        var changePlaybackPosition: Any?
        var changeRepeatMode: Any?
    }
}

