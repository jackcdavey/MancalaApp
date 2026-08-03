import Foundation

/// The single place that turns a difficulty into a move.
///
/// `ContentView` and `Scripts/ai-arena.swift` both go through here, which is
/// what makes a headless match a faithful rehearsal of what the app will do.
enum AIMoveSelector {

    /// Chooses a pit for `player`.
    ///
    /// - Parameters:
    ///   - optionsOverride: supplied by the app for Impossible, whose budget
    ///     comes from user settings rather than the difficulty profile.
    ///   - rng: drives the deliberate-mistake rate of the lower tiers. Seed it
    ///     to make a game reproducible.
    static func selectPit(
        in game: MancalaGame,
        for player: Player,
        difficulty: AIDifficulty,
        optionsOverride: MancalaOptimalSolver.Options? = nil,
        rng: inout SplitMix64,
        progress: @escaping @Sendable (String) -> Void = { _ in },
        progressUpdate: @escaping @Sendable (MancalaOptimalSolver.SearchProgress) -> Void = { _ in }
    ) -> Int? {
        let legalPits = game.legalPits(for: player)
        guard !legalPits.isEmpty else { return nil }
        guard legalPits.count > 1 else { return legalPits.first }

        let profile = difficulty.profile
        let ordered: [Int]

        if profile.usesSearch {
            let outcome = MancalaOptimalSolver.search(
                pits: game.pits,
                currentPlayer: player == .playerOne ? 1 : 2,
                options: optionsOverride ?? options(for: profile),
                progress: progress,
                progressUpdate: progressUpdate
            )
            // A cancelled or empty search still has to produce a legal move.
            ordered = outcome.rankedMoves.isEmpty ? legalPits : outcome.rankedMoves.map(\.move)
        } else {
            ordered = HeuristicAIPlayer
                .rankedPits(in: game, for: player, difficulty: difficulty, legalPits: legalPits)
                .map(\.pit)
        }

        return applyMistakeRate(to: ordered, profile: profile, rng: &rng)
    }

    /// The solver settings implied by a difficulty profile.
    static func options(for profile: AISearchProfile) -> MancalaOptimalSolver.Options {
        MancalaOptimalSolver.Options(
            maxPositions: profile.maxPositions,
            timeLimit: profile.timeLimit,
            depthLimit: profile.depthLimit,
            exactEndgameStoneThreshold: profile.exactEndgameStoneThreshold
        )
    }

    /// Occasionally plays something other than the best move.
    ///
    /// This is what separates the tiers in practice. It also stops the lower
    /// tiers being perfectly deterministic — before this, the AI replayed the
    /// same game forever and one memorised line beat it every time.
    private static func applyMistakeRate(
        to ordered: [Int],
        profile: AISearchProfile,
        rng: inout SplitMix64
    ) -> Int? {
        guard let best = ordered.first else { return nil }
        guard profile.mistakeRate > 0, ordered.count > 1 else { return best }
        guard rng.nextUnitInterval() < profile.mistakeRate else { return best }

        let poolSize = min(max(profile.mistakePoolSize, 2), ordered.count)
        // Index 0 is the best move, so sample from the alternatives.
        guard let offset = rng.nextIndex(below: poolSize - 1) else { return best }
        return ordered[offset + 1]
    }
}
