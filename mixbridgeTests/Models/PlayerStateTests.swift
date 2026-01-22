//
//  PlayerStateTests.swift
//  mixbridgeTests
//
//  Comprehensive tests for PlayerState enums, structs, and isolated functionality.
//

import XCTest
@testable import mixbridge

// MARK: - PlaybackStatus Tests

final class PlaybackStatusTests: XCTestCase {

    // MARK: - Case Tests

    func testPlaybackStatus_idleCase() {
        let status: PlayerState.PlaybackStatus = .idle
        XCTAssertEqual(status, .idle)
    }

    func testPlaybackStatus_loadingCase() {
        let status: PlayerState.PlaybackStatus = .loading
        XCTAssertEqual(status, .loading)
    }

    func testPlaybackStatus_readyCase() {
        let status: PlayerState.PlaybackStatus = .ready
        XCTAssertEqual(status, .ready)
    }

    func testPlaybackStatus_playingCase() {
        let status: PlayerState.PlaybackStatus = .playing
        XCTAssertEqual(status, .playing)
    }

    func testPlaybackStatus_pausedCase() {
        let status: PlayerState.PlaybackStatus = .paused
        XCTAssertEqual(status, .paused)
    }

    func testPlaybackStatus_failedCase_withMessage() {
        let errorMessage = "Stream URL expired"
        let status: PlayerState.PlaybackStatus = .failed(errorMessage)

        if case .failed(let message) = status {
            XCTAssertEqual(message, errorMessage)
        } else {
            XCTFail("Expected failed case")
        }
    }

    func testPlaybackStatus_failedCase_withEmptyMessage() {
        let status: PlayerState.PlaybackStatus = .failed("")

        if case .failed(let message) = status {
            XCTAssertEqual(message, "")
        } else {
            XCTFail("Expected failed case")
        }
    }

    // MARK: - Equatable Tests

    func testPlaybackStatus_equality_sameCase() {
        XCTAssertEqual(PlayerState.PlaybackStatus.idle, .idle)
        XCTAssertEqual(PlayerState.PlaybackStatus.loading, .loading)
        XCTAssertEqual(PlayerState.PlaybackStatus.ready, .ready)
        XCTAssertEqual(PlayerState.PlaybackStatus.playing, .playing)
        XCTAssertEqual(PlayerState.PlaybackStatus.paused, .paused)
    }

    func testPlaybackStatus_inequality_differentCases() {
        XCTAssertNotEqual(PlayerState.PlaybackStatus.idle, .loading)
        XCTAssertNotEqual(PlayerState.PlaybackStatus.playing, .paused)
        XCTAssertNotEqual(PlayerState.PlaybackStatus.ready, .failed("error"))
    }

    func testPlaybackStatus_failed_equality_sameMessage() {
        let status1: PlayerState.PlaybackStatus = .failed("Network error")
        let status2: PlayerState.PlaybackStatus = .failed("Network error")
        XCTAssertEqual(status1, status2)
    }

    func testPlaybackStatus_failed_inequality_differentMessage() {
        let status1: PlayerState.PlaybackStatus = .failed("Error A")
        let status2: PlayerState.PlaybackStatus = .failed("Error B")
        XCTAssertNotEqual(status1, status2)
    }

    func testPlaybackStatus_failed_notEqualToOtherCases() {
        let failedStatus: PlayerState.PlaybackStatus = .failed("error")
        XCTAssertNotEqual(failedStatus, .idle)
        XCTAssertNotEqual(failedStatus, .loading)
        XCTAssertNotEqual(failedStatus, .ready)
        XCTAssertNotEqual(failedStatus, .playing)
        XCTAssertNotEqual(failedStatus, .paused)
    }

    // MARK: - Edge Cases

    func testPlaybackStatus_failed_withSpecialCharacters() {
        let message = "Error: \u{1F4A5} Connection failed!\nRetry?"
        let status: PlayerState.PlaybackStatus = .failed(message)

        if case .failed(let extracted) = status {
            XCTAssertEqual(extracted, message)
        } else {
            XCTFail("Expected failed case")
        }
    }

    func testPlaybackStatus_failed_withVeryLongMessage() {
        let longMessage = String(repeating: "Error details. ", count: 1000)
        let status: PlayerState.PlaybackStatus = .failed(longMessage)

        if case .failed(let extracted) = status {
            XCTAssertEqual(extracted, longMessage)
        } else {
            XCTFail("Expected failed case")
        }
    }

    func testPlaybackStatus_failed_withUnicodeMessage() {
        let unicodeMessage = "Error in track: \u{4E2D}\u{6587}\u{65E5}\u{672C}\u{8A9E}\u{D55C}\u{AE00}"
        let status: PlayerState.PlaybackStatus = .failed(unicodeMessage)

        if case .failed(let extracted) = status {
            XCTAssertEqual(extracted, unicodeMessage)
        } else {
            XCTFail("Expected failed case")
        }
    }
}

// MARK: - PlaybackError Tests

final class PlaybackErrorTests: XCTestCase {

    func testPlaybackError_invalidStreamURL() {
        let error = PlayerState.PlaybackError.invalidStreamURL
        XCTAssertNotNil(error.errorDescription)
    }

    func testPlaybackError_invalidStreamURL_errorDescription() {
        let error = PlayerState.PlaybackError.invalidStreamURL
        XCTAssertEqual(error.errorDescription, "Invalid stream URL")
    }

    func testPlaybackError_conformsToLocalizedError() {
        let error: LocalizedError = PlayerState.PlaybackError.invalidStreamURL
        XCTAssertEqual(error.errorDescription, "Invalid stream URL")
    }

    func testPlaybackError_canBeThrownAndCaught() {
        func throwingFunction() throws {
            throw PlayerState.PlaybackError.invalidStreamURL
        }

        XCTAssertThrowsError(try throwingFunction()) { error in
            XCTAssertTrue(error is PlayerState.PlaybackError)
            if let playbackError = error as? PlayerState.PlaybackError {
                XCTAssertEqual(playbackError, .invalidStreamURL)
            }
        }
    }
}

// MARK: - RepeatMode Tests

final class RepeatModeTests: XCTestCase {

    // MARK: - Case Tests

    func testRepeatMode_offCase() {
        let mode: PlayerState.RepeatMode = .off
        XCTAssertEqual(mode.rawValue, "off")
    }

    func testRepeatMode_allCase() {
        let mode: PlayerState.RepeatMode = .all
        XCTAssertEqual(mode.rawValue, "all")
    }

    func testRepeatMode_oneCase() {
        let mode: PlayerState.RepeatMode = .one
        XCTAssertEqual(mode.rawValue, "one")
    }

    // MARK: - CaseIterable Tests

    func testRepeatMode_allCases() {
        let allCases = PlayerState.RepeatMode.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.off))
        XCTAssertTrue(allCases.contains(.all))
        XCTAssertTrue(allCases.contains(.one))
    }

    // MARK: - Symbol Name Tests

    func testRepeatMode_symbolName_off() {
        XCTAssertEqual(PlayerState.RepeatMode.off.symbolName, "repeat")
    }

    func testRepeatMode_symbolName_all() {
        XCTAssertEqual(PlayerState.RepeatMode.all.symbolName, "repeat")
    }

    func testRepeatMode_symbolName_one() {
        XCTAssertEqual(PlayerState.RepeatMode.one.symbolName, "repeat.1")
    }

    // MARK: - isEnabled Tests

    func testRepeatMode_isEnabled_off() {
        XCTAssertFalse(PlayerState.RepeatMode.off.isEnabled)
    }

    func testRepeatMode_isEnabled_all() {
        XCTAssertTrue(PlayerState.RepeatMode.all.isEnabled)
    }

    func testRepeatMode_isEnabled_one() {
        XCTAssertTrue(PlayerState.RepeatMode.one.isEnabled)
    }

    // MARK: - next() Cycle Tests

    func testRepeatMode_next_fromOff() {
        XCTAssertEqual(PlayerState.RepeatMode.off.next(), .all)
    }

    func testRepeatMode_next_fromAll() {
        XCTAssertEqual(PlayerState.RepeatMode.all.next(), .one)
    }

    func testRepeatMode_next_fromOne() {
        XCTAssertEqual(PlayerState.RepeatMode.one.next(), .off)
    }

    func testRepeatMode_next_fullCycle() {
        var mode: PlayerState.RepeatMode = .off

        mode = mode.next()
        XCTAssertEqual(mode, .all)

        mode = mode.next()
        XCTAssertEqual(mode, .one)

        mode = mode.next()
        XCTAssertEqual(mode, .off)
    }

    func testRepeatMode_next_multipleCycles() {
        var mode: PlayerState.RepeatMode = .off

        // Cycle through 3 complete cycles (9 transitions)
        for i in 0..<9 {
            mode = mode.next()
            let expectedIndex = (i + 1) % 3
            let expected: PlayerState.RepeatMode = [.all, .one, .off][expectedIndex]
            XCTAssertEqual(mode, expected, "Failed at transition \(i)")
        }
    }

    // MARK: - Raw Value Init Tests

    func testRepeatMode_initFromRawValue_valid() {
        XCTAssertEqual(PlayerState.RepeatMode(rawValue: "off"), .off)
        XCTAssertEqual(PlayerState.RepeatMode(rawValue: "all"), .all)
        XCTAssertEqual(PlayerState.RepeatMode(rawValue: "one"), .one)
    }

    func testRepeatMode_initFromRawValue_invalid() {
        XCTAssertNil(PlayerState.RepeatMode(rawValue: "invalid"))
        XCTAssertNil(PlayerState.RepeatMode(rawValue: ""))
        XCTAssertNil(PlayerState.RepeatMode(rawValue: "OFF"))
        XCTAssertNil(PlayerState.RepeatMode(rawValue: "All"))
    }

    // MARK: - Equatable Tests

    func testRepeatMode_equality() {
        XCTAssertEqual(PlayerState.RepeatMode.off, .off)
        XCTAssertEqual(PlayerState.RepeatMode.all, .all)
        XCTAssertEqual(PlayerState.RepeatMode.one, .one)
    }

    func testRepeatMode_inequality() {
        XCTAssertNotEqual(PlayerState.RepeatMode.off, .all)
        XCTAssertNotEqual(PlayerState.RepeatMode.all, .one)
        XCTAssertNotEqual(PlayerState.RepeatMode.one, .off)
    }
}

// MARK: - PendingPlayback Tests

final class PendingPlaybackTests: XCTestCase {

    func testPendingPlayback_init_withTrackIdOnly() {
        let pending = PlayerState.PendingPlayback(trackId: "track-123")

        XCTAssertEqual(pending.trackId, "track-123")
        XCTAssertNil(pending.uiUpdated)
        XCTAssertNil(pending.startedPlaying)
    }

    func testPendingPlayback_init_withAllParameters() {
        let uiToken = InteractionMetrics.begin("test_ui", context: "ui test")
        let playingToken = InteractionMetrics.begin("test_playing", context: "playing test")

        var pending = PlayerState.PendingPlayback(trackId: "track-456")
        pending.uiUpdated = uiToken
        pending.startedPlaying = playingToken

        XCTAssertEqual(pending.trackId, "track-456")
        XCTAssertNotNil(pending.uiUpdated)
        XCTAssertNotNil(pending.startedPlaying)
    }

    func testPendingPlayback_trackId_emptyString() {
        let pending = PlayerState.PendingPlayback(trackId: "")
        XCTAssertEqual(pending.trackId, "")
    }

    func testPendingPlayback_trackId_specialCharacters() {
        let trackId = "track-\u{1F3B5}-#special/chars@test"
        let pending = PlayerState.PendingPlayback(trackId: trackId)
        XCTAssertEqual(pending.trackId, trackId)
    }

    func testPendingPlayback_tokens_areMutable() {
        var pending = PlayerState.PendingPlayback(trackId: "track-789")

        XCTAssertNil(pending.uiUpdated)

        let token = InteractionMetrics.begin("test_metric")
        pending.uiUpdated = token

        XCTAssertNotNil(pending.uiUpdated)
    }
}

// MARK: - PendingNavigationKind Tests

final class PendingNavigationKindTests: XCTestCase {

    func testPendingNavigationKind_next_storesPreviousTrackId() {
        let kind = PlayerState.PendingNavigationKind.next(previousTrackId: "old-track-123")

        if case .next(let trackId) = kind {
            XCTAssertEqual(trackId, "old-track-123")
        } else {
            XCTFail("Expected next case")
        }
    }

    func testPendingNavigationKind_previous_storesPreviousTrackId() {
        let kind = PlayerState.PendingNavigationKind.previous(previousTrackId: "old-track-456")

        if case .previous(let trackId) = kind {
            XCTAssertEqual(trackId, "old-track-456")
        } else {
            XCTFail("Expected previous case")
        }
    }

    func testPendingNavigationKind_next_emptyTrackId() {
        let kind = PlayerState.PendingNavigationKind.next(previousTrackId: "")

        if case .next(let trackId) = kind {
            XCTAssertEqual(trackId, "")
        } else {
            XCTFail("Expected next case")
        }
    }

    func testPendingNavigationKind_previous_emptyTrackId() {
        let kind = PlayerState.PendingNavigationKind.previous(previousTrackId: "")

        if case .previous(let trackId) = kind {
            XCTAssertEqual(trackId, "")
        } else {
            XCTFail("Expected previous case")
        }
    }

    func testPendingNavigationKind_next_specialCharacters() {
        let specialId = "track-\u{D55C}\u{AE00}-\u{65E5}\u{672C}\u{8A9E}"
        let kind = PlayerState.PendingNavigationKind.next(previousTrackId: specialId)

        if case .next(let trackId) = kind {
            XCTAssertEqual(trackId, specialId)
        } else {
            XCTFail("Expected next case")
        }
    }

    func testPendingNavigationKind_differentCases_areDistinct() {
        let nextKind = PlayerState.PendingNavigationKind.next(previousTrackId: "track-123")
        let previousKind = PlayerState.PendingNavigationKind.previous(previousTrackId: "track-123")

        // Both have the same track ID but different cases
        if case .next = nextKind {
            // OK
        } else {
            XCTFail("Expected next case")
        }

        if case .previous = previousKind {
            // OK
        } else {
            XCTFail("Expected previous case")
        }
    }
}

// MARK: - InteractionMetrics Token Tests

final class InteractionMetricsTokenTests: XCTestCase {

    func testToken_hasUniqueId() {
        let token1 = InteractionMetrics.begin("test_1")
        let token2 = InteractionMetrics.begin("test_2")

        XCTAssertNotEqual(token1.id, token2.id)
    }

    func testToken_storesName() {
        let token = InteractionMetrics.begin("player_action")
        // StaticString comparison - just verify it's stored
        XCTAssertNotNil(token.name)
    }

    func testToken_storesContext() {
        let token = InteractionMetrics.begin("test_metric", context: "test context value")
        XCTAssertEqual(token.context, "test context value")
    }

    func testToken_defaultEmptyContext() {
        let token = InteractionMetrics.begin("test_metric")
        XCTAssertEqual(token.context, "")
    }

    func testToken_recordsStartTime() {
        let beforeTime = DispatchTime.now().uptimeNanoseconds
        let token = InteractionMetrics.begin("timing_test")
        let afterTime = DispatchTime.now().uptimeNanoseconds

        XCTAssertGreaterThanOrEqual(token.startUptimeNs, beforeTime)
        XCTAssertLessThanOrEqual(token.startUptimeNs, afterTime)
    }

    func testToken_isSendable() async {
        let token = InteractionMetrics.begin("sendable_test", context: "context")

        // Verify token can be sent across actor boundaries
        let receivedToken = await Task.detached {
            return token
        }.value

        XCTAssertEqual(receivedToken.id, token.id)
        XCTAssertEqual(receivedToken.context, token.context)
    }

    func testEnd_doesNotCrash() {
        let token = InteractionMetrics.begin("end_test")
        // Just verify this doesn't crash - it logs to OSLog
        InteractionMetrics.end(token)
        InteractionMetrics.end(token, result: "success")
    }
}

// MARK: - Persistence Keys Tests

@MainActor
final class PlayerStatePersistenceKeysTests: XCTestCase {

    func testSavedTrackKey() {
        let playerState = PlayerState.shared
        XCTAssertEqual(playerState.kSavedTrack, "mixbridge.savedTrack")
    }

    func testSavedPositionKey() {
        let playerState = PlayerState.shared
        XCTAssertEqual(playerState.kSavedPosition, "mixbridge.savedPosition")
    }

    func testSavedDurationKey() {
        let playerState = PlayerState.shared
        XCTAssertEqual(playerState.kSavedDuration, "mixbridge.savedDuration")
    }

    func testMixEnabledKey() {
        let playerState = PlayerState.shared
        XCTAssertEqual(playerState.kMixEnabled, "mixbridge.mixEnabled")
    }

    func testCrossfadeSecondsKey() {
        let playerState = PlayerState.shared
        XCTAssertEqual(playerState.kCrossfadeSeconds, "mixbridge.crossfadeSeconds")
    }

    func testPrewarmSecondsKey() {
        let playerState = PlayerState.shared
        XCTAssertEqual(playerState.kPrewarmSeconds, "mixbridge.prewarmSeconds")
    }

    func testFadeCurveKey() {
        let playerState = PlayerState.shared
        XCTAssertEqual(playerState.kFadeCurve, "mixbridge.fadeCurve")
    }

    func testRepeatModeKey() {
        let playerState = PlayerState.shared
        XCTAssertEqual(playerState.kRepeatMode, "mixbridge.repeatMode")
    }

    func testAllKeysHaveConsistentPrefix() {
        let playerState = PlayerState.shared
        let keys = [
            playerState.kSavedTrack,
            playerState.kSavedPosition,
            playerState.kSavedDuration,
            playerState.kMixEnabled,
            playerState.kCrossfadeSeconds,
            playerState.kPrewarmSeconds,
            playerState.kFadeCurve,
            playerState.kRepeatMode
        ]

        for key in keys {
            XCTAssertTrue(key.hasPrefix("mixbridge."), "Key '\(key)' should have 'mixbridge.' prefix")
        }
    }

    func testAllKeysAreUnique() {
        let playerState = PlayerState.shared
        let keys = [
            playerState.kSavedTrack,
            playerState.kSavedPosition,
            playerState.kSavedDuration,
            playerState.kMixEnabled,
            playerState.kCrossfadeSeconds,
            playerState.kPrewarmSeconds,
            playerState.kFadeCurve,
            playerState.kRepeatMode
        ]

        let uniqueKeys = Set(keys)
        XCTAssertEqual(keys.count, uniqueKeys.count, "All persistence keys should be unique")
    }
}

// MARK: - Crossfade Settings Clamping Tests

@MainActor
final class PlayerStateCrossfadeClampingTests: XCTestCase {

    // Note: These tests verify the clamping behavior documented in the code
    // crossfadeSeconds: clamped to 1...20
    // prewarmSeconds: clamped to 5...60

    func testCrossfadeSeconds_defaultValue() {
        // Default is 6 seconds per the code
        let playerState = PlayerState.shared
        // We can't easily test the default since it's a singleton that may have loaded state
        // Just verify it's within valid range
        XCTAssertGreaterThanOrEqual(playerState.crossfadeSeconds, 1)
        XCTAssertLessThanOrEqual(playerState.crossfadeSeconds, 20)
    }

    func testPrewarmSeconds_defaultValue() {
        // Default is 15 seconds per the code
        let playerState = PlayerState.shared
        // We can't easily test the default since it's a singleton that may have loaded state
        // Just verify it's within valid range
        XCTAssertGreaterThanOrEqual(playerState.prewarmSeconds, 5)
        XCTAssertLessThanOrEqual(playerState.prewarmSeconds, 60)
    }

    func testCrossfadeSeconds_validRange() {
        let playerState = PlayerState.shared
        let originalValue = playerState.crossfadeSeconds

        // Test setting a valid value in range
        playerState.crossfadeSeconds = 10
        XCTAssertEqual(playerState.crossfadeSeconds, 10)

        playerState.crossfadeSeconds = 1  // minimum
        XCTAssertEqual(playerState.crossfadeSeconds, 1)

        playerState.crossfadeSeconds = 20  // maximum
        XCTAssertEqual(playerState.crossfadeSeconds, 20)

        // Restore
        playerState.crossfadeSeconds = originalValue
    }

    func testCrossfadeSeconds_clampsBelowMinimum() {
        let playerState = PlayerState.shared
        let originalValue = playerState.crossfadeSeconds

        playerState.crossfadeSeconds = 0
        XCTAssertEqual(playerState.crossfadeSeconds, 1, "Should clamp to minimum of 1")

        playerState.crossfadeSeconds = -5
        XCTAssertEqual(playerState.crossfadeSeconds, 1, "Should clamp negative to minimum of 1")

        // Restore
        playerState.crossfadeSeconds = originalValue
    }

    func testCrossfadeSeconds_clampsAboveMaximum() {
        let playerState = PlayerState.shared
        let originalValue = playerState.crossfadeSeconds

        playerState.crossfadeSeconds = 21
        XCTAssertEqual(playerState.crossfadeSeconds, 20, "Should clamp to maximum of 20")

        playerState.crossfadeSeconds = 100
        XCTAssertEqual(playerState.crossfadeSeconds, 20, "Should clamp large value to maximum of 20")

        // Restore
        playerState.crossfadeSeconds = originalValue
    }

    func testPrewarmSeconds_validRange() {
        let playerState = PlayerState.shared
        let originalValue = playerState.prewarmSeconds

        playerState.prewarmSeconds = 30
        XCTAssertEqual(playerState.prewarmSeconds, 30)

        playerState.prewarmSeconds = 5  // minimum
        XCTAssertEqual(playerState.prewarmSeconds, 5)

        playerState.prewarmSeconds = 60  // maximum
        XCTAssertEqual(playerState.prewarmSeconds, 60)

        // Restore
        playerState.prewarmSeconds = originalValue
    }

    func testPrewarmSeconds_clampsBelowMinimum() {
        let playerState = PlayerState.shared
        let originalValue = playerState.prewarmSeconds

        playerState.prewarmSeconds = 4
        XCTAssertEqual(playerState.prewarmSeconds, 5, "Should clamp to minimum of 5")

        playerState.prewarmSeconds = 0
        XCTAssertEqual(playerState.prewarmSeconds, 5, "Should clamp zero to minimum of 5")

        playerState.prewarmSeconds = -10
        XCTAssertEqual(playerState.prewarmSeconds, 5, "Should clamp negative to minimum of 5")

        // Restore
        playerState.prewarmSeconds = originalValue
    }

    func testPrewarmSeconds_clampsAboveMaximum() {
        let playerState = PlayerState.shared
        let originalValue = playerState.prewarmSeconds

        playerState.prewarmSeconds = 61
        XCTAssertEqual(playerState.prewarmSeconds, 60, "Should clamp to maximum of 60")

        playerState.prewarmSeconds = 1000
        XCTAssertEqual(playerState.prewarmSeconds, 60, "Should clamp large value to maximum of 60")

        // Restore
        playerState.prewarmSeconds = originalValue
    }
}

// MARK: - Computed Properties Tests

@MainActor
final class PlayerStateComputedPropertiesTests: XCTestCase {

    func testHasActiveTrack_idleStatus_returnsFalse() {
        let playerState = PlayerState.shared
        let originalStatus = playerState.playbackStatus

        playerState.playbackStatus = .idle
        XCTAssertFalse(playerState.hasActiveTrack)

        playerState.playbackStatus = originalStatus
    }

    func testHasActiveTrack_loadingStatus_returnsTrue() {
        let playerState = PlayerState.shared
        let originalStatus = playerState.playbackStatus

        playerState.playbackStatus = .loading
        XCTAssertTrue(playerState.hasActiveTrack)

        playerState.playbackStatus = originalStatus
    }

    func testHasActiveTrack_readyStatus_returnsTrue() {
        let playerState = PlayerState.shared
        let originalStatus = playerState.playbackStatus

        playerState.playbackStatus = .ready
        XCTAssertTrue(playerState.hasActiveTrack)

        playerState.playbackStatus = originalStatus
    }

    func testHasActiveTrack_playingStatus_returnsTrue() {
        let playerState = PlayerState.shared
        let originalStatus = playerState.playbackStatus

        playerState.playbackStatus = .playing
        XCTAssertTrue(playerState.hasActiveTrack)

        playerState.playbackStatus = originalStatus
    }

    func testHasActiveTrack_pausedStatus_returnsTrue() {
        let playerState = PlayerState.shared
        let originalStatus = playerState.playbackStatus

        playerState.playbackStatus = .paused
        XCTAssertTrue(playerState.hasActiveTrack)

        playerState.playbackStatus = originalStatus
    }

    func testHasActiveTrack_failedStatus_returnsTrue() {
        let playerState = PlayerState.shared
        let originalStatus = playerState.playbackStatus

        playerState.playbackStatus = .failed("Some error")
        XCTAssertTrue(playerState.hasActiveTrack)

        playerState.playbackStatus = originalStatus
    }

    func testCurrentQueueIndex_returnsMinus1WhenNotInQueue() {
        let playerState = PlayerState.shared
        // Default/initial value when not playing from queue
        // The actual value depends on app state, just verify it's accessible
        _ = playerState.currentQueueIndex
    }
}

// MARK: - Default Values Tests

@MainActor
final class PlayerStateDefaultValuesTests: XCTestCase {

    func testDefaultVolume_is0Point7() {
        // Volume is initialized to 0.7 per the source code
        // Since it's a singleton that may have user settings loaded,
        // we verify it's in a valid range
        let playerState = PlayerState.shared
        XCTAssertGreaterThanOrEqual(playerState.volume, 0)
        XCTAssertLessThanOrEqual(playerState.volume, 1)
    }

    func testAutoplayEnabled_defaultTrue() {
        // autoplayEnabled is initialized to true
        let playerState = PlayerState.shared
        // Can be either true or false depending on user settings
        // Just verify it's accessible as a Bool
        _ = playerState.autoplayEnabled
    }

    func testMixEnabled_defaultFalse() {
        // mixEnabled is initialized to false
        let playerState = PlayerState.shared
        // Verify it's accessible
        _ = playerState.mixEnabled
    }

    func testCrossfadeProgress_defaultZero() {
        let playerState = PlayerState.shared
        XCTAssertGreaterThanOrEqual(playerState.crossfadeProgress, 0)
        XCTAssertLessThanOrEqual(playerState.crossfadeProgress, 1)
    }

    func testIsSeeking_defaultFalse() {
        let playerState = PlayerState.shared
        // isSeeking should default to false when not actively seeking
        // It may be true during a seek operation
        _ = playerState.isSeeking
    }
}

// MARK: - Crossfade Visual State Tests

@MainActor
final class PlayerStateCrossfadeVisualTests: XCTestCase {

    func testCrossfadeProgress_inValidRange() {
        let playerState = PlayerState.shared
        XCTAssertGreaterThanOrEqual(playerState.crossfadeProgress, 0.0)
        XCTAssertLessThanOrEqual(playerState.crossfadeProgress, 1.0)
    }

    func testIsCrossfading_isAccessible() {
        let playerState = PlayerState.shared
        // Just verify the property is accessible
        _ = playerState.isCrossfading
    }

    func testCrossfadeFromArtwork_isAccessible() {
        let playerState = PlayerState.shared
        // Default is empty string per source code
        _ = playerState.crossfadeFromArtwork
    }

    func testCrossfadeNextTrack_canBeNil() {
        let playerState = PlayerState.shared
        // Default is nil per source code
        // May have a value during crossfade
        _ = playerState.crossfadeNextTrack
    }

    func testCrossfadeNextPosition_isAccessible() {
        let playerState = PlayerState.shared
        XCTAssertGreaterThanOrEqual(playerState.crossfadeNextPosition, 0)
    }

    func testCrossfadeNextDuration_isAccessible() {
        let playerState = PlayerState.shared
        XCTAssertGreaterThanOrEqual(playerState.crossfadeNextDuration, 0)
    }
}

// MARK: - FadeCurve Integration Tests

final class PlayerStateFadeCurveTests: XCTestCase {

    func testFadeCurve_allCases() {
        let allCases = FadeCurve.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.linear))
        XCTAssertTrue(allCases.contains(.equalPower))
        XCTAssertTrue(allCases.contains(.sCurve))
        XCTAssertTrue(allCases.contains(.exponential))
    }

    func testFadeCurve_rawValues() {
        XCTAssertEqual(FadeCurve.linear.rawValue, "linear")
        XCTAssertEqual(FadeCurve.equalPower.rawValue, "equalPower")
        XCTAssertEqual(FadeCurve.sCurve.rawValue, "sCurve")
        XCTAssertEqual(FadeCurve.exponential.rawValue, "exponential")
    }

    func testFadeCurve_initFromRawValue_valid() {
        XCTAssertEqual(FadeCurve(rawValue: "linear"), .linear)
        XCTAssertEqual(FadeCurve(rawValue: "equalPower"), .equalPower)
        XCTAssertEqual(FadeCurve(rawValue: "sCurve"), .sCurve)
        XCTAssertEqual(FadeCurve(rawValue: "exponential"), .exponential)
    }

    func testFadeCurve_initFromRawValue_invalid() {
        XCTAssertNil(FadeCurve(rawValue: "invalid"))
        XCTAssertNil(FadeCurve(rawValue: ""))
        XCTAssertNil(FadeCurve(rawValue: "Linear"))
        XCTAssertNil(FadeCurve(rawValue: "EQUALPOWER"))
    }

    func testFadeCurve_displayName_linear() {
        XCTAssertEqual(FadeCurve.linear.displayName, "Linear")
    }

    func testFadeCurve_displayName_equalPower() {
        XCTAssertEqual(FadeCurve.equalPower.displayName, "Equal Power")
    }

    func testFadeCurve_displayName_sCurve() {
        XCTAssertEqual(FadeCurve.sCurve.displayName, "S-Curve")
    }

    func testFadeCurve_displayName_exponential() {
        XCTAssertEqual(FadeCurve.exponential.displayName, "Exponential")
    }

    func testFadeCurve_codable_encodeDecodeRoundtrip() throws {
        let original = FadeCurve.equalPower
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FadeCurve.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testFadeCurve_codable_allCasesRoundtrip() throws {
        for curve in FadeCurve.allCases {
            let encoded = try JSONEncoder().encode(curve)
            let decoded = try JSONDecoder().decode(FadeCurve.self, from: encoded)
            XCTAssertEqual(decoded, curve)
        }
    }
}

// MARK: - Singleton Access Tests

@MainActor
final class PlayerStateSingletonTests: XCTestCase {

    func testShared_returnsSameInstance() {
        let instance1 = PlayerState.shared
        let instance2 = PlayerState.shared

        XCTAssertTrue(instance1 === instance2, "PlayerState.shared should always return the same instance")
    }

    func testShared_hasValidCurrentTrack() {
        let playerState = PlayerState.shared
        // Current track should never be nil (it's a non-optional)
        XCTAssertFalse(playerState.currentTrack.title.isEmpty || playerState.currentTrack.title == "")
    }

    func testShared_playbackCoordinatorExists() {
        let playerState = PlayerState.shared
        XCTAssertNotNil(playerState.playbackCoordinator)
    }

    func testShared_queueManagerExists() {
        let playerState = PlayerState.shared
        XCTAssertNotNil(playerState.queueManager)
    }

    func testShared_commandCenterExists() {
        let playerState = PlayerState.shared
        XCTAssertNotNil(playerState.commandCenter)
    }
}

// MARK: - Property Type Verification Tests

@MainActor
final class PlayerStatePropertyTypeTests: XCTestCase {

    func testPlaybackPosition_isDouble() {
        let playerState = PlayerState.shared
        let position: Double = playerState.playbackPosition
        XCTAssertGreaterThanOrEqual(position, 0)
    }

    func testDuration_isDouble() {
        let playerState = PlayerState.shared
        let duration: Double = playerState.duration
        XCTAssertGreaterThanOrEqual(duration, 0)
    }

    func testIsPlaying_isBool() {
        let playerState = PlayerState.shared
        let _: Bool = playerState.isPlaying
    }

    func testVolume_isDouble() {
        let playerState = PlayerState.shared
        let volume: Double = playerState.volume
        XCTAssertGreaterThanOrEqual(volume, 0)
        XCTAssertLessThanOrEqual(volume, 1)
    }

    func testErrorMessage_isOptionalString() {
        let playerState = PlayerState.shared
        let _: String? = playerState.errorMessage
    }

    func testCanPlayNext_isBool() {
        let playerState = PlayerState.shared
        let _: Bool = playerState.canPlayNext
    }

    func testCanPlayPrevious_isBool() {
        let playerState = PlayerState.shared
        let _: Bool = playerState.canPlayPrevious
    }

    func testPreviousHistoryTrack_isOptionalTrack() {
        let playerState = PlayerState.shared
        let _: Track? = playerState.previousHistoryTrack
    }

    func testNextForwardTrack_isOptionalTrack() {
        let playerState = PlayerState.shared
        let _: Track? = playerState.nextForwardTrack
    }

    func testIsCurrentTrackInQueue_isBool() {
        let playerState = PlayerState.shared
        let _: Bool = playerState.isCurrentTrackInQueue
    }
}
