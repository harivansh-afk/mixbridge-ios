import Foundation
import MixBridgeDJ

/// Pre-plans DJ transitions when tracks are identified, caching results for instant retrieval at prewarm time.
/// This eliminates network latency during playback by planning ahead.
@MainActor
final class AIDJPrePlanner {
    static let shared = AIDJPrePlanner()

    // MARK: - Types

    struct CachedPlan {
        let plan: DJTransitionPlan
        let createdAt: Date
        let isFallback: Bool

        var age: TimeInterval { Date().timeIntervalSince(createdAt) }
        var isStale: Bool { age > 300 } // 5 minutes
    }

    struct PlanKey: Hashable {
        let outgoingId: String
        let incomingId: String

        init(_ outgoingId: String, _ incomingId: String) {
            self.outgoingId = outgoingId
            self.incomingId = incomingId
        }
    }

    // MARK: - State

    private var cache: [PlanKey: CachedPlan] = [:]
    private var pendingRequests: Set<PlanKey> = []
    private var settings: AIDJMixSettings = .default

    private init() {}

    // MARK: - Configuration

    /// Update the mix settings used for planning
    func configure(settings: AIDJMixSettings) {
        self.settings = settings
    }

    func configure(fadeDuration: Double, curve: DJCrossfadeCurve?) {
        settings = AIDJMixSettings(
            preferredFadeDurationSeconds: fadeDuration,
            preferredCurve: curve,
            allowTempoMatch: settings.allowTempoMatch,
            allowBeatSync: settings.allowBeatSync,
            allowEQPolish: settings.allowEQPolish,
            maxRateAdjustment: settings.maxRateAdjustment,
            bassSwapDepth: settings.bassSwapDepth,
            midsSwapDepth: settings.midsSwapDepth,
            highsSwapDepth: settings.highsSwapDepth
        )
    }

    // MARK: - Pre-Planning

    /// Pre-plan a transition between two tracks. Call this when the next track is identified.
    /// This runs the AI planning in the background and caches the result.
    func preplan(
        outgoing: Track,
        outgoingAnalysis: DJAnalysisResult,
        incoming: Track,
        incomingAnalysis: DJAnalysisResult
    ) async {
        let key = PlanKey(outgoing.id, incoming.id)

        // Skip if already cached or in progress
        guard cache[key] == nil || cache[key]?.isStale == true else {
            logDebug(.dj, "AIDJPrePlanner: cache hit for \(key.outgoingId) → \(key.incomingId)")
            return
        }
        guard !pendingRequests.contains(key) else {
            logDebug(.dj, "AIDJPrePlanner: request already pending for \(key.outgoingId) → \(key.incomingId)")
            return
        }

        pendingRequests.insert(key)
        defer { pendingRequests.remove(key) }

        logInfo(.dj, "AIDJPrePlanner: pre-planning \(outgoing.id) → \(incoming.id)")

        let request = AIDJPlanRequest.from(
            outgoing: outgoing,
            outgoingAnalysis: outgoingAnalysis,
            incoming: incoming,
            incomingAnalysis: incomingAnalysis,
            settings: settings
        )

        do {
            let plan = try await AIDJRemotePlanner().plan(request: request)

            // Validate the plan before caching
            let validatedPlan = try plan.validated(outgoingDuration: outgoing.duration)

            cache[key] = CachedPlan(plan: validatedPlan, createdAt: Date(), isFallback: false)
            logInfo(.dj, "AIDJPrePlanner: cached AI plan for \(key.outgoingId) → \(key.incomingId)")

        } catch {
            logWarning(.dj, "AIDJPrePlanner: AI plan failed, caching fallback: \(error)")

            // Cache a local fallback plan
            let fallbackPlan = makeFallbackPlan(
                outgoingDuration: outgoing.duration,
                outgoingAnalysis: outgoingAnalysis,
                incomingAnalysis: incomingAnalysis
            )

            cache[key] = CachedPlan(plan: fallbackPlan, createdAt: Date(), isFallback: true)
        }
    }

    // MARK: - Retrieval

    /// Get a cached plan if available. Returns nil if no plan is cached.
    func getPlan(outgoingId: String, incomingId: String) -> CachedPlan? {
        let key = PlanKey(outgoingId, incomingId)
        return cache[key]
    }

    /// Get a plan, waiting for pending request if necessary. Falls back to local plan if needed.
    func getPlanOrFallback(
        outgoingId: String,
        outgoingDuration: Double,
        outgoingAnalysis: DJAnalysisResult,
        incomingId: String,
        incomingDuration _: Double,
        incomingAnalysis: DJAnalysisResult
    ) async -> CachedPlan {
        let key = PlanKey(outgoingId, incomingId)

        // Wait briefly for pending request
        if pendingRequests.contains(key) {
            logDebug(.dj, "AIDJPrePlanner: waiting for pending request \(outgoingId) → \(incomingId)")
            for _ in 0 ..< 10 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if let cached = cache[key] {
                    let adjusted = applyUserSettings(
                        to: cached.plan,
                        outgoingDuration: outgoingDuration,
                        outgoingAnalysis: outgoingAnalysis
                    )
                    return CachedPlan(plan: adjusted, createdAt: cached.createdAt, isFallback: cached.isFallback)
                }
                if !pendingRequests.contains(key) {
                    break
                }
            }
        }

        // Return cached if available
        if let cached = cache[key], !cached.isStale {
            let adjusted = applyUserSettings(
                to: cached.plan,
                outgoingDuration: outgoingDuration,
                outgoingAnalysis: outgoingAnalysis
            )
            return CachedPlan(plan: adjusted, createdAt: cached.createdAt, isFallback: cached.isFallback)
        }

        // Generate fallback
        logDebug(.dj, "AIDJPrePlanner: generating fallback for \(outgoingId) → \(incomingId)")
        let fallbackPlan = makeFallbackPlan(
            outgoingDuration: outgoingDuration,
            outgoingAnalysis: outgoingAnalysis,
            incomingAnalysis: incomingAnalysis
        )

        let adjusted = applyUserSettings(
            to: fallbackPlan,
            outgoingDuration: outgoingDuration,
            outgoingAnalysis: outgoingAnalysis
        )
        return CachedPlan(plan: adjusted, createdAt: Date(), isFallback: true)
    }

    // MARK: - Fallback Planning

    private func makeFallbackPlan(
        outgoingDuration: Double,
        outgoingAnalysis: DJAnalysisResult,
        incomingAnalysis: DJAnalysisResult
    ) -> DJTransitionPlan {
        let fadeDuration = min(settings.preferredFadeDurationSeconds, outgoingDuration * 0.5)
        let fadeStart = max(0, outgoingDuration - fadeDuration)

        let plannerSettings = DJTransitionPlannerSettings(
            crossfadeSeconds: fadeDuration,
            fadeCurve: settings.preferredCurve ?? .equalPower,
            beatSyncEnabled: settings.allowBeatSync,
            tempoMatchEnabled: settings.allowTempoMatch,
            eqPolishEnabled: settings.allowEQPolish,
            preferBarSync: true,
            confidenceThreshold: 0.6
        )

        let plan = DJTransitionPlanner.makePlan(
            outgoing: outgoingAnalysis,
            incoming: incomingAnalysis,
            fadeStartSeconds: fadeStart,
            fadeDurationSeconds: fadeDuration,
            settings: plannerSettings
        )

        return DJTransitionPlan(
            fadeDurationSeconds: plan.fadeDurationSeconds,
            fadeStartSeconds: plan.fadeStartSeconds,
            crossfadeCurve: plan.crossfadeCurve,
            outgoingEQCurves: plan.outgoingEQCurves,
            incomingEQCurves: plan.incomingEQCurves,
            tempoMatch: plan.tempoMatch,
            beatAlignment: plan.beatAlignment,
            isFallback: true
        )
    }

    private func applyUserSettings(
        to plan: DJTransitionPlan,
        outgoingDuration: Double,
        outgoingAnalysis: DJAnalysisResult
    ) -> DJTransitionPlan {
        let clampedFadeDuration = min(max(2.0, settings.preferredFadeDurationSeconds), 20.0)
        let fadeDuration = min(clampedFadeDuration, outgoingDuration)
        let fadeStart = max(0, outgoingDuration - fadeDuration)

        let curve = settings.preferredCurve ?? plan.crossfadeCurve

        let tempoMatch: DJTempoMatchConfig
        if settings.allowTempoMatch {
            tempoMatch = DJTempoMatchConfig(
                enabled: true,
                targetBPM: outgoingAnalysis.bpm,
                maxRateAdjustment: settings.maxRateAdjustment,
                preservePitch: true
            )
        } else {
            tempoMatch = .disabled
        }

        let (outgoingEQ, incomingEQ) = makeSwapCurves()
        let beatAlignment = settings.allowBeatSync ? plan.beatAlignment : .none

        return DJTransitionPlan(
            fadeDurationSeconds: fadeDuration,
            fadeStartSeconds: fadeStart,
            crossfadeCurve: curve,
            outgoingEQCurves: outgoingEQ,
            incomingEQCurves: incomingEQ,
            tempoMatch: tempoMatch,
            beatAlignment: beatAlignment,
            isFallback: plan.isFallback
        )
    }

    private func makeSwapCurves() -> (outgoing: [DJEQCurve], incoming: [DJEQCurve]) {
        guard settings.allowEQPolish else { return ([], []) }

        let lowDepth = max(0.0, min(1.0, settings.bassSwapDepth))
        let midDepth = max(0.0, min(1.0, settings.midsSwapDepth))
        let highDepth = max(0.0, min(1.0, settings.highsSwapDepth))

        var outgoing: [DJEQCurve] = []
        var incoming: [DJEQCurve] = []

        func appendCurves(band: DJEQBand, depth: Double) {
            guard depth > 0.001 else { return }
            let maxCut = -24.0 * depth
            let swapPoint = 0.5

            outgoing.append(DJEQCurve(band: band, keyframes: [
                DJEQKeyframe(progress: 0.0, gainDB: 0.0),
                DJEQKeyframe(progress: swapPoint, gainDB: maxCut),
                DJEQKeyframe(progress: 1.0, gainDB: maxCut),
            ]))

            incoming.append(DJEQCurve(band: band, keyframes: [
                DJEQKeyframe(progress: 0.0, gainDB: maxCut),
                DJEQKeyframe(progress: swapPoint, gainDB: 0.0),
                DJEQKeyframe(progress: 1.0, gainDB: 0.0),
            ]))
        }

        appendCurves(band: .low, depth: lowDepth)
        appendCurves(band: .mid, depth: midDepth)
        appendCurves(band: .high, depth: highDepth)

        return (outgoing, incoming)
    }

    // MARK: - Cache Management

    /// Clear the plan cache
    func clearCache() {
        cache.removeAll()
        logDebug(.dj, "AIDJPrePlanner: cache cleared")
    }

    /// Remove stale entries from the cache
    func pruneStaleEntries() {
        let staleKeys = cache.filter { $0.value.isStale }.map { $0.key }
        for key in staleKeys {
            cache.removeValue(forKey: key)
        }
        if !staleKeys.isEmpty {
            logDebug(.dj, "AIDJPrePlanner: pruned \(staleKeys.count) stale entries")
        }
    }

    /// Invalidate a specific transition (e.g., when queue changes)
    func invalidate(outgoingId: String, incomingId: String) {
        let key = PlanKey(outgoingId, incomingId)
        cache.removeValue(forKey: key)
    }

    /// Invalidate all plans for a track (e.g., when track is removed from queue)
    func invalidateAllForTrack(_ trackId: String) {
        let keysToRemove = cache.keys.filter { $0.outgoingId == trackId || $0.incomingId == trackId }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
    }

    // MARK: - Debug

    var cacheStats: (count: Int, fallbackCount: Int) {
        let total = cache.count
        let fallbacks = cache.values.filter { $0.isFallback }.count
        return (total, fallbacks)
    }
}

// MARK: - Planner Internals

enum AIDJPlannerError: Error, LocalizedError {
    case requestFailed(statusCode: Int?)
    case decodeFailed
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(code):
            return "Request failed with status \(code ?? -1)"
        case .decodeFailed:
            return "Failed to decode response"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

@MainActor
private struct AIDJRemotePlanner {
    private static let endpoint = URL(string: "https://mixbridge.app/api/dj/plan")!
    private static let timeout: TimeInterval = 50 // 50 seconds

    func plan(request: AIDJPlanRequest) async throws -> DJTransitionPlan {
        let backendRequest = request.toBackendRequest()

        logInfo(.dj, "AIDJ request: \(formatRequest(request))")

        let data = try await sendRequest(backendRequest)
        let decoded = try decodeResponse(data)
        let plan = decoded.toTransitionPlan()

        logInfo(.dj, "AIDJ response: \(formatResponse(plan, confidence: decoded.confidence))")

        return plan
    }

    private func sendRequest(_ request: AIDJBackendRequest) async throws -> Data {
        var httpRequest = URLRequest(url: Self.endpoint)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.timeoutInterval = Self.timeout

        let encoder = JSONEncoder()
        let requestBody = try encoder.encode(request)
        httpRequest.httpBody = requestBody

        if let jsonString = String(data: requestBody, encoding: .utf8) {
            logDebug(.dj, "AIDJ request body: \(truncate(jsonString, max: 2000))")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: httpRequest)
        } catch {
            throw AIDJPlannerError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIDJPlannerError.requestFailed(statusCode: nil)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let errorBody = String(data: data, encoding: .utf8) {
                logWarning(.dj, "AIDJ request failed: status=\(httpResponse.statusCode), body=\(truncate(errorBody, max: 500))")
            } else {
                logWarning(.dj, "AIDJ request failed: status=\(httpResponse.statusCode)")
            }
            throw AIDJPlannerError.requestFailed(statusCode: httpResponse.statusCode)
        }

        logDebug(.dj, "AIDJ raw response: \(truncate(String(data: data, encoding: .utf8) ?? ""))")

        return data
    }

    private func decodeResponse(_ data: Data) throws -> AIDJBackendResponse {
        do {
            return try JSONDecoder().decode(AIDJBackendResponse.self, from: data)
        } catch {
            logWarning(.dj, "AIDJ decode failed: \(error)")
            throw AIDJPlannerError.decodeFailed
        }
    }

    private func formatRequest(_ req: AIDJPlanRequest) -> String {
        let out = req.outgoingTrack
        let inc = req.incomingTrack

        var parts = [
            "out=\(out.trackId)",
            "in=\(inc.trackId)",
            "bpm=\(formatOptional(out.bpm))/\(formatOptional(inc.bpm))",
            "dur=\(String(format: "%.0f", out.durationSeconds))/\(String(format: "%.0f", inc.durationSeconds))s",
            "fade=\(String(format: "%.1f", req.settings.preferredFadeDurationSeconds))s",
        ]

        if let curve = req.settings.preferredCurve {
            parts.append("curve=\(curve.rawValue)")
        }

        return parts.joined(separator: ", ")
    }

    private func formatResponse(_ plan: DJTransitionPlan, confidence: Double?) -> String {
        var parts = [
            "fadeStart=\(String(format: "%.2f", plan.fadeStartSeconds))s",
            "duration=\(String(format: "%.2f", plan.fadeDurationSeconds))s",
            "curve=\(plan.crossfadeCurve)",
            "beat=\(plan.beatAlignment)",
            "tempo=\(plan.tempoMatch.enabled ? "on" : "off")",
        ]

        if !plan.outgoingEQCurves.isEmpty || !plan.incomingEQCurves.isEmpty {
            parts.append("eq=\(plan.outgoingEQCurves.count)/\(plan.incomingEQCurves.count)")
        }

        if let confidence {
            parts.append("conf=\(String(format: "%.2f", confidence))")
        }

        return parts.joined(separator: ", ")
    }

    private func formatOptional(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "-"
    }

    private func truncate(_ value: String, max: Int = 500) -> String {
        value.count <= max ? value : String(value.prefix(max)) + "…"
    }
}
