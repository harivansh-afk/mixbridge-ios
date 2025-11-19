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

    // Debouncer for seek operations to prevent excessive calls during scrubbing
    private var seekDebouncer: Debouncer?

    // Timestamp of the target seek position (updated immediately for UI responsiveness)
    private var pendingSeekTime: Double?

    private override init() {
        currentTrack = Track.sampleTracks.first ?? Track(
            title: "Some Music Title",
            artist: "Unknown Artist",
            album: "Unknown Album"
        )
        super.init()

        // Initialize seek debouncer with 300ms delay (optimal for UI responsiveness)
        seekDebouncer = Debouncer(delay: 0.3) { [weak self] in
            guard let self, let targetTime = self.pendingSeekTime else { return }
            self.playbackCoordinator.seek(to: targetTime)
            self.pendingSeekTime = nil
        }

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

    /// Seeks to a specific time position with debouncing to prevent excessive operations.
    /// UI updates happen immediately while the actual AVPlayer seek is debounced by 300ms.
    ///
    /// - Parameter time: The target playback position in seconds
    /// - Parameter immediate: If true, bypasses debouncing and seeks immediately (default: false)
    func seek(to time: Double, immediate: Bool = false) {
        // Update UI immediately for smooth visual feedback
        playbackPosition = time
        pendingSeekTime = time

        if immediate {
            // Immediate seek (used for programmatic seeks, not user scrubbing)
            seekDebouncer?.cancel()
            playbackCoordinator.seek(to: time)
            pendingSeekTime = nil
        } else {
            // Debounced seek (used for user scrubbing)
            seekDebouncer?.call()
        }

        // Update Now Playing info with new position
        updateNowPlayingInfo()
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
            // Configure audio session for Now Playing integration
            // Note: Cannot use .mixWithOthers or it won't appear in Control Center/Lock Screen
            // Using .playback category makes us the primary audio app

            // Only configure if not already set to avoid OSStatus -50
            if audioSession.category != .playback || audioSession.mode != .default {
                try audioSession.setCategory(
                    .playback,
                    mode: .default,
                    options: [.allowBluetoothA2DP, .allowAirPlay]
                )
            }

            // Activate session
            if !audioSession.isOtherAudioPlaying {
                try audioSession.setActive(true)
            }

            print("✅ Audio session configured successfully")
        } catch let error as NSError {
            // OSStatus -50 means invalid parameter, but often non-fatal
            if error.code == -50 {
                print("⚠️ Audio session configuration warning (non-fatal): \(error.localizedDescription)")
            } else {
                print("❌ Failed to configure audio session: \(error.localizedDescription)")
            }
        }
    }

    private func activateAudioSession() throws {
        // Only reconfigure if category is wrong
        if audioSession.category != .playback || audioSession.mode != .default {
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )
        }

        // Try to activate, but don't throw if already active
        do {
            try audioSession.setActive(true)
        } catch let error as NSError {
            // Ignore if already active or if OSStatus -50
            if error.code != -50 {
                throw error
            }
        }
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
        // Remove all existing targets to prevent duplicates
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)

        // Basic playback controls
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayback()
            return .success
        }

        // Track navigation
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNextFromQueue()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPreviousFromQueue()
            return .success
        }

        // Playback position (lock screen scrubbing)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            // Use immediate seek for lock screen scrubbing (no debounce needed)
            self.seek(to: positionEvent.positionTime, immediate: true)
            return .success
        }

        // Skip forward (15 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            let skipInterval: Double
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                skipInterval = skipEvent.interval
            } else {
                skipInterval = 15.0
            }

            let newPosition = min(self.playbackPosition + skipInterval, self.duration)
            self.seek(to: newPosition, immediate: true)
            return .success
        }

        // Skip backward (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            let skipInterval: Double
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                skipInterval = skipEvent.interval
            } else {
                skipInterval = 15.0
            }

            let newPosition = max(self.playbackPosition - skipInterval, 0)
            self.seek(to: newPosition, immediate: true)
            return .success
        }

        // Disable commands we don't support
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
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
        info[MPMediaItemPropertyAlbumTitle] = currentTrack.album

        let trackDuration = duration > 0 ? duration : max(currentTrack.duration, 0)
        info[MPMediaItemPropertyPlaybackDuration] = trackDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate ?? (isPlaying ? 1 : 0)

        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if DEBUG
        print("🎨 Now Playing updated: \(currentTrack.title)")
        #endif
    }

    private func refreshArtwork(for track: Track) {
        artworkTask?.cancel()

        // Set placeholder artwork immediately
        nowPlayingArtwork = nil
        updateNowPlayingInfo()

        if track.artwork.starts(with: "http"), let url = URL(string: track.artwork) {
            artworkTask = Task { [weak self] in
                guard let self else { return }

                if let image = await ImageCacheManager.shared.getImage(for: url) {
                    // Create artwork with proper handler that returns resized images
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { requestedSize in
                        // Resize image to requested size for optimal display
                        let renderer = UIGraphicsImageRenderer(size: requestedSize)
                        return renderer.image { context in
                            image.draw(in: CGRect(origin: .zero, size: requestedSize))
                        }
                    }

                    await MainActor.run {
                        self.nowPlayingArtwork = artwork
                        self.updateNowPlayingInfo()
                        #if DEBUG
                        print("✅ Artwork loaded: \(track.title)")
                        #endif
                    }
                } else {
                    #if DEBUG
                    print("⚠️ Artwork load failed: \(track.title)")
                    #endif
                }
            }
        } else if let image = UIImage(named: track.artwork) {
            // Local asset
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { requestedSize in
                let renderer = UIGraphicsImageRenderer(size: requestedSize)
                return renderer.image { context in
                    image.draw(in: CGRect(origin: .zero, size: requestedSize))
                }
            }
            nowPlayingArtwork = artwork
            updateNowPlayingInfo()
        } else {
            nowPlayingArtwork = nil
            updateNowPlayingInfo()
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
        var needsNowPlayingUpdate = false

        // Track changes
        if let track = snapshot.track {
            let trackChanged = track.id != currentTrack.id
            currentTrack = track
            if trackChanged {
                refreshArtwork(for: track)
                needsNowPlayingUpdate = true
            }
            if let index = snapshot.queueIndex {
                currentQueueIndex = index
            } else if trackChanged {
                currentQueueIndex = -1
            }
        } else if snapshot.queueIndex == nil {
            currentQueueIndex = -1
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

        // Position and duration (update locally, but don't spam Now Playing)
        playbackPosition = snapshot.currentTime
        duration = snapshot.duration

        // Only update Now Playing when something meaningful changed
        if needsNowPlayingUpdate {
            updateNowPlayingInfo()
        } else {
            // Just update the elapsed time (lightweight operation)
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1 : 0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }

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
