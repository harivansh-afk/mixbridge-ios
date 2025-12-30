import XCTest
@testable import MixbridgeMixCore

final class MixGainTests: XCTestCase {

    // MARK: - Gain Curve Boundary Tests

    func testCurrentGainAtZero() {
        XCTAssertEqual(MixGain.currentGain(0), 1.0, accuracy: 0.0001)
    }

    func testCurrentGainAtOne() {
        XCTAssertEqual(MixGain.currentGain(1), 0.0, accuracy: 0.0001)
    }

    func testNextGainAtZero() {
        XCTAssertEqual(MixGain.nextGain(0), 0.0, accuracy: 0.0001)
    }

    func testNextGainAtOne() {
        XCTAssertEqual(MixGain.nextGain(1), 1.0, accuracy: 0.0001)
    }

    // MARK: - Equal-Power Invariant

    func testEqualPowerInvariant() {
        // Test at multiple points: sum of squares should equal 1
        let testPoints: [Double] = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]

        for p in testPoints {
            let current = MixGain.currentGain(p)
            let next = MixGain.nextGain(p)
            let sumOfSquares = current * current + next * next

            XCTAssertEqual(sumOfSquares, 1.0, accuracy: 0.01,
                "Equal-power invariant failed at p=\(p): \(sumOfSquares)")
        }
    }

    // MARK: - Clamping Tests

    func testCurrentGainClampsBelowZero() {
        XCTAssertEqual(MixGain.currentGain(-0.5), 1.0, accuracy: 0.0001)
    }

    func testCurrentGainClampsAboveOne() {
        XCTAssertEqual(MixGain.currentGain(1.5), 0.0, accuracy: 0.0001)
    }

    func testNextGainClampsBelowZero() {
        XCTAssertEqual(MixGain.nextGain(-0.5), 0.0, accuracy: 0.0001)
    }

    func testNextGainClampsAboveOne() {
        XCTAssertEqual(MixGain.nextGain(1.5), 1.0, accuracy: 0.0001)
    }
}

final class MixSchedulerTests: XCTestCase {

    // MARK: - Basic Schedule Computation

    func testScheduleWithNormalDuration() {
        let schedule = MixScheduler.schedule(
            duration: 180, // 3 minutes
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )

        XCTAssertNotNil(schedule)
        XCTAssertEqual(schedule!.effectiveCrossfade, 6)
        XCTAssertEqual(schedule!.fadeStartTime, 174) // 180 - 6
        XCTAssertEqual(schedule!.prewarmStartTime, 165) // 180 - 15
        XCTAssertTrue(schedule!.isCrossfadeEnabled)
    }

    func testScheduleClampsCrossfadeToHalfDuration() {
        // 10 second track, 6 second crossfade requested
        // effectiveCrossfade should be floor(10/2) = 5
        let schedule = MixScheduler.schedule(
            duration: 10,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )

        XCTAssertNotNil(schedule)
        XCTAssertEqual(schedule!.effectiveCrossfade, 5)
        XCTAssertEqual(schedule!.fadeStartTime, 5) // 10 - 5
    }

    func testScheduleWithZeroCrossfade() {
        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 0,
            prewarmSeconds: 15
        )

        XCTAssertNotNil(schedule)
        XCTAssertEqual(schedule!.effectiveCrossfade, 0)
        XCTAssertFalse(schedule!.isCrossfadeEnabled)
    }

    func testScheduleWithInvalidDuration() {
        XCTAssertNil(MixScheduler.schedule(duration: 0, crossfadeSeconds: 6, prewarmSeconds: 15))
        XCTAssertNil(MixScheduler.schedule(duration: -10, crossfadeSeconds: 6, prewarmSeconds: 15))
        XCTAssertNil(MixScheduler.schedule(duration: .infinity, crossfadeSeconds: 6, prewarmSeconds: 15))
        XCTAssertNil(MixScheduler.schedule(duration: .nan, crossfadeSeconds: 6, prewarmSeconds: 15))
    }

    func testSchedulePrewarmStartsBeforeFade() {
        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        XCTAssertLessThan(schedule.prewarmStartTime, schedule.fadeStartTime)
    }

    func testSchedulePrewarmClampsToMax() {
        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 100 // Exceeds max of 60
        )!

        // prewarmStartTime = 180 - max(60, 6) = 120
        XCTAssertEqual(schedule.prewarmStartTime, 120)
    }

    func testSchedulePrewarmUsesLargerOfPrewarmOrCrossfade() {
        // If crossfade > prewarm, prewarm should use crossfade value
        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 12,
            prewarmSeconds: 5
        )!

        // prewarmStartTime = 180 - max(5, 12) = 168
        XCTAssertEqual(schedule.prewarmStartTime, 168)
    }

    // MARK: - Crossfade Progress

    func testCrossfadeProgressBeforeFadeStart() {
        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        let progress = MixScheduler.crossfadeProgress(currentTime: 170, schedule: schedule)
        XCTAssertNil(progress)
    }

    func testCrossfadeProgressAtFadeStart() {
        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        let progress = MixScheduler.crossfadeProgress(currentTime: 174, schedule: schedule)
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress!, 0.0, accuracy: 0.0001)
    }

    func testCrossfadeProgressAtMidpoint() {
        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        // Midpoint: fadeStart + 3 = 177
        let progress = MixScheduler.crossfadeProgress(currentTime: 177, schedule: schedule)
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress!, 0.5, accuracy: 0.0001)
    }

    func testCrossfadeProgressAtEnd() {
        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        let progress = MixScheduler.crossfadeProgress(currentTime: 180, schedule: schedule)
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress!, 1.0, accuracy: 0.0001)
    }

    func testCrossfadeProgressWhenDisabled() {
        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 0,
            prewarmSeconds: 15
        )!

        let progress = MixScheduler.crossfadeProgress(currentTime: 180, schedule: schedule)
        XCTAssertNil(progress)
    }
}

final class MixStateMachineTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let machine = MixStateMachine()
        XCTAssertEqual(machine.state, .singlePlaying)
        XCTAssertFalse(machine.hasNextTrack)
        XCTAssertFalse(machine.isNextReady)
    }

    // MARK: - SinglePlaying -> PrewarmingNext

    func testTransitionToPrewarming() {
        var machine = MixStateMachine()
        machine.setHasNextTrack(true)

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        // Before prewarm time - no transition
        var events = machine.process(.timeUpdate(currentTime: 160, schedule: schedule))
        XCTAssertEqual(machine.state, .singlePlaying)
        XCTAssertTrue(events.isEmpty)

        // At prewarm time - should transition
        events = machine.process(.timeUpdate(currentTime: 165, schedule: schedule))
        XCTAssertEqual(machine.state, .prewarmingNext)
        XCTAssertEqual(events, [.prewarmStart])
    }

    func testNoPrewarmWithoutNextTrack() {
        var machine = MixStateMachine()
        // hasNextTrack = false

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        let events = machine.process(.timeUpdate(currentTime: 170, schedule: schedule))
        XCTAssertEqual(machine.state, .singlePlaying)
        XCTAssertTrue(events.isEmpty)
    }

    func testNoPrewarmWhenCrossfadeDisabled() {
        var machine = MixStateMachine()
        machine.setHasNextTrack(true)

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 0,
            prewarmSeconds: 15
        )!

        let events = machine.process(.timeUpdate(currentTime: 170, schedule: schedule))
        XCTAssertEqual(machine.state, .singlePlaying)
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - PrewarmingNext -> Crossfading

    func testTransitionToCrossfading() {
        var machine = MixStateMachine()
        machine.setHasNextTrack(true)

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        // Transition to prewarming
        _ = machine.process(.timeUpdate(currentTime: 165, schedule: schedule))
        XCTAssertEqual(machine.state, .prewarmingNext)

        // Mark next as ready
        var events = machine.process(.nextTrackReady)
        XCTAssertEqual(events, [.prewarmReady])
        XCTAssertTrue(machine.isNextReady)

        // At fade start - should transition
        events = machine.process(.timeUpdate(currentTime: 174, schedule: schedule))
        XCTAssertEqual(machine.state, .crossfading)
        XCTAssertEqual(events, [.fadeStart])
    }

    func testNoFadeWithoutReady() {
        var machine = MixStateMachine()
        machine.setHasNextTrack(true)

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        // Transition to prewarming but don't mark ready
        _ = machine.process(.timeUpdate(currentTime: 165, schedule: schedule))

        // At fade start - should NOT transition (not ready)
        let events = machine.process(.timeUpdate(currentTime: 174, schedule: schedule))
        XCTAssertEqual(machine.state, .prewarmingNext)
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Abort Scenarios

    func testAbortOnSeek() {
        var machine = MixStateMachine()
        machine.setHasNextTrack(true)

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        // Get into prewarming state
        _ = machine.process(.timeUpdate(currentTime: 165, schedule: schedule))
        XCTAssertEqual(machine.state, .prewarmingNext)

        // Seek before prewarm start
        let events = machine.process(.seekBefore(prewarmStartTime: 165))
        XCTAssertEqual(machine.state, .singlePlaying)
        XCTAssertEqual(events, [.fadeAbort(.seekCancelled)])
    }

    func testAbortOnQueueChanged() {
        var machine = MixStateMachine()
        machine.setHasNextTrack(true)

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        // Get into crossfading state
        _ = machine.process(.timeUpdate(currentTime: 165, schedule: schedule))
        _ = machine.process(.nextTrackReady)
        _ = machine.process(.timeUpdate(currentTime: 174, schedule: schedule))
        XCTAssertEqual(machine.state, .crossfading)

        // Queue changed
        let events = machine.process(.queueChanged)
        XCTAssertEqual(machine.state, .singlePlaying)
        XCTAssertEqual(events, [.fadeAbort(.queueChanged)])
    }

    func testAbortOnDisabled() {
        var machine = MixStateMachine()
        machine.setHasNextTrack(true)

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        // Get into crossfading state
        _ = machine.process(.timeUpdate(currentTime: 165, schedule: schedule))
        _ = machine.process(.nextTrackReady)
        _ = machine.process(.timeUpdate(currentTime: 174, schedule: schedule))
        XCTAssertEqual(machine.state, .crossfading)

        // Mix disabled
        let events = machine.process(.disabled)
        XCTAssertEqual(machine.state, .singlePlaying)
        XCTAssertEqual(events, [.fadeAbort(.disabled)])
    }

    func testAbortOnNextTrackFailed() {
        var machine = MixStateMachine()
        machine.setHasNextTrack(true)

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        // Get into prewarming state
        _ = machine.process(.timeUpdate(currentTime: 165, schedule: schedule))
        XCTAssertEqual(machine.state, .prewarmingNext)

        // Next track failed
        let events = machine.process(.nextTrackFailed(.streamRefreshFailed))
        XCTAssertEqual(machine.state, .singlePlaying)
        XCTAssertEqual(events, [.fadeAbort(.streamRefreshFailed)])
    }

    // MARK: - Fade Complete

    func testFadeComplete() {
        var machine = MixStateMachine()
        machine.setHasNextTrack(true)

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        // Get into crossfading state
        _ = machine.process(.timeUpdate(currentTime: 165, schedule: schedule))
        _ = machine.process(.nextTrackReady)
        _ = machine.process(.timeUpdate(currentTime: 174, schedule: schedule))
        XCTAssertEqual(machine.state, .crossfading)

        // Fade complete
        let events = machine.process(.fadeComplete)
        XCTAssertEqual(machine.state, .singlePlaying)
        XCTAssertEqual(events, [.fadeComplete])
        XCTAssertFalse(machine.hasNextTrack)
        XCTAssertFalse(machine.isNextReady)
    }

    // MARK: - Reset

    func testReset() {
        var machine = MixStateMachine()
        machine.setHasNextTrack(true)

        let schedule = MixScheduler.schedule(
            duration: 180,
            crossfadeSeconds: 6,
            prewarmSeconds: 15
        )!

        _ = machine.process(.timeUpdate(currentTime: 165, schedule: schedule))
        _ = machine.process(.nextTrackReady)
        XCTAssertEqual(machine.state, .prewarmingNext)

        machine.reset()
        XCTAssertEqual(machine.state, .singlePlaying)
        XCTAssertFalse(machine.hasNextTrack)
        XCTAssertFalse(machine.isNextReady)
    }
}
