import Foundation
import MixBridgeDJ

// MARK: - Errors

enum AIDJPlannerError: Error, LocalizedError {
    case missingAnalysis
    case invalidRequest(String)
    case requestFailed(statusCode: Int?)
    case decodeFailed
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAnalysis:
            return "Missing track analysis"
        case let .invalidRequest(reason):
            return "Invalid request: \(reason)"
        case let .requestFailed(code):
            return "Request failed with status \(code ?? -1)"
        case .decodeFailed:
            return "Failed to decode response"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Remote Planner (mixbridge.app API)

/// Plans DJ transitions using the mixbridge.app/api/dj/plan endpoint.
/// Uses simplified absolute-only time semantics.
@MainActor
struct AIDJRemotePlanner {
    private static let endpoint = URL(string: "https://mixbridge.app/api/dj/plan")!
    private static let timeout: TimeInterval = 50 // 50 seconds

    /// Plan a mix transition using the remote AI endpoint.
    func plan(request: AIDJPlanRequest) async throws -> AIDJPlanResponse {
        let backendRequest = request.toBackendRequest()

        logInfo(.dj, "AIDJ request: \(formatRequest(request))")

        let data = try await sendRequest(backendRequest)
        let response = try decodeResponse(data)

        logInfo(.dj, "AIDJ response: \(formatResponse(response))")

        return response
    }

    // MARK: - Network

    private func sendRequest(_ request: AIDJBackendRequest) async throws -> Data {
        var httpRequest = URLRequest(url: Self.endpoint)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.timeoutInterval = Self.timeout

        let encoder = JSONEncoder()
        let requestBody = try encoder.encode(request)
        httpRequest.httpBody = requestBody

        // Log the actual request JSON for debugging
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
            // Log error response body for debugging
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

    private func decodeResponse(_ data: Data) throws -> AIDJPlanResponse {
        do {
            let decoded = try JSONDecoder().decode(AIDJBackendResponse.self, from: data)
            return decoded.toPlanResponse()
        } catch {
            logWarning(.dj, "AIDJ decode failed: \(error)")
            throw AIDJPlannerError.decodeFailed
        }
    }

    // MARK: - Logging Helpers

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

    private func formatResponse(_ resp: AIDJPlanResponse) -> String {
        let plan = resp.plan
        var parts = [
            "fadeStart=\(String(format: "%.2f", plan.outgoingFadeStartSeconds))s",
            "duration=\(String(format: "%.2f", plan.fadeDurationSeconds))s",
            "curve=\(plan.crossfadeCurve)",
            "beat=\(plan.beatAlignment)",
            "tempo=\(plan.tempoMatch.enabled ? "on" : "off")",
        ]

        if !plan.outgoingEQCurves.isEmpty || !plan.incomingEQCurves.isEmpty {
            parts.append("eq=\(plan.outgoingEQCurves.count)/\(plan.incomingEQCurves.count)")
        }

        if let confidence = resp.confidence {
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

// MARK: - Local Planner

/// Plans DJ transitions locally using analysis data (no network).
/// Used as a fallback when the remote planner fails.
@MainActor
struct AIDJLocalPlanner {
    /// Plan a mix transition using local analysis.
    func plan(request: AIDJPlanRequest) -> AIDJMixPlan {
        let settings = DJTransitionPlannerSettings(
            crossfadeSeconds: request.settings.preferredFadeDurationSeconds,
            fadeCurve: request.settings.preferredCurve?.toDJ() ?? .equalPower,
            beatSyncEnabled: request.settings.allowBeatSync,
            tempoMatchEnabled: request.settings.allowTempoMatch,
            eqPolishEnabled: request.settings.allowEQPolish,
            preferBarSync: true,
            confidenceThreshold: 0.6
        )

        // Build analysis results from track info
        let outgoingAnalysis = buildAnalysis(from: request.outgoingTrack)
        let incomingAnalysis = buildAnalysis(from: request.incomingTrack)

        // Calculate fade start (near end of outgoing track)
        let fadeStart = max(0, request.outgoingTrack.durationSeconds - request.settings.preferredFadeDurationSeconds)

        let djPlan = DJTransitionPlanner.makePlan(
            outgoing: outgoingAnalysis,
            incoming: incomingAnalysis,
            fadeStartSeconds: fadeStart,
            fadeDurationSeconds: request.settings.preferredFadeDurationSeconds,
            settings: settings
        )

        return AIDJMixPlan(
            outgoingFadeStartSeconds: djPlan.fadeStartSeconds,
            fadeDurationSeconds: djPlan.fadeDurationSeconds,
            crossfadeCurve: AIDJCrossfadeCurve.fromDJ(djPlan.crossfadeCurve),
            incomingStartOffsetSeconds: 0,
            beatAlignment: AIDJBeatAlignmentMode.fromDJ(djPlan.beatAlignment),
            tempoMatch: AIDJTempoMatch(
                enabled: djPlan.tempoMatch.enabled,
                targetBPM: djPlan.tempoMatch.targetBPM,
                maxRateAdjustment: djPlan.tempoMatch.maxRateAdjustment,
                preservePitch: djPlan.tempoMatch.preservePitch
            ),
            outgoingEQCurves: djPlan.outgoingEQCurves.map { curve in
                AIDJEQCurve(
                    band: AIDJEQBand.fromDJ(curve.band),
                    keyframes: curve.keyframes.map { AIDJEQKeyframe(progress: $0.progress, gainDB: $0.gainDB) }
                )
            },
            incomingEQCurves: djPlan.incomingEQCurves.map { curve in
                AIDJEQCurve(
                    band: AIDJEQBand.fromDJ(curve.band),
                    keyframes: curve.keyframes.map { AIDJEQKeyframe(progress: $0.progress, gainDB: $0.gainDB) }
                )
            },
            isFallback: true
        )
    }

    private func buildAnalysis(from track: AIDJTrackInfo) -> DJAnalysisResult {
        DJAnalysisResult(
            bpm: track.bpm ?? 120,
            beatOffsetSeconds: track.beatOffsetSeconds ?? 0,
            timeSignatureNumerator: 4,
            timeSignatureDenominator: 4,
            confidence: track.timingConfidence ?? 0.5,
            metadata: AnalysisMetadata(
                analysisVersion: AnalysisMetadata.currentVersion,
                analysisDurationMs: 0,
                failureReason: nil
            )
        )
    }
}
