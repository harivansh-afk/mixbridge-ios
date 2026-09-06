@preconcurrency import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct DownloadReliabilityTests {
    @MainActor static func main() async throws {
        try contract()
        try await interruptedTransfer()
        try await exhaustion()
        try await permanentFailures()
        try await cancellation()
        try await scheduler()
        print("PASS: 6 offline download regression groups (contract, interrupted transfer/cleanup, exhaustion, permanent failures, cancellation, global scheduler)")
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.invalid/audio")!, statusCode: status,
                        httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    static func contract() throws {
        for code in ["protected_content", "provider_unavailable", "provider_auth_required", "unsupported_format", "auth_required"] {
            let body = try JSONSerialization.data(withJSONObject: ["detail": ["code": code, "message": "SECRET", "retryable": true]])
            let error = DownloadFailure.response(response(422), data: body)
            check(!error.retryable && !DownloadFailure.canRetryManually(error), "permanent codes must not offer retry")
            check(!DownloadFailure.message(error).contains("SECRET"), "server message leaked")
        }
        let legacy = Data(#"{"detail":"Extraction failed: This video is DRM protected SECRET"}"#.utf8)
        check(DownloadFailure.response(response(400), data: legacy).code == "protected_content", "rolling upgrade DRM")
        let limited = DownloadFailure.response(response(429, ["Retry-After": "12"]))
        check(DirectDownloadRetry.delay(for: limited, attempt: 0, jitter: 0) == 12, "Retry-After seconds")
        let now = Date(timeIntervalSince1970: 0)
        check(DownloadFailure.retryDelay("Thu, 01 Jan 1970 00:00:20 GMT", now: now) == 20, "Retry-After date")
        let longWait = DownloadFailure.response(response(503, ["Retry-After": "120"]))
        check(DirectDownloadRetry.delay(for: longWait, attempt: 0, jitter: 0) == nil, "do not shorten long hints")
        check(DownloadFailure.retryDelay("NaN", now: now) == nil, "invalid hint")
    }

    static func bytes(_ values: [UInt8], error: Error? = nil) -> AsyncThrowingStream<UInt8, Error> {
        AsyncThrowingStream { continuation in
            values.forEach { continuation.yield($0) }
            continuation.finish(throwing: error)
        }
    }

    @MainActor static func interruptedTransfer() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        var attempts = 0
        var delays: [Double] = []
        var published = false
        try await DirectDownloadRetry.run(sleep: { delays.append($0) }, jitter: { 0 }) {
            attempts += 1
            check(!FileManager.default.fileExists(atPath: path.path), "partial must be gone before next attempt")
            let stream = attempts == 1 ? bytes([1, 2], error: URLError(.networkConnectionLost)) : bytes([3, 4, 5])
            try await DownloadFileWriter.write(stream, to: path, expectedLength: 3) { _ in }
            published = true
        }
        check(attempts == 2 && delays == [1] && published, "retry then publish")
        let data = try Data(contentsOf: path)
        check(data == Data([3, 4, 5]), "restart must not append partial bytes")
        do {
            try await DownloadFileWriter.write(bytes([1]), to: path, expectedLength: 2) { _ in }
            preconditionFailure("truncated response accepted")
        } catch {
            check((error as? URLError)?.code == .networkConnectionLost, "truncation typed as interruption")
            check(!FileManager.default.fileExists(atPath: path.path), "truncated file removed")
        }
    }

    @MainActor static func exhaustion() async throws {
        var attempts = 0
        var delays: [Double] = []
        do {
            try await DirectDownloadRetry.run(sleep: { delays.append($0) }, jitter: { 0 }) {
                attempts += 1
                throw URLError(.networkConnectionLost)
            }
            preconditionFailure("retry budget did not exhaust")
        } catch {
            check(attempts == 3 && delays == [1, 2], "bounded retry budget")
        }
    }

    @MainActor static func permanentFailures() async throws {
        let errors: [Error] = [DownloadFailure.response(response(401)), DownloadFailure.response(response(403)),
                               DownloadFailure.response(response(404)), CocoaError(.fileWriteOutOfSpace),
                               URLError(.cancelled), URLError(.serverCertificateUntrusted),
                               DownloadFailure(code: "protected_content", retryable: false, retryAfter: nil)]
        for error in errors {
            var attempts = 0
            do {
                try await DirectDownloadRetry.run(sleep: { _ in preconditionFailure("permanent error slept") }) {
                    attempts += 1
                    throw error
                }
            } catch { check(attempts == 1, "permanent error retried") }
        }
    }

    @MainActor static func cancellation() async throws {
        var attempts = 0
        do {
            try await DirectDownloadRetry.run(sleep: { _ in throw CancellationError() }) {
                attempts += 1
                throw URLError(.timedOut)
            }
        } catch is CancellationError {
            check(attempts == 1, "backoff cancellation retried")
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try await DownloadFileWriter.write(bytes([1], error: CancellationError()), to: path, expectedLength: 2) { _ in }
            preconditionFailure("cancelled write succeeded")
        } catch is CancellationError {
            check(!FileManager.default.fileExists(atPath: path.path), "cancelled partial retained")
        }
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await DirectDownloadRetry.run { preconditionFailure("cancelled task started network") }
        }
        do { try await task.value; preconditionFailure("cancel lost") } catch is CancellationError { }
    }

    @MainActor static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("scheduler failed to make progress")
    }

    @MainActor static func scheduler() async throws {
        let queue = DownloadScheduler()
        var gates: [String: CheckedContinuation<Void, Never>] = [:]
        var started: [String] = []
        var running = 0
        var maximum = 0
        for id in ["a", "b", "c", "d", "e"] {
            queue.enqueue(id) {
                running += 1
                maximum = max(maximum, running)
                started.append(id)
                await withCheckedContinuation { gates[id] = $0 }
                running -= 1
            }
        }
        await waitUntil { gates.count == 3 }
        check(started.count == 3 && maximum == 3, "global cap across callers")
        check(queue.cancel("d"), "queued cancellation")
        check(!queue.cancel("a"), "active cancellation")
        check(!queue.enqueue("a") {}, "active cancellation must retain ownership during cleanup")
        check(!started.contains("e"), "cancel must not prematurely release slot")
        gates.removeValue(forKey: "a")!.resume()
        await waitUntil { started.contains("e") }
        check(!started.contains("d") && maximum == 3, "cancelled queued job must never start")
        for gate in gates.values { gate.resume() }
        gates.removeAll()
        await waitUntil { running == 0 && !queue.contains("e") }
        check(queue.enqueue("a") {}, "cleanup must release id for future retries")
    }
}
