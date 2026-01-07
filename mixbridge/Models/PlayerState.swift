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
import MixBridgeDB

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

    // MARK: - Perf / Interaction Timing

    private struct PendingPlayback {
        let trackId: String
        var uiUpdated: InteractionMetrics.Token?
        var startedPlaying: InteractionMetrics.Token?
    }

    private enum PendingNavigationKind {
        case next(previousTrackId: String)
        case previous(previousTrackId: String)
    }

    private var pendingPlayback: PendingPlayback?
    private var pendingToggle: InteractionMetrics.Token?
    private var pendingNavigation: (kind: PendingNavigationKind, token: InteractionMetrics.Token)?
    private var pendingSeek: (target: Double, token: InteractionMetrics.Token)?

    // MARK: - Crossfade Visual State

    /// Current crossfade progress (0.0 to 1.0) for visual transitions
    var crossfadeProgress: Double = 0

    /// Whether a crossfade is currently active
    var isCrossfading: Bool = false

    /// The artwork we're crossfading FROM.
    /// This is captured at crossfade start so visuals don't change `from` mid-transition
    /// when `currentTrack` swaps at the end.
    var crossfadeFromArtwork: String = ""

    /// The track we're crossfading TO (for artwork morph effect)
    var crossfadeNextTrack: Track? = nil

    /// Next track's playback position during crossfade (for smooth progress bar transition)
    var crossfadeNextPosition: Double = 0

    /// Next track's duration during crossfade (for smooth progress bar transition)
    var crossfadeNextDuration: Double = 0

    // MARK: - Mix Mode Settings

    /// Enable automatic crossfade between tracks (default: false)
    var mixEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(mixEnabled, forKey: kMixEnabled)
            playbackCoordinator.mixEnabled = mixEnabled
        }
    }

    /// Crossfade duration in seconds (default: 6, clamped to 1...20)
    var crossfadeSeconds: Double = 6 {
        didSet {
            let clamped = max(1, min(20, crossfadeSeconds))
            if clamped != crossfadeSeconds {
                crossfadeSeconds = clamped
                return
            }
            UserDefaults.standard.set(crossfadeSeconds, forKey: kCrossfadeSeconds)
            playbackCoordinator.crossfadeSeconds = crossfadeSeconds
        }
    }

    /// Prewarm lead time in seconds (default: 15, clamped to 5...60)
    var prewarmSeconds: Double = 15 {
        didSet {
            let clamped = max(5, min(60, prewarmSeconds))
            if clamped != prewarmSeconds {
                prewarmSeconds = clamped
                return
            }
            UserDefaults.standard.set(prewarmSeconds, forKey: kPrewarmSeconds)
            playbackCoordinator.prewarmSeconds = prewarmSeconds
        }
    }

    /// Fade curve type for crossfade transitions (default: equalPower)
    var fadeCurve: FadeCurve = .equalPower {
        didSet {
            UserDefaults.standard.set(fadeCurve.rawValue, forKey: kFadeCurve)
            playbackCoordinator.fadeCurve = fadeCurve
        }
    }
    
    /// Returns true if there's an active track (not idle and has valid duration)
    var hasActiveTrack: Bool {
        // Treat any non-idle state as active so the mini player appears instantly,
        // even before AVPlayer has reported a duration.
        playbackStatus != .idle
    }

    private let playbackCoordinator = PlaybackCoordinator.shared
    private let queueManager = QueueManager.shared
    private let audioSession = AVAudioSession.sharedInstance()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private var _currentQueueIndex: Int = -1

    /// Public getter for the current queue index (-1 if not playing from queue)
    var currentQueueIndex: Int { _currentQueueIndex }

    /// Returns true if there's a next track available in the queue
    /// This considers the current track's position even if played from outside the queue
    var canPlayNext: Bool {
        // First check explicit queue index
        if _currentQueueIndex >= 0 {
            return queueManager.canPlayNext(from: _currentQueueIndex)
        }
        // Fallback: check if current track is in queue
        if let position = queueManager.queuePosition(for: currentTrack.id) {
            return position.hasNext
        }
        // Last resort: check if queue has any tracks
        return queueManager.hasQueue
    }

    /// Returns true if there's a previous track available in the queue
    /// This considers the current track's position even if played from outside the queue
    var canPlayPrevious: Bool {
        // First check explicit queue index
        if _currentQueueIndex >= 0 {
            return queueManager.canPlayPrevious(from: _currentQueueIndex)
        }
        // Fallback: check if current track is in queue
        if let position = queueManager.queuePosition(for: currentTrack.id) {
            return position.hasPrevious
        }
        return false
    }

    /// Returns true if the current track is in the queue (regardless of entry point)
    var isCurrentTrackInQueue: Bool {
        queueManager.isInQueue(currentTrack.id)
    }

    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var saveStateTask: Task<Void, Never>?
    private var lastPublishedStatus: PlaybackStatus = .idle

    /// Flag to prevent time observer updates during user scrubbing (prevents slider jitter)
    var isSeeking: Bool = false

    // MARK: - Persistence Keys
    private let kSavedTrack = "mixbridge.savedTrack"
    private let kSavedPosition = "mixbridge.savedPosition"
    private let kSavedDuration = "mixbridge.savedDuration"
    private let kMixEnabled = "mixbridge.mixEnabled"
    private let kCrossfadeSeconds = "mixbridge.crossfadeSeconds"
    private let kPrewarmSeconds = "mixbridge.prewarmSeconds"
    private let kFadeCurve = "mixbridge.fadeCurve"

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

        // Load Mix Mode settings from UserDefaults
        loadMixSettings()

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

    private func loadMixSettings() {
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
           let curve = FadeCurve(rawValue: curveRaw) {
            fadeCurve = curve
        }

        // Sync to coordinator
        playbackCoordinator.mixEnabled = mixEnabled
        playbackCoordinator.crossfadeSeconds = crossfadeSeconds
        playbackCoordinator.prewarmSeconds = prewarmSeconds
        playbackCoordinator.fadeCurve = fadeCurve
    }

    private func scheduleSavePlaybackState(immediate: Bool = false) {
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
                // Load artwork and update Now Playing info
                refreshArtwork(for: savedTrack)
                updateNowPlayingInfo(playbackRate: 0)
            }
        }
    }
    
    private func fetchRemoteHistoryIfNeeded() async {
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

    private func setDefaultTrack(from soundCloudTrack: SoundCloudTrack) async {
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
    
    @objc private func handleAppBackground() {
        scheduleSavePlaybackState(immediate: true)
    }

    // MARK: - Public API

    func play(track: Track, soundCloudTrack: SoundCloudTrack? = nil, queueIndex: Int? = nil, startTime: Double? = nil) {
        // Instant UI: update the selected track immediately and show loading.
        // Playback correctness is enforced by PlaybackCoordinator snapshots.
        if track.id != currentTrack.id {
            currentTrack = track
            duration = max(track.duration, 0)
            if let startTime { playbackPosition = startTime }
            refreshArtwork(for: track)
            updateNowPlayingInfo(playbackRate: 0)
        }

        playbackStatus = .loading

        pendingPlayback = PendingPlayback(
            trackId: track.id,
            uiUpdated: InteractionMetrics.begin("player_play_tap_to_ui", context: track.title),
            startedPlaying: InteractionMetrics.begin("player_play_tap_to_playing", context: track.title)
        )

        // Store queue index
        if let explicitIndex = queueIndex {
            _currentQueueIndex = explicitIndex
        } else if let inferredIndex = queueManager.indexOfTrack(withId: track.id) {
            _currentQueueIndex = inferredIndex
        } else {
            _currentQueueIndex = -1
        }

        try? activateAudioSession()
        playbackCoordinator.play(
            track: track,
            soundCloudTrack: soundCloudTrack ?? queueManager.soundCloudTrack(for: track.id),
            queueIndex: queueIndex,
            startTime: startTime
        )
    }

    /// Play from a list context - handles queue setup/append automatically
    /// - Parameters:
    ///   - items: Full list of TrackItems
    ///   - startIndex: Which track was clicked (0-based index)
    ///   - shuffle: If true, shuffles the list before setting queue
    func playFromList(items: [TrackItem], startIndex: Int, shuffle: Bool = false) {
        guard !items.isEmpty else { return }
        guard startIndex >= 0 && startIndex < items.count else { return }

        var itemsToQueue = items
        var playIndex = startIndex

        // Shuffle if requested
        if shuffle {
            itemsToQueue = items.shuffled()
            playIndex = 0  // Start from beginning of shuffled list
        }

        // Get the track to play
        let trackToPlay = itemsToQueue[playIndex]

        // Queue invariant: current track is never in the queue.
        // We replace the upcoming queue with tracks AFTER the tapped track.
        queueManager.setQueue(items: itemsToQueue, startIndex: playIndex)

        // Play immediately (do not await queue persistence/sync).
        play(
            track: trackToPlay.track,
            soundCloudTrack: trackToPlay.soundCloudTrack,
            queueIndex: nil
        )
    }

    func playFromQueue(index: Int) {
        guard queueManager.queueTracks.indices.contains(index) else { return }
        let track = queueManager.queueTracks[index]
        play(track: track, soundCloudTrack: queueManager.soundCloudTrack(for: track.id), queueIndex: index)
    }

    func togglePlayback() {
        pendingToggle = InteractionMetrics.begin("player_toggle_tap")
        // Check if we need to restore playback from a saved state (coordinator empty but we have a track)
        if playbackStatus == .paused && duration > 0 && !playbackCoordinator.hasLoadedItems {
             // Try to resume/restart the current track if coordinator is empty
             // This handles the case where we loaded state but haven't loaded the player
             play(track: currentTrack, startTime: playbackPosition)
             return
        }

        // Optimistic UI: flip immediately, then let the coordinator reconcile actual playback.
        // This makes play/pause feel “instant” even if AVPlayer takes a beat to start/stop.
        if isPlaying {
            isPlaying = false
            playbackStatus = .paused
            updateNowPlayingInfo(playbackRate: 0)
        } else if playbackStatus == .paused || playbackStatus == .ready || playbackStatus == .playing {
            isPlaying = true
            playbackStatus = .playing
            updateNowPlayingInfo(playbackRate: 1)
        }

        playbackCoordinator.togglePlayback()
    }

    func pause() {
        playbackCoordinator.pause()
        updateNowPlayingInfo(playbackRate: 0)
        scheduleSavePlaybackState(immediate: true)
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
        pendingSeek = (target: time, token: InteractionMetrics.begin("player_seek_tap_to_settle"))
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

            logDebug(.playback, "Seeking flag cleared, time observer resumed")
        }

        // Update Now Playing info with new position
        updateNowPlayingInfo()
    }

    func playNextFromQueue() {
        pendingNavigation = (kind: .next(previousTrackId: currentTrack.id), token: InteractionMetrics.begin("player_next_tap"))
        playbackCoordinator.playNext(manual: true)
    }

    func playPreviousFromQueue() {
        pendingNavigation = (kind: .previous(previousTrackId: currentTrack.id), token: InteractionMetrics.begin("player_previous_tap"))
        playbackCoordinator.playPrevious()
    }

    /// Synchronize the queue index with the current track's position in the queue
    /// Call this after the queue loads to ensure navigation works correctly
    func syncQueueIndex() {
        // If we already have a valid index, verify it's still correct
        if _currentQueueIndex >= 0 && _currentQueueIndex < queueManager.queueTracks.count {
            // Check if the track at our index still matches
            let trackAtIndex = queueManager.queueTracks[_currentQueueIndex]
            if trackAtIndex.id == currentTrack.id {
                return // Index is still valid
            }
        }

        // Try to find current track in queue
        if let inferredIndex = queueManager.indexOfTrack(withId: currentTrack.id) {
            _currentQueueIndex = inferredIndex
            logDebug(.playback, "Synced queue index to \(inferredIndex) for track: \(self.currentTrack.title)")
        } else {
            _currentQueueIndex = -1
        }
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

            logInfo(.playback, "Audio session configured successfully")
        } catch let error as NSError {
            // OSStatus -50 means invalid parameter, but often non-fatal
            if error.code == -50 {
                logWarning(.playback, "Audio session configuration warning (non-fatal): \(error.localizedDescription)")
            } else {
                logError(.playback, "Failed to configure audio session: \(error.localizedDescription)")
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

        // Disable skip commands so iOS shows next/previous track buttons instead
        // (Skip buttons are for podcast-style apps, not music players)
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false

        // Disable commands we don't support
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
    }

    // MARK: - Notifications

    /// Track if we were playing before interruption (for reliable recovery)
    private var wasPlayingBeforeInterruption: Bool = false

    @MainActor
    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            let wasSuspended = info[AVAudioSessionInterruptionWasSuspendedKey] as? Bool ?? false
            
            // Remember if we were playing before interruption
            let wasPlaying = isPlaying
            wasPlayingBeforeInterruption = wasPlaying
            
            logInfo(.playback, "Audio interruption began (wasSuspended: \(wasSuspended), wasPlaying: \(wasPlaying))")
            
            // For wasSuspended interruptions (like overlay windows), auto-resume immediately
            // The OS pauses the player but we want to keep playing
            if wasSuspended && wasPlaying {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                    do {
                        try self.activateAudioSession()
                    } catch {
                        logWarning(.playback, "Failed to reactivate after wasSuspended: \(error)")
                    }
                    self.resume()
                    logInfo(.playback, "Auto-resumed after wasSuspended interruption")
                }
                return
            }
            
            // For real interruptions (phone calls, Siri, etc.), pause properly
            if !wasSuspended {
                playbackCoordinator.pause()
                updateNowPlayingInfo(playbackRate: 0)
                scheduleSavePlaybackState(immediate: true)
            }

        case .ended:
            logInfo(.playback, "Audio interruption ended")

            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)

            // Try to resume if:
            // 1. iOS says we should resume, OR
            // 2. We were playing before and have an active track
            if options.contains(.shouldResume) || (wasPlayingBeforeInterruption && hasActiveTrack) {
                // Delay resume slightly to ensure audio session is fully restored
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms delay

                    // Re-activate audio session
                    do {
                        try self.activateAudioSession()
                    } catch {
                        logWarning(.playback, "Failed to reactivate audio session: \(error)")
                    }

                    // Resume playback
                    if self.wasPlayingBeforeInterruption {
                        self.resume()
                        logInfo(.playback, "Resumed playback after interruption")
                    }
                }
            }

            wasPlayingBeforeInterruption = false

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

        logInfo(.playback, "Audio route changed: \(reason.rawValue)")

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged, Bluetooth disconnected, etc.
            pause()

        case .newDeviceAvailable:
            // New device connected - could auto-resume if we were interrupted
            // But generally safer to let user manually resume
            logInfo(.playback, "New audio device available")

        case .categoryChange:
            // Audio category changed by another app
            // Re-assert our audio session
            Task { @MainActor in
                try? self.activateAudioSession()
            }

        default:
            break
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
                        logDebug(.playback, "Artwork loaded: \(track.title)")
                    }
                } else {
                    logWarning(.playback, "Artwork load failed: \(track.title)")
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
    }

    func playbackCoordinator(_ coordinator: PlaybackCoordinator, didEncounter error: Error) {
        handlePlaybackFailure(error)
        lastPublishedStatus = .failed(error.localizedDescription)
    }
}
