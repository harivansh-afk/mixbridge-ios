import Foundation
import MixBridgeDJ

@MainActor
protocol AIDJPlanner {
    func plan(request: AIDJMixPlanRequest) async throws -> AIDJMixPlanResponse
}

enum AIDJPlannerError: Error {
    case missingAnalysis
    case invalidRequest(String)
}

@MainActor
final class AIDJPlannerProvider {
    static let shared = AIDJPlannerProvider()
    var planner: AIDJPlanner

    private init() {
        self.planner = AIDJFallbackPlanner(
            primary: AIDJConvexPlanner(),
            fallback: AIDJLocalPlanner()
        )
    }
}

@MainActor
struct AIDJFallbackPlanner: AIDJPlanner {
    let primary: AIDJPlanner
    let fallback: AIDJPlanner

    func plan(request: AIDJMixPlanRequest) async throws -> AIDJMixPlanResponse {
        do {
            return try await primary.plan(request: request)
        } catch {
            logWarning(.dj, "AIDJFallbackPlanner: primary failed, using fallback: \(error)")
            return try await fallback.plan(request: request)
        }
    }
}

@MainActor
struct AIDJLocalPlanner: AIDJPlanner {
    func plan(request: AIDJMixPlanRequest) async throws -> AIDJMixPlanResponse {
        guard let outgoingAnalysis = request.outgoing.analysis,
              let incomingAnalysis = request.incoming.analysis else {
            throw AIDJPlannerError.missingAnalysis
        }

        let settings = DJTransitionPlannerSettings(
            crossfadeSeconds: request.context?.suggestedFadeDurationSeconds
                ?? request.context?.userCrossfadeSeconds
                ?? 6,
            fadeCurve: localFadeCurve(from: request),
            beatSyncEnabled: request.context?.allowBeatSync ?? true,
            tempoMatchEnabled: request.context?.allowTempoMatch ?? true,
            eqPolishEnabled: request.context?.allowEQPolish ?? true,
            preferBarSync: request.context?.preferBarSync ?? true,
            confidenceThreshold: request.constraints?.minTimingConfidence ?? 0.6
        )

        let fadeStart = request.context?.suggestedFadeStartSeconds ?? 0
        let fadeDuration = request.context?.suggestedFadeDurationSeconds
            ?? request.context?.userCrossfadeSeconds
            ?? 6

        let plan = DJTransitionPlanner.makePlan(
            outgoing: outgoingAnalysis.toDJAnalysisResult(),
            incoming: incomingAnalysis.toDJAnalysisResult(),
            fadeStartSeconds: fadeStart,
            fadeDurationSeconds: fadeDuration,
            settings: settings
        )

        let response = AIDJMixPlanResponse(
            schemaVersion: request.schemaVersion,
            plan: AIDJMixPlan(
                fadeDurationSeconds: plan.fadeDurationSeconds,
                fadeStartSeconds: plan.fadeStartSeconds,
                crossfadeCurve: AIDJCrossfadeCurve(from: plan.crossfadeCurve),
                outgoingEQCurves: plan.outgoingEQCurves.map { $0.toAIDJCurve() },
                incomingEQCurves: plan.incomingEQCurves.map { $0.toAIDJCurve() },
                tempoMatch: AIDJTempoMatch(
                    enabled: plan.tempoMatch.enabled,
                    targetBPM: plan.tempoMatch.targetBPM,
                    maxRateAdjustment: plan.tempoMatch.maxRateAdjustment,
                    preservePitch: plan.tempoMatch.preservePitch
                ),
                beatAlignment: AIDJBeatAlignmentMode(from: plan.beatAlignment),
                isFallback: plan.isFallback
            ),
            confidence: outgoingAnalysis.confidence,
            warnings: nil,
            debug: nil
        )

        return response
    }

    private func localFadeCurve(from request: AIDJMixPlanRequest) -> FadeCurve {
        if let curve = request.context?.fadeCurve {
            switch curve {
            case .equalPower:
                return .equalPower
            case .linear:
                return .linear
            case .constantPower:
                return .sCurve
            }
        }
        if request.preferences?.preferEqualPower == true {
            return .equalPower
        }
        return .equalPower
    }
}

extension AIDJCrossfadeCurve {
    init(from curve: DJCrossfadeCurve) {
        switch curve {
        case .equalPower:
            self = .equalPower
        case .linear:
            self = .linear
        case .constantPower:
            self = .constantPower
        }
    }
}

extension AIDJBeatAlignmentMode {
    init(from mode: DJBeatAlignmentMode) {
        switch mode {
        case .beat:
            self = .beat
        case .bar:
            self = .bar
        case .none:
            self = .none
        }
    }
}

extension DJEQCurve {
    func toAIDJCurve() -> AIDJEQCurve {
        let band: AIDJEQBand
        switch self.band {
        case .low:
            band = .low
        case .mid:
            band = .mid
        case .high:
            band = .high
        }
        let keyframes = self.keyframes.map { AIDJEQKeyframe(progress: $0.progress, gainDB: $0.gainDB) }
        return AIDJEQCurve(band: band, keyframes: keyframes)
    }
}
