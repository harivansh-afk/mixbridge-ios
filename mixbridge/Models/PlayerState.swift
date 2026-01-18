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

    struct PendingPlayback {
        let trackId: String
        var uiUpdated: InteractionMetrics.Token?
        var startedPlaying: InteractionMetrics.Token?
    }

    enum PendingNavigationKind {
        case next(previousTrackId: String)
        case previous(previousTrackId: String)
    }

    var pendingPlayback: PendingPlayback?
    var pendingToggle: InteractionMetrics.Token?
    var pendingNavigation: (kind: PendingNavigationKind, token: InteractionMetrics.Token)?
    var pendingSeek: (target: Double, token: InteractionMetrics.Token)?

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

    /// Enable automatic crossfade between tracks (default: true)
    var mixEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(mixEnabled, forKey: kMixEnabled)
            playbackCoordinator.mixEnabled = mixEnabled
        }
    }

    // MARK: - DJ Mode Settings

    /// Enable DJ mode for beat-aware transitions (default: true)
    var djEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(djEnabled, forKey: kDJEnabled)
        }
    }

    /// If true, DJ mode will NOT fall back to the basic AVPlayer mix engine.
    /// Useful for testing to ensure you’re actually using the DJ backend.
    var djStrictMode: Bool = false {
        didSet {
            UserDefaults.standard.set(djStrictMode, forKey: kDJStrictMode)
        }
    }

    /// Number of upcoming tracks to download ahead when DJ mode is enabled (default: 2)
    var djDownloadAheadCount: Int = 2 {
        didSet {
            let clamped = max(1, min(5, djDownloadAheadCount))
            if clamped != djDownloadAheadCount {
                djDownloadAheadCount = clamped
                return
            }
            UserDefaults.standard.set(djDownloadAheadCount, forKey: kDJDownloadAheadCount)
        }
    }

    /// Automatically download upcoming tracks when DJ mode is enabled (default: true)
    var djAutoDownloadAhead: Bool = true {
        didSet {
            UserDefaults.standard.set(djAutoDownloadAhead, forKey: kDJAutoDownloadAhead)
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

    let playbackCoordinator = PlaybackCoordinator.shared
    let queueManager = QueueManager.shared
    let audioSession = AVAudioSession.sharedInstance()
    let commandCenter = MPRemoteCommandCenter.shared()
    var remoteCommandTargets = RemoteCommandTargets()

    var _currentQueueIndex: Int = -1

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

    var nowPlayingArtwork: MPMediaItemArtwork?
    var artworkTask: Task<Void, Never>?
    var saveStateTask: Task<Void, Never>?
    var lastPublishedStatus: PlaybackStatus = .idle
    var wasPlayingBeforeInterruption: Bool = false

    /// Flag to prevent time observer updates during user scrubbing (prevents slider jitter)
    var isSeeking: Bool = false

    // MARK: - Persistence Keys
    let kSavedTrack = "mixbridge.savedTrack"
    let kSavedPosition = "mixbridge.savedPosition"
    let kSavedDuration = "mixbridge.savedDuration"
    let kMixEnabled = "mixbridge.mixEnabled"
    let kDJStrictMode = "mixbridge.djStrictMode"
    let kCrossfadeSeconds = "mixbridge.crossfadeSeconds"
    let kPrewarmSeconds = "mixbridge.prewarmSeconds"
    let kFadeCurve = "mixbridge.fadeCurve"
    let kDJEnabled = "mixbridge.djEnabled"
    let kDJDownloadAheadCount = "mixbridge.djDownloadAheadCount"
    let kDJAutoDownloadAhead = "mixbridge.djAutoDownloadAhead"

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

        // We currently manage Now Playing via `MPNowPlayingInfoCenter` and remote commands via
        // `MPRemoteCommandCenter`. We are not adopting `MPNowPlayingSession` yet because this project
        // supports iOS versions where it may not be available and our playback model is still evolving.
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

    @MainActor deinit {
        NotificationCenter.default.removeObserver(self)
        teardownRemoteCommands()
    }
}
