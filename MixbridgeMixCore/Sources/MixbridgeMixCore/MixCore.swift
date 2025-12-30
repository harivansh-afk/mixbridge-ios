// MixCore.swift
// Pure Swift mix logic - no AVFoundation dependencies
// Unit-testable gain curves, scheduler, and state machine

import Foundation

// MARK: - Gain Curves (Equal-Power)

/// Equal-power crossfade gain calculations
/// Ensures constant perceived loudness during crossfade
public enum MixGain {
    /// Gain for outgoing (current) track: cos(p * pi/2)
    /// - Parameter progress: Crossfade progress in [0, 1]
    /// - Returns: Gain value in [0, 1]
    public static func currentGain(_ progress: Double) -> Double {
        let clamped = max(0, min(1, progress))
        return cos(clamped * .pi / 2)
    }

    /// Gain for incoming (next) track: sin(p * pi/2)
    /// - Parameter progress: Crossfade progress in [0, 1]
    /// - Returns: Gain value in [0, 1]
    public static func nextGain(_ progress: Double) -> Double {
        let clamped = max(0, min(1, progress))
        return sin(clamped * .pi / 2)
    }
}

// MARK: - Scheduler

/// Timing schedule for mix transitions
public struct MixSchedule: Equatable {
    /// Effective crossfade duration (clamped to max half of track duration)
    public let effectiveCrossfade: Double

    /// Time when crossfade should start
    public let fadeStartTime: Double

    /// Time when prewarm should start (load next track)
    public let prewarmStartTime: Double

    /// Track duration used for calculations
    public let duration: Double

    /// Whether crossfade is enabled (effectiveCrossfade > 0)
    public var isCrossfadeEnabled: Bool {
        effectiveCrossfade > 0
    }
}

/// Scheduler for computing mix timing boundaries
public enum MixScheduler {
    /// Compute schedule for a track
    /// - Parameters:
    ///   - duration: Track duration in seconds (must be > 0 and finite)
    ///   - crossfadeSeconds: Desired crossfade duration (clamped 0...12)
    ///   - prewarmSeconds: Prewarm lead time (clamped 0...60)
    /// - Returns: Computed schedule, or nil if duration is invalid
    public static func schedule(
        duration: Double,
        crossfadeSeconds: Double,
        prewarmSeconds: Double
    ) -> MixSchedule? {
        guard duration > 0 && duration.isFinite else { return nil }

        // Clamp inputs per spec
        let clampedCrossfade = max(0, min(12, crossfadeSeconds))
        let clampedPrewarm = max(0, min(60, prewarmSeconds))

        // Effective crossfade cannot exceed half of track duration
        let effectiveCrossfade = min(clampedCrossfade, floor(duration / 2))

        // Fade starts at duration - effectiveCrossfade
        let fadeStartTime = max(0, duration - effectiveCrossfade)

        // Prewarm starts at duration - max(prewarm, crossfade)
        let prewarmLeadTime = max(clampedPrewarm, effectiveCrossfade)
        let prewarmStartTime = max(0, duration - prewarmLeadTime)

        return MixSchedule(
            effectiveCrossfade: effectiveCrossfade,
            fadeStartTime: fadeStartTime,
            prewarmStartTime: prewarmStartTime,
            duration: duration
        )
    }

    /// Compute crossfade progress for current playback time
    /// - Parameters:
    ///   - currentTime: Current playback position
    ///   - schedule: Computed mix schedule
    /// - Returns: Progress in [0, 1], or nil if not in crossfade window
    public static func crossfadeProgress(
        currentTime: Double,
        schedule: MixSchedule
    ) -> Double? {
        guard schedule.isCrossfadeEnabled else { return nil }
        guard currentTime >= schedule.fadeStartTime else { return nil }

        let elapsed = currentTime - schedule.fadeStartTime
        let progress = elapsed / schedule.effectiveCrossfade
        return max(0, min(1, progress))
    }
}

// MARK: - State Machine

/// Mix playback states
public enum MixState: Equatable {
    case singlePlaying
    case prewarmingNext
    case crossfading
}

/// Reasons for aborting a mix transition
public enum MixAbortReason: String, Equatable {
    case noNext = "no_next"
    case disabled = "disabled"
    case zeroCrossfade = "zero_crossfade"
    case notReady = "not_ready"
    case streamRefreshFailed = "stream_refresh_failed"
    case queueChanged = "queue_changed"
    case seekCancelled = "seek_cancelled"
}

/// Input signals for the state machine
public enum MixInput: Equatable {
    case timeUpdate(currentTime: Double, schedule: MixSchedule)
    case nextTrackReady
    case nextTrackFailed(MixAbortReason)
    case fadeComplete
    case seekBefore(prewarmStartTime: Double)
    case queueChanged
    case disabled
}

/// Output events emitted by the state machine
public enum MixEvent: Equatable {
    case prewarmStart
    case prewarmReady
    case fadeStart
    case fadeComplete
    case fadeAbort(MixAbortReason)
}

/// Pure state machine for mix transitions
/// No side effects - returns new state and events
public struct MixStateMachine {
    public private(set) var state: MixState
    public private(set) var hasNextTrack: Bool
    public private(set) var isNextReady: Bool

    public init() {
        self.state = .singlePlaying
        self.hasNextTrack = false
        self.isNextReady = false
    }

    /// Process input and return (newState, events)
    public mutating func process(_ input: MixInput) -> [MixEvent] {
        var events: [MixEvent] = []

        switch (state, input) {

        // MARK: - SinglePlaying transitions

        case (.singlePlaying, .timeUpdate(let currentTime, let schedule)):
            // Check if we should start prewarming
            if hasNextTrack && schedule.isCrossfadeEnabled && currentTime >= schedule.prewarmStartTime {
                state = .prewarmingNext
                events.append(.prewarmStart)
            }

        case (.singlePlaying, .disabled), (.singlePlaying, .queueChanged):
            // No-op in single playing state
            break

        // MARK: - PrewarmingNext transitions

        case (.prewarmingNext, .nextTrackReady):
            isNextReady = true
            events.append(.prewarmReady)

        case (.prewarmingNext, .timeUpdate(let currentTime, let schedule)):
            // Check if we should start crossfading
            if isNextReady && currentTime >= schedule.fadeStartTime {
                state = .crossfading
                events.append(.fadeStart)
            }

        case (.prewarmingNext, .nextTrackFailed(let reason)):
            state = .singlePlaying
            isNextReady = false
            events.append(.fadeAbort(reason))

        case (.prewarmingNext, .seekBefore):
            state = .singlePlaying
            isNextReady = false
            events.append(.fadeAbort(.seekCancelled))

        case (.prewarmingNext, .queueChanged):
            state = .singlePlaying
            isNextReady = false
            events.append(.fadeAbort(.queueChanged))

        case (.prewarmingNext, .disabled):
            state = .singlePlaying
            isNextReady = false
            events.append(.fadeAbort(.disabled))

        // MARK: - Crossfading transitions

        case (.crossfading, .fadeComplete):
            state = .singlePlaying
            hasNextTrack = false
            isNextReady = false
            events.append(.fadeComplete)

        case (.crossfading, .nextTrackFailed(let reason)):
            state = .singlePlaying
            isNextReady = false
            events.append(.fadeAbort(reason))

        case (.crossfading, .seekBefore):
            state = .singlePlaying
            isNextReady = false
            events.append(.fadeAbort(.seekCancelled))

        case (.crossfading, .queueChanged):
            state = .singlePlaying
            isNextReady = false
            events.append(.fadeAbort(.queueChanged))

        case (.crossfading, .disabled):
            state = .singlePlaying
            isNextReady = false
            events.append(.fadeAbort(.disabled))

        case (.crossfading, .timeUpdate):
            // Time updates during crossfade are handled by the engine
            break

        default:
            break
        }

        return events
    }

    /// Set whether next track exists in queue
    public mutating func setHasNextTrack(_ hasNext: Bool) {
        hasNextTrack = hasNext
        if !hasNext {
            isNextReady = false
        }
    }

    /// Reset state machine to initial state
    public mutating func reset() {
        state = .singlePlaying
        hasNextTrack = false
        isNextReady = false
    }
}
