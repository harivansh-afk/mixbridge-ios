import Foundation

/// One queue for individual taps and all batches. A cancelled active job retains
/// ownership until its cleanup finishes, so a new job cannot delete its files.
@MainActor
final class DownloadScheduler {
    private let limit: Int
    private var active: [String: Task<Void, Never>] = [:]
    private var pending: [(id: String, operation: () async -> Void)] = []

    init(limit: Int = 3) {
        precondition(limit > 0)
        self.limit = limit
    }

    func contains(_ id: String) -> Bool {
        active[id] != nil || pending.contains { $0.id == id }
    }

    @discardableResult
    func enqueue(_ id: String, operation: @escaping () async -> Void) -> Bool {
        guard !contains(id) else { return false }
        pending.append((id, operation))
        pump()
        return true
    }

    /// True when queued work was removed before it started.
    @discardableResult
    func cancel(_ id: String) -> Bool {
        if let task = active[id] {
            task.cancel()
            return false
        }
        let wasPending = pending.contains { $0.id == id }
        pending.removeAll { $0.id == id }
        return wasPending
    }

    private func pump() {
        while active.count < limit, !pending.isEmpty {
            let job = pending.removeFirst()
            active[job.id] = Task {
                await job.operation()
                active.removeValue(forKey: job.id)
                pump()
            }
        }
    }
}
