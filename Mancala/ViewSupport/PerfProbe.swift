import SwiftUI

/// Counts how often labelled work happens and prints a per-second summary.
///
/// Temporary diagnostic scaffolding for the main menu's idle CPU cost: the
/// energy gauge says ~90% of a core with the 3D board's rendering disabled, and
/// the question is *what* is running at frame rate. Body evaluations are the
/// cheapest thing to count that distinguishes the candidates — a view whose body
/// runs 60 times a second on a menu nobody is touching is the culprit, and one
/// that runs twice isn't.
///
/// Compiled out entirely in release. Delete this file and its call sites once
/// the idle cost is settled.
@MainActor
enum PerfProbe {
    /// Flip to false to silence the probe without unpicking the call sites.
    static var isEnabled = true

    #if DEBUG
    private static var counts: [String: Int] = [:]
    private static var windowStart = CFAbsoluteTimeGetCurrent()
    #endif

    static func tick(_ label: String) {
        #if DEBUG
        guard isEnabled else { return }
        counts[label, default: 0] += 1

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - windowStart
        guard elapsed >= 1 else { return }

        let summary = counts
            .sorted { $0.value > $1.value }
            .map { "\($0.key) \(Int((Double($0.value) / elapsed).rounded()))/s" }
            .joined(separator: "   ")
        print("[PerfProbe] \(summary)")

        counts.removeAll(keepingCapacity: true)
        windowStart = now
        #endif
    }

    /// `tick` for callers that aren't on the main actor — notably RealityKit
    /// `System.update`, which is what counts *engine* frames as opposed to
    /// SwiftUI body evaluations. The hop costs a `Task` per call, which is fine
    /// at frame rate for a diagnostic and is why this isn't the default path.
    nonisolated static func tickFromAnyThread(_ label: String) {
        #if DEBUG
        Task { @MainActor in PerfProbe.tick(label) }
        #endif
    }
}

extension View {
    /// Counts one body evaluation of the view this is written inside. Returns
    /// `Self` so it can be dropped anywhere without disturbing the view type.
    func perfProbe(_ label: String) -> Self {
        PerfProbe.tick(label)
        return self
    }
}
