import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An allowlisted presentation contract, never a server/extractor error string.
struct DownloadFailure: LocalizedError, Sendable {
    let code: String
    let retryable: Bool
    let retryAfter: TimeInterval?

    nonisolated var errorDescription: String? {
        switch code {
        case "protected_content": return "SoundCloud does not make this track available for offline download."
        case "provider_unavailable": return "This track is unavailable for offline download."
        case "unsupported_format": return "This track has no supported offline audio format."
        case "provider_auth_required": return "The provider requires access that offline downloads do not support."
        case "auth_required": return "Your sign-in has expired. Please sign out and sign in again."
        case "too_large": return "This track exceeds the 50 MiB download limit."
        case "rate_limited": return "The service is busy. Please try again later."
        case "provider_temporary": return "The service is temporarily unavailable. Please try again later."
        default: return "Unable to download this track."
        }
    }

    nonisolated static func response(_ response: HTTPURLResponse, data: Data = Data(), now: Date = Date()) -> DownloadFailure {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let detail = object?["detail"] as? [String: Any]
        let known = ["protected_content", "provider_unavailable", "unsupported_format", "provider_auth_required",
                     "auth_required", "too_large", "rate_limited", "provider_temporary", "extraction_failed", "invalid_request", "internal_error"]
        let supplied = detail?["code"] as? String
        let fallback: String
        switch response.statusCode {
        case 401, 403: fallback = "auth_required"
        case 404, 410: fallback = "provider_unavailable"
        case 413: fallback = "too_large"
        case 429: fallback = "rate_limited"
        case 502, 503, 504: fallback = "provider_temporary"
        default: fallback = "extraction_failed"
        }
        // Recognize only the old backend's exact DRM phrase during a rolling upgrade.
        let legacy = (object?["detail"] as? String)?.lowercased() ?? ""
        let code = supplied.flatMap { known.contains($0) ? $0 : nil }
            ?? (legacy.contains("this video is drm protected") ? "protected_content" : fallback)
        let transient = ["rate_limited", "provider_temporary"].contains(code)
            && [429, 502, 503, 504].contains(response.statusCode)
            && (detail?["retryable"] as? Bool != false)
        return DownloadFailure(code: code, retryable: transient,
                               retryAfter: retryDelay(response.value(forHTTPHeaderField: "Retry-After"), now: now))
    }

    nonisolated static func retryDelay(_ value: String?, now: Date) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }

    nonisolated static func canRetryManually(_ error: Error) -> Bool {
        guard let failure = error as? DownloadFailure else { return true }
        return failure.retryable
    }

    nonisolated static func message(_ error: Error) -> String {
        if let failure = error as? DownloadFailure { return failure.errorDescription! }
        if error is URLError { return "The connection was interrupted. Check your connection and try again." }
        // Other local errors are not trusted presentation strings either.
        return "Unable to download this track. Check your connection, sign-in and available storage."
    }
}

/// Only used around a direct GET transfer, never around /download or token POSTs.
/// The caller owns cleanup and its global concurrency slot for the entire loop.
enum DirectDownloadRetry {
    @MainActor
    static func run(
        sleep: (TimeInterval) async throws -> Void = { delay in
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        },
        jitter: () -> Double = { Double.random(in: 0...0.25) },
        operation: () async throws -> Void
    ) async throws {
        for attempt in 0...2 {
            try Task.checkCancellation()
            do {
                try await operation()
                try Task.checkCancellation()
                return
            } catch {
                try Task.checkCancellation()
                guard attempt < 2, let delay = delay(for: error, attempt: attempt, jitter: jitter()) else { throw error }
                try await sleep(delay)
            }
        }
    }

    nonisolated static func delay(for error: Error, attempt: Int, jitter: Double) -> TimeInterval? {
        let hint: TimeInterval
        if let failure = error as? DownloadFailure {
            guard failure.retryable else { return nil }
            hint = failure.retryAfter ?? 0
        } else if let urlError = error as? URLError,
                  [.networkConnectionLost, .timedOut, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed].contains(urlError.code) {
            hint = 0
        } else { return nil }
        // Never shorten a server hint. Long waits are left to a later manual attempt.
        guard hint <= 30 else { return nil }
        return max(hint, pow(2, Double(attempt)) + min(max(jitter, 0), 0.25))
    }
}
