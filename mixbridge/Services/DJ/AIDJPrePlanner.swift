import Foundation
import MixBridgeDJ

/// Pre-plans DJ transitions when tracks are identified, caching results for instant retrieval at prewarm time.
/// This eliminates network latency during playback by planning ahead.
@MainActor
final class AIDJPrePlanner {
    static let shared = AIDJPrePlanner()

    // MARK: - Types

    struct CachedPlan {
        let plan: AIDJMixPlan
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
            preferredCurve: curve.map { AIDJCrossfadeCurve.fromDJ($0) },
            allowTempoMatch: settings.allowTempoMatch,
            allowBeatSync: settings.allowBeatSync,
            allowEQPolish: settings.allowEQPolish
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
            let response = try await AIDJRemotePlanner().plan(request: request)

            // Validate the plan before caching
            let validatedPlan = try response.plan.validated(
                outgoingDuration: outgoing.duration,
                incomingDuration: incoming.duration
            )

            cache[key] = CachedPlan(plan: validatedPlan, createdAt: Date(), isFallback: false)
            logInfo(.dj, "AIDJPrePlanner: cached AI plan for \(key.outgoingId) → \(key.incomingId)")

        } catch {
            logWarning(.dj, "AIDJPrePlanner: AI plan failed, caching fallback: \(error)")

            // Cache a local fallback plan
            let fallbackPlan = AIDJMixPlan.localFallback(
                outgoingDuration: outgoing.duration,
                outgoingAnalysis: outgoingAnalysis,
                incomingAnalysis: incomingAnalysis,
                settings: settings
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
                    return cached
                }
                if !pendingRequests.contains(key) {
                    break
                }
            }
        }

        // Return cached if available
        if let cached = cache[key], !cached.isStale {
            return cached
        }

        // Generate fallback
        logDebug(.dj, "AIDJPrePlanner: generating fallback for \(outgoingId) → \(incomingId)")
        let fallbackPlan = AIDJMixPlan.localFallback(
            outgoingDuration: outgoingDuration,
            outgoingAnalysis: outgoingAnalysis,
            incomingAnalysis: incomingAnalysis,
            settings: settings
        )

        return CachedPlan(plan: fallbackPlan, createdAt: Date(), isFallback: true)
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
