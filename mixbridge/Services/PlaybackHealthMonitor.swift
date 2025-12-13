//
//  PlaybackHealthMonitor.swift
//  mixbridge
//
//  Isolated service for monitoring playback health and automatic recovery.
//  Handles: item status failures, buffer starvation, stalls, and stream recovery.
//

import AVFoundation
import Combine

// MARK: - Protocols

@MainActor
protocol PlaybackHealthMonitorDelegate: AnyObject {
    /// Called when AVPlayerItem enters failed state during playback
    func healthMonitor(_ monitor: PlaybackHealthMonitor, itemDidFail item: AVPlayerItem, error: Error?)

    /// Called when playback stalls due to buffer issues
    func healthMonitor(_ monitor: PlaybackHealthMonitor, playbackDidStall item: AVPlayerItem)

    /// Called when playback recovers from a stall
    func healthMonitor(_ monitor: PlaybackHealthMonitor, playbackDidRecover item: AVPlayerItem)

    /// Called when stream URL needs refresh (expired or failed)
    func healthMonitorNeedsStreamRefresh(_ monitor: PlaybackHealthMonitor, for trackId: String)

    /// Called when automatic recovery attempts are exhausted
    func healthMonitor(_ monitor: PlaybackHealthMonitor, recoveryFailedFor item: AVPlayerItem, attempts: Int)
}

// MARK: - Health Monitor

@MainActor
final class PlaybackHealthMonitor {

    // MARK: - Configuration

    struct Configuration {
        /// Maximum automatic recovery attempts before giving up
        let maxRecoveryAttempts: Int

        /// Time to wait before considering playback truly stalled (seconds)
        let stallDetectionThreshold: TimeInterval

        /// Base delay between recovery attempts (doubles each attempt)
        let baseRecoveryDelay: TimeInterval

        /// Maximum time to wait for buffer recovery before taking action
        let bufferRecoveryTimeout: TimeInterval

        static let `default` = Configuration(
            maxRecoveryAttempts: 3,
            stallDetectionThreshold: 5.0,  // ⚡ Increased from 2.0 - less aggressive
            baseRecoveryDelay: 1.0,        // ⚡ Increased from 0.5 - give more time
            bufferRecoveryTimeout: 15.0    // ⚡ Increased from 10.0 - more patience
        )
    }

    // MARK: - Properties

    weak var delegate: PlaybackHealthMonitorDelegate?

    private let player: AVQueuePlayer
    private let configuration: Configuration

    // Observers
    private var itemStatusObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var bufferFullObservation: NSKeyValueObservation?
    private var bufferKeepUpObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var reasonForWaitingObservation: NSKeyValueObservation?

    // State tracking
    private var currentItem: AVPlayerItem?
    private var currentTrackId: String?
    private var recoveryAttempts: Int = 0
    private var isRecovering: Bool = false
    private var stallDetectionTask: Task<Void, Never>?
    private var bufferRecoveryTask: Task<Void, Never>?
    private var lastKnownPlaybackTime: Double = 0
    private var wasPlayingBeforeStall: Bool = false
    private var playbackStartTime: Date?  // ⚡ Track when playback started to avoid false stalls

    // MARK: - Initialization

    init(player: AVQueuePlayer, configuration: Configuration = .default) {
        self.player = player
        self.configuration = configuration

        setupPlayerObservers()

        #if DEBUG
        print("🏥 PlaybackHealthMonitor initialized")
        #endif
    }

    // MARK: - Public API

    /// Start monitoring a specific player item
    func startMonitoring(item: AVPlayerItem, trackId: String) {
        stopMonitoring()

        currentItem = item
        currentTrackId = trackId
        recoveryAttempts = 0
        isRecovering = false
        playbackStartTime = nil  // ⚡ Reset for new track
        wasPlayingBeforeStall = false  // ⚡ Reset for new track

        setupItemObservers(for: item)

        #if DEBUG
        print("🏥 Started monitoring track: \(trackId)")
        #endif
    }

    /// Stop monitoring current item
    func stopMonitoring() {
        stallDetectionTask?.cancel()
        stallDetectionTask = nil
        bufferRecoveryTask?.cancel()
        bufferRecoveryTask = nil

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        bufferFullObservation?.invalidate()
        bufferFullObservation = nil
        bufferKeepUpObservation?.invalidate()
        bufferKeepUpObservation = nil

        currentItem = nil
        currentTrackId = nil
        recoveryAttempts = 0
        isRecovering = false
        playbackStartTime = nil  // ⚡ Reset
        wasPlayingBeforeStall = false  // ⚡ Reset

        #if DEBUG
        print("🏥 Stopped monitoring")
        #endif
    }

    /// Reset recovery counter (call after successful playback)
    func resetRecoveryState() {
        recoveryAttempts = 0
        isRecovering = false
    }

    /// Notify monitor that playback resumed successfully
    func playbackDidResume() {
        resetRecoveryState()
        stallDetectionTask?.cancel()
        stallDetectionTask = nil
        bufferRecoveryTask?.cancel()
        bufferRecoveryTask = nil
    }

    // MARK: - Player Observers

    private func setupPlayerObservers() {
        // Observe player's timeControlStatus
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new, .old]) { [weak self] player, change in
            Task { @MainActor in
                self?.handleTimeControlStatusChange(player.timeControlStatus)
            }
        }

        // Observe reason for waiting (gives detailed stall info)
        reasonForWaitingObservation = player.observe(\.reasonForWaitingToPlay, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.handleReasonForWaitingChange(player.reasonForWaitingToPlay)
            }
        }
    }

    // MARK: - Item Observers

    private func setupItemObservers(for item: AVPlayerItem) {
        // Observe item status for failures
        itemStatusObservation = item.observe(\.status, options: [.new, .old]) { [weak self] item, change in
            Task { @MainActor in
                self?.handleItemStatusChange(item, status: item.status)
            }
        }

        // Observe buffer empty state
        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, change in
            Task { @MainActor in
                if item.isPlaybackBufferEmpty {
                    self?.handleBufferEmpty(item)
                }
            }
        }

        // Observe buffer full state
        bufferFullObservation = item.observe(\.isPlaybackBufferFull, options: [.new]) { [weak self] item, change in
            Task { @MainActor in
                if item.isPlaybackBufferFull {
                    self?.handleBufferFull(item)
                }
            }
        }

        // Observe likely to keep up (buffer health indicator)
        bufferKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, change in
            Task { @MainActor in
                self?.handleKeepUpChange(item, likelyToKeepUp: item.isPlaybackLikelyToKeepUp)
            }
        }
    }

    // MARK: - Status Handlers

    private func handleItemStatusChange(_ item: AVPlayerItem, status: AVPlayerItem.Status) {
        switch status {
        case .failed:
            #if DEBUG
            print("🏥 ❌ AVPlayerItem FAILED: \(item.error?.localizedDescription ?? "Unknown error")")
            if let error = item.error as NSError? {
                print("   Error domain: \(error.domain), code: \(error.code)")
                if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                    print("   Underlying: \(underlying.domain), code: \(underlying.code)")
                }
            }
            #endif

            delegate?.healthMonitor(self, itemDidFail: item, error: item.error)
            attemptRecovery(for: item, reason: .itemFailed)

        case .readyToPlay:
            #if DEBUG
            print("🏥 ✅ AVPlayerItem ready to play")
            #endif
            // Reset recovery state on successful ready
            if isRecovering {
                isRecovering = false
                recoveryAttempts = 0
                delegate?.healthMonitor(self, playbackDidRecover: item)
            }

        case .unknown:
            #if DEBUG
            print("🏥 ⏳ AVPlayerItem status unknown")
            #endif

        @unknown default:
            break
        }
    }

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            #if DEBUG
            print("🏥 ▶️ Player is playing")
            #endif
            stallDetectionTask?.cancel()
            stallDetectionTask = nil
            wasPlayingBeforeStall = true

            // ⚡ Track when playback actually started
            if playbackStartTime == nil {
                playbackStartTime = Date()
            }

            if isRecovering, let item = currentItem {
                isRecovering = false
                recoveryAttempts = 0
                delegate?.healthMonitor(self, playbackDidRecover: item)
            }

        case .paused:
            #if DEBUG
            print("🏥 ⏸️ Player is paused")
            #endif
            // ⚡ Don't reset wasPlayingBeforeStall on pause - user might resume

        case .waitingToPlayAtSpecifiedRate:
            #if DEBUG
            print("🏥 ⏳ Player is waiting to play")
            #endif

            // ⚡ CRITICAL: Only start stall detection if:
            // 1. We were previously playing (not during initial load)
            // 2. We've been playing for at least 3 seconds (avoid false positives during startup)
            if wasPlayingBeforeStall {
                let timeSinceStart = playbackStartTime.map { Date().timeIntervalSince($0) } ?? 0
                if timeSinceStart > 3.0 {
                    startStallDetection()
                } else {
                    #if DEBUG
                    print("🏥 Skipping stall detection - playback just started (\(String(format: "%.1f", timeSinceStart))s ago)")
                    #endif
                }
            }

        @unknown default:
            break
        }
    }

    private func handleReasonForWaitingChange(_ reason: AVPlayer.WaitingReason?) {
        guard let reason = reason else { return }

        #if DEBUG
        print("🏥 Waiting reason: \(reason.rawValue)")
        #endif

        switch reason {
        case .toMinimizeStalls:
            // Buffering to prevent future stalls - this is normal
            break

        case .evaluatingBufferingRate:
            // Evaluating if buffer can keep up - monitor this
            break

        case .noItemToPlay:
            // No item in queue - this is a different issue
            #if DEBUG
            print("🏥 ⚠️ No item to play!")
            #endif

        case .interstitialEvent:
            // Interstitial playback - ignore
            break

        default:
            break
        }
    }

    private func handleBufferEmpty(_ item: AVPlayerItem) {
        #if DEBUG
        print("🏥 ⚠️ Buffer EMPTY for item")
        #endif

        // Start buffer recovery timeout
        startBufferRecoveryTimeout(for: item)
    }

    private func handleBufferFull(_ item: AVPlayerItem) {
        #if DEBUG
        print("🏥 ✅ Buffer FULL")
        #endif

        bufferRecoveryTask?.cancel()
        bufferRecoveryTask = nil
    }

    private func handleKeepUpChange(_ item: AVPlayerItem, likelyToKeepUp: Bool) {
        if likelyToKeepUp {
            #if DEBUG
            print("🏥 ✅ Playback likely to keep up")
            #endif

            bufferRecoveryTask?.cancel()
            bufferRecoveryTask = nil

            // If we were recovering, mark success
            if isRecovering {
                isRecovering = false
                recoveryAttempts = 0
                delegate?.healthMonitor(self, playbackDidRecover: item)
            }
        } else {
            #if DEBUG
            print("🏥 ⚠️ Playback may NOT keep up")
            #endif
        }
    }

    // MARK: - Stall Detection

    private func startStallDetection() {
        stallDetectionTask?.cancel()

        stallDetectionTask = Task { [weak self, configuration] in
            guard let self = self else { return }

            // Wait for stall threshold
            try? await Task.sleep(nanoseconds: UInt64(configuration.stallDetectionThreshold * 1_000_000_000))

            guard !Task.isCancelled else { return }

            // Check if still waiting
            if self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                #if DEBUG
                print("🏥 ⚠️ Stall detected! Player waiting for \(configuration.stallDetectionThreshold)s")
                #endif

                if let item = self.currentItem {
                    self.delegate?.healthMonitor(self, playbackDidStall: item)
                    self.attemptRecovery(for: item, reason: .stalled)
                }
            }
        }
    }

    private func startBufferRecoveryTimeout(for item: AVPlayerItem) {
        bufferRecoveryTask?.cancel()

        bufferRecoveryTask = Task { [weak self, configuration] in
            guard let self = self else { return }

            // Wait for buffer recovery timeout
            try? await Task.sleep(nanoseconds: UInt64(configuration.bufferRecoveryTimeout * 1_000_000_000))

            guard !Task.isCancelled else { return }

            // Check if buffer still empty
            if item.isPlaybackBufferEmpty && !item.isPlaybackLikelyToKeepUp {
                #if DEBUG
                print("🏥 ⚠️ Buffer recovery timeout! Empty for \(configuration.bufferRecoveryTimeout)s")
                #endif

                self.delegate?.healthMonitor(self, playbackDidStall: item)
                self.attemptRecovery(for: item, reason: .bufferTimeout)
            }
        }
    }

    // MARK: - Recovery

    private enum RecoveryReason {
        case itemFailed
        case stalled
        case bufferTimeout
    }

    private func attemptRecovery(for item: AVPlayerItem, reason: RecoveryReason) {
        guard !isRecovering else {
            #if DEBUG
            print("🏥 Recovery already in progress")
            #endif
            return
        }

        recoveryAttempts += 1

        if recoveryAttempts > configuration.maxRecoveryAttempts {
            #if DEBUG
            print("🏥 ❌ Max recovery attempts (\(configuration.maxRecoveryAttempts)) reached")
            #endif
            delegate?.healthMonitor(self, recoveryFailedFor: item, attempts: recoveryAttempts)
            return
        }

        isRecovering = true

        #if DEBUG
        print("🏥 🔄 Attempting recovery #\(recoveryAttempts) for reason: \(reason)")
        #endif

        Task { [weak self, configuration] in
            guard let self = self, let trackId = self.currentTrackId else { return }

            // Exponential backoff delay
            let delay = configuration.baseRecoveryDelay * pow(2, Double(self.recoveryAttempts - 1))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            switch reason {
            case .itemFailed:
                // Item failed - likely stream URL issue, request refresh
                self.delegate?.healthMonitorNeedsStreamRefresh(self, for: trackId)

            case .stalled, .bufferTimeout:
                // Buffer issue - try seeking to current position to kick-start buffering
                let currentTime = self.player.currentTime()
                if currentTime.isValid && !currentTime.isIndefinite {
                    #if DEBUG
                    print("🏥 Seeking to current position to restart buffering")
                    #endif

                    await self.player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)

                    // Give it a moment, then check if we need stream refresh
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                    if self.player.timeControlStatus != .playing && self.isRecovering {
                        // Still not playing, might need stream refresh
                        self.delegate?.healthMonitorNeedsStreamRefresh(self, for: trackId)
                    }
                } else {
                    // Invalid time, request stream refresh
                    self.delegate?.healthMonitorNeedsStreamRefresh(self, for: trackId)
                }
            }
        }
    }

    deinit {
        // Inline cleanup since deinit is nonisolated
        stallDetectionTask?.cancel()
        bufferRecoveryTask?.cancel()
        itemStatusObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        bufferFullObservation?.invalidate()
        bufferKeepUpObservation?.invalidate()
        timeControlObservation?.invalidate()
        reasonForWaitingObservation?.invalidate()
    }
}
