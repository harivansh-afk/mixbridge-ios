import Foundation
import MixBridgeDJ

enum DJTransitionPlanValidationError: Error, LocalizedError {
    case fadeExceedsTrackDuration(fadeEnd: Double, trackDuration: Double)
    case invalidFadeStart(value: Double)
    case invalidFadeDuration(value: Double)

    var errorDescription: String? {
        switch self {
        case let .fadeExceedsTrackDuration(fadeEnd, duration):
            return "Fade end (\(String(format: "%.2f", fadeEnd))s) exceeds track duration (\(String(format: "%.2f", duration))s)"
        case let .invalidFadeStart(value):
            return "Invalid fade start: \(String(format: "%.2f", value))s"
        case let .invalidFadeDuration(value):
            return "Invalid fade duration: \(String(format: "%.2f", value))s"
        }
    }
}

extension DJTransitionPlan {
    func validated(outgoingDuration: Double) throws -> DJTransitionPlan {
        guard fadeStartSeconds >= 0 else {
            throw DJTransitionPlanValidationError.invalidFadeStart(value: fadeStartSeconds)
        }

        guard fadeDurationSeconds > 0 else {
            throw DJTransitionPlanValidationError.invalidFadeDuration(value: fadeDurationSeconds)
        }

        let fadeEnd = fadeStartSeconds + fadeDurationSeconds
        guard fadeEnd <= outgoingDuration else {
            throw DJTransitionPlanValidationError.fadeExceedsTrackDuration(fadeEnd: fadeEnd, trackDuration: outgoingDuration)
        }

        return self
    }

    func clamped(outgoingDuration: Double) -> DJTransitionPlan {
        let clampedFadeStart = max(0, min(fadeStartSeconds, outgoingDuration - 1))
        let maxFadeDuration = outgoingDuration - clampedFadeStart
        let clampedFadeDuration = max(0.5, min(fadeDurationSeconds, maxFadeDuration))

        return DJTransitionPlan(
            fadeDurationSeconds: clampedFadeDuration,
            fadeStartSeconds: clampedFadeStart,
            crossfadeCurve: crossfadeCurve,
            outgoingEQCurves: outgoingEQCurves,
            incomingEQCurves: incomingEQCurves,
            tempoMatch: tempoMatch,
            beatAlignment: beatAlignment,
            isFallback: isFallback
        )
    }
}
