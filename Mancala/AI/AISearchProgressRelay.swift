import Foundation

/// Coalesces the solver's progress reports into a main-actor delivery that
/// cannot outrun the main thread.
///
/// The solver reports roughly a hundred times a second, and Impossible's search
/// runs for tens of seconds rather than the two or three the lower tiers are
/// capped at. Delivered one main-actor hop per report — a `Task { @MainActor
/// in ... }` per log line *and* one per progress tick — that left SwiftUI
/// re-evaluating the whole game view on every display frame for the length of
/// the search, which is why the board, the undo button and the settings sheet
/// all stopped responding while Impossible thought.
///
/// Here the search thread only ever appends to a buffer under a lock. At most
/// one drain is in flight at a time, and each one waits `minimumInterval`
/// before taking whatever piled up, so the main actor sees a bounded trickle
/// however fast the search reports. Nothing worth showing is lost: log lines
/// accumulate in order, and the newest progress tick wins because the ones it
/// replaces only ever described a smaller node count.
///
/// `nonisolated` on purpose. The project defaults to main-actor isolation, but
/// this type's whole job is to be written to from the search thread; the lock,
/// not the actor, is what makes that safe.
nonisolated final class AISearchProgressRelay: @unchecked Sendable {

    /// Matches `appendAIThought`'s own cap — buffering more than the log can
    /// hold would only be work for the main actor to throw away.
    private static let maximumBufferedEntries = 40

    private struct Buffer {
        var entries: [String] = []
        var update: MancalaOptimalSolver.SearchProgress?
        var isDrainScheduled = false
        var isStopped = false

        var isEmpty: Bool { entries.isEmpty && update == nil }

        /// - Returns: `true` if the caller now owns scheduling the next drain.
        mutating func claimDrain() -> Bool {
            guard !isDrainScheduled else { return false }
            isDrainScheduled = true
            return true
        }

        mutating func take() -> (entries: [String], update: MancalaOptimalSolver.SearchProgress?) {
            defer {
                entries = []
                update = nil
            }
            return (entries, update)
        }
    }

    private let lock = NSLock()
    private var buffer = Buffer()

    private let minimumInterval: Duration
    private let deliver: @MainActor @Sendable ([String], MancalaOptimalSolver.SearchProgress?) -> Void

    /// - Parameters:
    ///   - minimumInterval: the shortest gap between two deliveries. Ten a
    ///     second reads as live without costing a re-render every frame.
    ///   - deliver: run on the main actor with everything buffered since the
    ///     last call. `entries` may be empty; `update` may be `nil`.
    init(
        minimumInterval: Duration = .milliseconds(100),
        deliver: @escaping @MainActor @Sendable ([String], MancalaOptimalSolver.SearchProgress?) -> Void
    ) {
        self.minimumInterval = minimumInterval
        self.deliver = deliver
    }

    /// Pass to `MancalaOptimalSolver.search(progress:)`.
    var progressHandler: @Sendable (String) -> Void {
        { [self] entry in
            let needsDrain = lock.withLock {
                guard !buffer.isStopped else { return false }
                buffer.entries.append(entry)
                if buffer.entries.count > Self.maximumBufferedEntries {
                    buffer.entries.removeFirst(buffer.entries.count - Self.maximumBufferedEntries)
                }
                return buffer.claimDrain()
            }
            if needsDrain { scheduleDrain() }
        }
    }

    /// Pass to `MancalaOptimalSolver.search(progressUpdate:)`.
    var progressUpdateHandler: @Sendable (MancalaOptimalSolver.SearchProgress) -> Void {
        { [self] update in
            let needsDrain = lock.withLock {
                guard !buffer.isStopped else { return false }
                buffer.update = update
                return buffer.claimDrain()
            }
            if needsDrain { scheduleDrain() }
        }
    }

    /// Delivers the tail of the search at once, without waiting out the
    /// interval, and stops accepting anything further.
    ///
    /// Call this once the search task has returned. The closing log lines — the
    /// depth that completed, why the search stopped — are the ones worth
    /// reading, and they have to land before the caller logs the move it chose.
    @MainActor
    func finish() {
        let taken = lock.withLock { () -> (entries: [String], update: MancalaOptimalSolver.SearchProgress?) in
            buffer.isStopped = true
            return buffer.take()
        }

        if !taken.entries.isEmpty || taken.update != nil {
            deliver(taken.entries, taken.update)
        }
    }

    private func scheduleDrain() {
        Task { @MainActor [self] in
            try? await Task.sleep(for: minimumInterval)

            let taken = lock.withLock { () -> (entries: [String], update: MancalaOptimalSolver.SearchProgress?)? in
                guard !buffer.isStopped else { return nil }
                // Cleared before delivering, so anything the search reports
                // during the delivery schedules a fresh drain of its own
                // rather than being swallowed.
                buffer.isDrainScheduled = false
                return buffer.isEmpty ? nil : buffer.take()
            }

            guard let taken else { return }
            deliver(taken.entries, taken.update)
        }
    }
}
