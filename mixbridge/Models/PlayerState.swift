//
//  PlayerState.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

@Observable
@MainActor
final class PlayerState: NSObject {
    static let shared = PlayerState()

    enum PlaybackStatus: Equatable {
        case idle
        case loading
        case ready
        case playing
        case paused
        case failed(String)
    }

    enum PlaybackError: LocalizedError {
        case invalidStreamURL

        var errorDescription: String? {
            switch self {
            case .invalidStreamURL:
                return "Invalid stream URL"
            }
        }
    }

    var currentTrack: Track
    var isPlaying: Bool = false
    var playbackPosition: Double = 0
    var duration: Double = 0
    var playbackStatus: PlaybackStatus = .idle
    var autoplayEnabled: Bool = true {
        didSet {
            playbackCoordinator.autoplayEnabled = autoplayEnabled
        }
    }
    var volume: Double = 0.7 {
        didSet {
            playbackCoordinator.setVolume(volume)
        }
    }
    var errorMessage: String?

    private let playbackCoordinator = PlaybackCoordinator.shared
    private let queueManager = QueueManager.shared
    private let audioSession = AVAudioSession.sharedInstance()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private var currentQueueIndex: Int = -1
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var lastPublishedStatus: PlaybackStatus = .idle

    private override init() {
        currentTrack = Track.sampleTracks.first ?? Track(
            title: "Some Music Title",
            artist: "Unknown Artist",
            album: "Unknown Album"
        )
        super.init()
        configureAudioSession()
        setupNotifications()
        setupRemoteCommands()
        playbackCoordinator.delegate = self
        playbackCoordinator.setVolume(volume)
        playbackCoordinator.autoplayEnabled = autoplayEnabled
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    // MARK: - Public API

    func play(track: Track, trackData: [String: Any]? = nil, queueIndex: Int? = nil) {
        playbackStatus = .loading
        currentTrack = track
        refreshArtwork(for: track)
        playbackPosition = 0
        duration = track.duration
        if let explicitIndex = queueIndex {
            currentQueueIndex = explicitIndex
        } else if let inferredIndex = queueManager.indexOfTrack(withId: track.id) {
            currentQueueIndex = inferredIndex
        } else {
            currentQueueIndex = -1
        }
        try? activateAudioSession()
        playbackCoordinator.play(
            track: track,
            trackData: trackData ?? queueManager.trackData(for: track.id),
            queueIndex: queueIndex
        )
        updateNowPlayingInfo(playbackRate: 0)
    }

    func playFromQueue(index: Int) {
        guard queueManager.queueTracks.indices.contains(index) else { return }
        let track = queueManager.queueTracks[index]
        play(track: track, trackData: queueManager.trackData(for: track.id), queueIndex: index)
    }

    func togglePlayback() {
        playbackCoordinator.togglePlayback()
    }

    func pause() {
        playbackCoordinator.pause()
        updateNowPlayingInfo(playbackRate: 0)
    }

    func resume() {
        try? activateAudioSession()
        playbackCoordinator.resume()
        updateNowPlayingInfo(playbackRate: 1)
    }

    func seek(to time: Double) {
        playbackCoordinator.seek(to: time)
    }

    func playNextFromQueue() {
        playbackCoordinator.playNext(manual: true)
    }

    func playPreviousFromQueue() {
        playbackCoordinator.playPrevious()
    }

    // MARK: - Setup

    private func configureAudioSession() {
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowBluetoothA2DP, .allowAirPlay])
            try audioSession.setActive(true)
        } catch {
            print("❌ [PlayerState] Failed to configure audio session: \(error)")
        }
    }

    private func activateAudioSession() throws {
        if audioSession.category != .playback {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowBluetoothA2DP, .allowAirPlay])
        }
        try audioSession.setActive(true)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: audioSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: audioSession
        )
    }

    private func setupRemoteCommands() {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayback()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNextFromQueue()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPreviousFromQueue()
            return .success
        }
    }

    // MARK: - Notifications

    @MainActor
    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            pause()
        case .ended:
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    @MainActor
    @objc private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    // MARK: - Helpers

    private func updateNowPlayingInfo(playbackRate: Float? = nil) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentTrack.title
        info[MPMediaItemPropertyArtist] = currentTrack.artist

        let trackDuration = duration > 0 ? duration : max(currentTrack.duration, 0)
        info[MPMediaItemPropertyPlaybackDuration] = trackDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate ?? (isPlaying ? 1 : 0)

        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func refreshArtwork(for track: Track) {
        artworkTask?.cancel()

        if track.artwork.starts(with: "http"), let url = URL(string: track.artwork) {
            artworkTask = Task { [weak self] in
                guard let self else { return }
                if let image = await ImageCacheManager.shared.getImage(for: url) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    await MainActor.run {
                        self.nowPlayingArtwork = artwork
                        self.updateNowPlayingInfo()
                    }
                }
            }
        } else if let image = UIImage(named: track.artwork) {
            nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else {
            nowPlayingArtwork = nil
        }
    }

    private func handlePlaybackFailure(_ error: Error) {
        errorMessage = error.localizedDescription
        playbackStatus = .failed(error.localizedDescription)
        isPlaying = false
        updateNowPlayingInfo(playbackRate: 0)
        HapticManager.error()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - PlaybackCoordinatorDelegate

extension PlayerState: PlaybackCoordinatorDelegate {
    func playbackCoordinator(_ coordinator: PlaybackCoordinator, didUpdate snapshot: PlaybackSnapshot) {
        if let track = snapshot.track {
            let trackChanged = track.id != currentTrack.id
            currentTrack = track
            if trackChanged {
                refreshArtwork(for: track)
            }
            if let index = snapshot.queueIndex {
                currentQueueIndex = index
            } else if trackChanged {
                currentQueueIndex = -1
            }
        } else if snapshot.queueIndex == nil {
            currentQueueIndex = -1
        }

        isPlaying = snapshot.isPlaying
        playbackStatus = snapshot.status
        playbackPosition = snapshot.currentTime
        duration = snapshot.duration
        updateNowPlayingInfo()

        if playbackStatus == .playing && lastPublishedStatus == .loading {
            HapticManager.success()
        }

        lastPublishedStatus = playbackStatus
    }

    func playbackCoordinator(_ coordinator: PlaybackCoordinator, didEncounter error: Error) {
        handlePlaybackFailure(error)
        lastPublishedStatus = .failed(error.localizedDescription)
    }
}
