import Foundation

/// A small seedable generator so the lower difficulties can vary their play
/// without becoming untestable.
///
/// The app seeds it from the clock; `Scripts/ai-arena.swift` seeds it from a
/// flag, which is what makes a headless match reproducible move for move.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A `Double` in `0..<1`.
    mutating func nextUnitInterval() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// An index in `0..<count`, or `nil` when `count` is not positive.
    mutating func nextIndex(below count: Int) -> Int? {
        guard count > 0 else { return nil }
        return Int(next() % UInt64(count))
    }
}
