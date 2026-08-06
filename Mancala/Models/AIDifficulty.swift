import Foundation

/// The four opponent skill levels.
///
/// This type is deliberately Foundation-only so the headless tools in `Scripts/`
/// can compile it without SwiftUI. The `tint` colour lives in a SwiftUI
/// extension in `GameSettings.swift`.
nonisolated enum AIDifficulty: String, CaseIterable, Identifiable, Sendable {
    case easy
    case medium
    case hard
    case impossible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .impossible: "Impossible"
        }
    }

    var description: String {
        switch self {
        case .easy:
            "Plays casually and misses plenty. A good first game."
        case .medium:
            "Looks a few turns ahead but still makes mistakes."
        case .hard:
            "Searches deeply and rarely gives anything away."
        case .impossible:
            "Full-strength search with exact endgame solving. Note that in Mancala the player who moves first has a real advantage, so moving second is an uphill game even for a perfect opponent."
        }
    }

    var promptInstruction: String {
        switch self {
        case .easy:
            "Choose a legal casual move. Do not deeply optimize."
        case .medium:
            "Prefer moves that earn an extra turn, capture stones, or avoid an obvious immediate loss."
        case .hard:
            "Evaluate all legal moves. Prioritize extra turns, captures, store advantage, and positions that reduce Player 1 capture opportunities."
        case .impossible:
            "This difficulty uses a deterministic solver instead of the language model."
        }
    }

    /// How this tier picks a move.
    ///
    /// Easy stays on the cheap one-ply heuristic; the rest drive
    /// `MancalaOptimalSolver` with progressively larger budgets and
    /// progressively smaller odds of deliberately playing a worse move.
    /// Impossible's budget is `nil` because it comes from user settings.
    var profile: AISearchProfile {
        switch self {
        case .easy:
            AISearchProfile(
                usesSearch: false,
                depthLimit: 1,
                maxPositions: 0,
                timeLimit: nil,
                exactEndgameStoneThreshold: 0,
                mistakeRate: 0.35,
                mistakePoolSize: 6
            )
        case .medium:
            AISearchProfile(
                usesSearch: true,
                depthLimit: 3,
                maxPositions: 40_000,
                timeLimit: 0.75,
                exactEndgameStoneThreshold: 6,
                mistakeRate: 0.12,
                mistakePoolSize: 3
            )
        case .hard:
            AISearchProfile(
                usesSearch: true,
                depthLimit: 7,
                maxPositions: 900_000,
                timeLimit: 2.5,
                exactEndgameStoneThreshold: 12,
                mistakeRate: 0.03,
                mistakePoolSize: 2
            )
        case .impossible:
            AISearchProfile(
                usesSearch: true,
                depthLimit: nil,
                maxPositions: 10_000_000,
                timeLimit: nil,
                exactEndgameStoneThreshold: MancalaOptimalSolver.defaultEndgameStoneThreshold,
                mistakeRate: 0,
                mistakePoolSize: 1
            )
        }
    }
}

/// The knobs that separate one difficulty from the next.
nonisolated struct AISearchProfile: Sendable {
    /// `false` means the tier uses `HeuristicAIPlayer` instead of the solver.
    let usesSearch: Bool
    /// Iterative-deepening cap in *turns*. `nil` lets the solver derive one from its budget.
    let depthLimit: Int?
    let maxPositions: Int
    let timeLimit: TimeInterval?
    /// Solve to terminal once this many or fewer stones sit outside the stores.
    let exactEndgameStoneThreshold: Int
    /// Odds of deliberately not playing the best move found.
    let mistakeRate: Double
    /// How many of the top-ranked moves a mistake picks from.
    let mistakePoolSize: Int
}
