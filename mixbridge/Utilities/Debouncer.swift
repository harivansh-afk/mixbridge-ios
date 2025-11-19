import Foundation

/// A generic debouncer that delays execution of an action until a specified time interval has passed
/// without any new calls. Thread-safe and cancellable.
///
/// Use cases:
/// - Debouncing seek operations during slider dragging
/// - Debouncing volume adjustments
/// - Debouncing search queries
///
/// Example:
/// ```swift
/// let debouncer = Debouncer(delay: 0.3) { [weak self] in
///     await self?.performExpensiveOperation()
/// }
/// debouncer.call()  // Will execute after 0.3s if no other calls are made
/// ```
final class Debouncer {
    // MARK: - Properties

    /// The time interval to wait before executing the action
    private let delay: TimeInterval

    /// The work item that will be executed after the delay
    private var workItem: DispatchWorkItem?

    /// The dispatch queue on which to execute the action
    private let queue: DispatchQueue

    /// The action to execute after the delay
    private let action: () -> Void

    /// Lock for thread-safe access to workItem
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a new debouncer
    /// - Parameters:
    ///   - delay: The time interval to wait before executing the action
    ///   - queue: The dispatch queue on which to execute the action (defaults to main queue)
    ///   - action: The action to execute after the delay
    init(delay: TimeInterval, queue: DispatchQueue = .main, action: @escaping () -> Void) {
        self.delay = delay
        self.queue = queue
        self.action = action
    }

    // MARK: - Public Methods

    /// Schedules the action to be executed after the delay.
    /// If called again before the delay expires, the previous execution is cancelled.
    func call() {
        lock.lock()
        defer { lock.unlock() }

        // Cancel any pending work
        workItem?.cancel()

        // Create new work item
        let newWorkItem = DispatchWorkItem { [weak self] in
            self?.action()
        }

        workItem = newWorkItem

        // Schedule execution
        queue.asyncAfter(deadline: .now() + delay, execute: newWorkItem)
    }

    /// Cancels any pending execution
    func cancel() {
        lock.lock()
        defer { lock.unlock() }

        workItem?.cancel()
        workItem = nil
    }

    /// Immediately executes the action and cancels any pending execution
    func callNow() {
        lock.lock()
        defer { lock.unlock() }

        workItem?.cancel()
        workItem = nil

        queue.async { [weak self] in
            self?.action()
        }
    }

    deinit {
        cancel()
    }
}
