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
    
    /// Returns true if there's an active track (not idle and has valid duration)
    var hasActiveTrack: Bool {
        playbackStatus != .idle && duration > 0
    }

    private let playbackCoordinator = PlaybackCoordinator.shared
    private let queueManager = QueueManager.shared
    private let audioSession = AVAudioSession.sharedInstance()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private var currentQueueIndex: Int = -1
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var lastPublishedStatus: PlaybackStatus = .idle

    /// Flag to prevent time observer updates during user scrubbing (prevents slider jitter)
    var isSeeking: Bool = false

    // MARK: - Persistence Keys
    private let kSavedTrack = "mixbridge.savedTrack"
    private let kSavedPosition = "mixbridge.savedPosition"
    private let kSavedDuration = "mixbridge.savedDuration"

    private override init() {
        // Initialize with placeholder initially
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
        
        // Load saved state
        loadPlaybackState()
        
        // If no active track after loading local state, try fetching remote history
        if !hasActiveTrack {
            Task {
                await fetchRemoteHistoryIfNeeded()
            }
        }
        
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        // Observe backgrounding to save state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    // MARK: - Persistence
    
    private func savePlaybackState() {
        // Save current track
        if let encoded = try? JSONEncoder().encode(currentTrack) {
            UserDefaults.standard.set(encoded, forKey: kSavedTrack)
        }
        
        // Save position and duration
        UserDefaults.standard.set(playbackPosition, forKey: kSavedPosition)
        UserDefaults.standard.set(duration, forKey: kSavedDuration)
    }
    
    private func loadPlaybackState() {
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
                // Update remote command center
                updateNowPlayingInfo(playbackRate: 0)
            }
        }
    }
    
    private func fetchRemoteHistoryIfNeeded() async {
        // Double check we still need it
        if hasActiveTrack { return }
        
        // We need authentication to fetch history
        // AuthManager is an Observable, but we can access shared instance or keychain
        guard let userId = KeychainManager.shared.getUserId() else { return }
        
        do {
            let history = try await ConvexService.shared.getPlayHistory(userId: userId, limit: 1)
            if let lastPlayed = history.first {
                let trackData = lastPlayed.trackData
                let artworkUrl = trackData.artwork_url ?? trackData.user.avatar_url ?? ""
                let highQualityArtwork = artworkUrl.upgradeArtworkQuality() // Need to make sure this string extension is available or handle it
                
                // String+SoundCloud extension might not be imported here implicitly if it's in extensions
                // But 'artwork' is a string. 
                
                // Actually, let's just use the artwork URL as is, assuming upgradeArtworkQuality is available on String
                // Wait, String extensions are usually global.
                
                let track = Track(
                    id: String(trackData.id),
                    title: trackData.title,
                    artist: trackData.user.username,
                    album: trackData.genre ?? "",
                    artwork: highQualityArtwork, // Hope this works
                    duration: Double(trackData.duration) / 1000.0 // Convert ms to seconds
                )
                
                await MainActor.run {
                    // Only update if we still don't have an active track
                    if !self.hasActiveTrack {
                        self.currentTrack = track
                        self.duration = track.duration
                        self.playbackPosition = 0
                        self.playbackStatus = .paused // Ready to play
                        self.updateNowPlayingInfo(playbackRate: 0)
                        self.savePlaybackState() // Save so we don't fetch next time
                    }
                }
            }
        } catch {
            print("Failed to fetch remote history: \(error)")
        }
    }
    
    @objc private func handleAppBackground() {
        savePlaybackState()
    }

    // MARK: - Public API

    func play(track: Track, soundCloudTrack: SoundCloudTrack? = nil, queueIndex: Int? = nil, startTime: Double? = nil) {
        // ⚡ CRITICAL FIX: Don't update currentTrack yet - wait for successful playback
        // Only update status to loading to show the user something is happening
        playbackStatus = .loading

        // Store queue index
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
            soundCloudTrack: soundCloudTrack ?? queueManager.soundCloudTrack(for: track.id),
            queueIndex: queueIndex,
            startTime: startTime
        )

        // NOTE: currentTrack will be updated when we receive successful snapshot from PlaybackCoordinator
        // This ensures tight coupling between UI and actual playback state
    }

    func playFromQueue(index: Int) {
        guard queueManager.queueTracks.indices.contains(index) else { return }
        let track = queueManager.queueTracks[index]
        play(track: track, soundCloudTrack: queueManager.soundCloudTrack(for: track.id), queueIndex: index)
    }

    func togglePlayback() {
        // Check if we need to restore playback from a saved state (coordinator empty but we have a track)
        if playbackStatus == .paused && duration > 0 && !playbackCoordinator.hasLoadedItems {
             // Try to resume/restart the current track if coordinator is empty
             // This handles the case where we loaded state but haven't loaded the player
             play(track: currentTrack, startTime: playbackPosition)
             return
        }
        
        playbackCoordinator.togglePlayback()
    }

    func pause() {
        playbackCoordinator.pause()
        updateNowPlayingInfo(playbackRate: 0)
        savePlaybackState()
    }

    func resume() {
        try? activateAudioSession()
        playbackCoordinator.resume()
        updateNowPlayingInfo(playbackRate: 1)
    }

    /// Seeks to a specific time position.
    /// When called from UI scrubbing, the isSeeking flag prevents time observer conflicts.
    ///
    /// - Parameter time: The target playback position in seconds
    func seek(to time: Double) {
        // ⚡ CRITICAL: Set seeking flag to prevent time observer jitter
        isSeeking = true

        // Update position locally immediately for responsive UI
        playbackPosition = time

        // Perform actual seek
        playbackCoordinator.seek(to: time)

        // ⚡ CRITICAL: Clear seeking flag after a brief delay
        // This allows the seek to complete before time observer resumes
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            self.isSeeking = false

            #if DEBUG
            print("✅ Seeking flag cleared, time observer resumed")
            #endif
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

            self.seek(to: positionEvent.positionTime)
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
            self.seek(to: newPosition)
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
            self.seek(to: newPosition)
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
        // Only log meaningful updates, not elapsed time changes
        // Uncomment below for verbose logging:
        // print("🎨 Now Playing updated: \(currentTrack.title)")
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

            #if DEBUG
            print("🎨 Now Playing updated: \(currentTrack.title) [\(playbackStatus)]")
            #endif
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
