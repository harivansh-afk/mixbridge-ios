import Foundation

/// Validation result for a transition plan.
public struct DJPlanValidationResult: Sendable {
    /// Whether the plan passed validation.
    public let isValid: Bool

    /// List of validation issues found.
    public let issues: [String]

    /// The validated (and potentially clamped) plan.
    public let validatedPlan: DJTransitionPlan

    public init(isValid: Bool, issues: [String], validatedPlan: DJTransitionPlan) {
        self.isValid = isValid
        self.issues = issues
        self.validatedPlan = validatedPlan
    }
}

/// Safety gate and validator for transition plans.
/// Ensures all plan values are within safe bounds and provides fallback behavior.
public struct DJPlanValidator: Sendable {

    // MARK: - Validation Bounds

    /// Minimum fade duration in seconds.
    public let minFadeDuration: Double

    /// Maximum fade duration in seconds.
    public let maxFadeDuration: Double

    /// Minimum EQ gain in dB.
    public let minEQGainDB: Double

    /// Maximum EQ gain in dB.
    public let maxEQGainDB: Double

    /// Minimum tempo rate (1.0 - maxTempoAdjustment).
    public let minTempoRate: Double

    /// Maximum tempo rate (1.0 + maxTempoAdjustment).
    public let maxTempoRate: Double

    /// Minimum confidence threshold for timing data.
    public let minTimingConfidence: Double

    /// Creates a validator with the specified bounds.
    public init(
        minFadeDuration: Double = 2.0,
        maxFadeDuration: Double = 32.0,
        minEQGainDB: Double = -24.0,
        maxEQGainDB: Double = 12.0,
        maxTempoAdjustment: Double = 0.08,
        minTimingConfidence: Double = 0.5
    ) {
        self.minFadeDuration = minFadeDuration
        self.maxFadeDuration = maxFadeDuration
        self.minEQGainDB = minEQGainDB
        self.maxEQGainDB = maxEQGainDB
        self.minTempoRate = 1.0 - maxTempoAdjustment
        self.maxTempoRate = 1.0 + maxTempoAdjustment
        self.minTimingConfidence = minTimingConfidence
    }

    /// Default validator with standard DJ mixing bounds.
    public static let `default` = DJPlanValidator()

    // MARK: - Validation

    /// Validates a transition plan and returns a validated/clamped version.
    /// If validation fails critically, returns a fallback plan.
    /// - Parameters:
    ///   - plan: The plan to validate.
    ///   - outgoingTiming: Timing for the outgoing track (for beat alignment validation).
    ///   - incomingTiming: Timing for the incoming track (for tempo match validation).
    /// - Returns: Validation result with issues and validated plan.
    public func validate(
        plan: DJTransitionPlan,
        outgoingTiming: DJTrackTiming?,
        incomingTiming: DJTrackTiming?
    ) -> DJPlanValidationResult {
        var issues: [String] = []
        var useFallback = false

        // Validate fade duration
        var fadeDuration = plan.fadeDurationSeconds
        if fadeDuration < minFadeDuration {
            issues.append("Fade duration \(fadeDuration)s below minimum \(minFadeDuration)s - clamped")
            fadeDuration = minFadeDuration
        } else if fadeDuration > maxFadeDuration {
            issues.append("Fade duration \(fadeDuration)s above maximum \(maxFadeDuration)s - clamped")
            fadeDuration = maxFadeDuration
        }

        // Validate fade start
        var fadeStart = plan.fadeStartSeconds
        if fadeStart < 0 {
            issues.append("Fade start \(fadeStart)s is negative - clamped to 0")
            fadeStart = 0
        }

        // Validate EQ curves
        let outgoingEQ = validateEQCurves(plan.outgoingEQCurves, label: "outgoing", issues: &issues)
        let incomingEQ = validateEQCurves(plan.incomingEQCurves, label: "incoming", issues: &issues)

        // Validate tempo matching
        var tempoMatch = plan.tempoMatch
        if tempoMatch.enabled {
            if outgoingTiming == nil || incomingTiming == nil {
                issues.append("Tempo match enabled but timing data missing - disabled")
                tempoMatch = .disabled
            } else {
                if let outTiming = outgoingTiming, !outTiming.isValid {
                    issues.append("Outgoing timing confidence too low (\(outTiming.confidence)) - using fallback")
                    useFallback = true
                }

                if let inTiming = incomingTiming, !inTiming.isValid {
                    issues.append("Incoming timing confidence too low (\(inTiming.confidence)) - using fallback")
                    useFallback = true
                }

                // Validate tempo rate would be within bounds
                if let inTiming = incomingTiming, tempoMatch.enabled {
                    let rate = tempoMatch.computeRate(incomingBPM: inTiming.bpm)
                    if rate < minTempoRate || rate > maxTempoRate {
                        issues.append("Computed tempo rate \(rate) outside safe bounds - rate will be clamped")
                    }
                }
            }
        }

        // Validate beat alignment
        var beatAlignment = plan.beatAlignment
        if beatAlignment != .none {
            let timingValid = outgoingTiming?.isValid ?? false
            if !timingValid {
                issues.append("Beat alignment requested but outgoing timing invalid - disabled")
                beatAlignment = .none
            }
        }

        // If critical issues found, use fallback plan
        if useFallback {
            let fallbackPlan = DJTransitionPlan.fallback(fadeDuration: fadeDuration, fadeStart: fadeStart)
            return DJPlanValidationResult(
                isValid: false,
                issues: issues,
                validatedPlan: fallbackPlan
            )
        }

        // Create validated plan
        let validatedPlan = DJTransitionPlan(
            fadeDurationSeconds: fadeDuration,
            fadeStartSeconds: fadeStart,
            crossfadeCurve: plan.crossfadeCurve,
            outgoingEQCurves: outgoingEQ,
            incomingEQCurves: incomingEQ,
            tempoMatch: tempoMatch,
            beatAlignment: beatAlignment,
            isFallback: false
        )

        return DJPlanValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            validatedPlan: validatedPlan
        )
    }

    /// Creates a safe fallback plan when timing confidence is absent or invalid.
    /// - Parameters:
    ///   - fadeDuration: Desired fade duration (will be clamped).
    ///   - fadeStart: When to start the fade.
    /// - Returns: A deterministic fallback plan with neutral settings.
    public func createFallbackPlan(fadeDuration: Double, fadeStart: Double) -> DJTransitionPlan {
        let clampedDuration = max(minFadeDuration, min(maxFadeDuration, fadeDuration))
        let clampedStart = max(0, fadeStart)

        return DJTransitionPlan(
            fadeDurationSeconds: clampedDuration,
            fadeStartSeconds: clampedStart,
            crossfadeCurve: .equalPower,
            outgoingEQCurves: DJEQBand.allCases.map { .flat(band: $0) },
            incomingEQCurves: DJEQBand.allCases.map { .flat(band: $0) },
            tempoMatch: .disabled,
            beatAlignment: .none,
            isFallback: true
        )
    }

    // MARK: - Private

    private func validateEQCurves(
        _ curves: [DJEQCurve],
        label: String,
        issues: inout [String]
    ) -> [DJEQCurve] {
        return curves.map { curve in
            let clampedKeyframes = curve.keyframes.map { keyframe in
                var gainDB = keyframe.gainDB
                if gainDB < minEQGainDB {
                    issues.append("\(label) \(curve.band) EQ gain \(gainDB)dB below minimum - clamped")
                    gainDB = minEQGainDB
                } else if gainDB > maxEQGainDB {
                    issues.append("\(label) \(curve.band) EQ gain \(gainDB)dB above maximum - clamped")
                    gainDB = maxEQGainDB
                }
                return DJEQKeyframe(progress: keyframe.progress, gainDB: gainDB)
            }
            return DJEQCurve(band: curve.band, keyframes: clampedKeyframes)
        }
    }
}
