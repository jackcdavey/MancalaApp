import Foundation

/// A puzzle board the player must win within a fixed number of sows.
///
/// Layouts use the same 14-slot scheme as `MancalaGame`: indices 0–5 are the
/// player's pits, 6 their store, 7–12 the opponent's pits, 13 the opponent's
/// store. Every challenge starts on the player's turn, and each sow the player
/// makes (extra turns included) costs one move from the budget. The catalog's
/// layouts are verified winnable within their limits against a worst-case
/// opponent by `Scripts/verify-challenges.swift`; rerun it after editing them.
struct MancalaChallenge: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let pits: [Int]
    let moveLimit: Int
    let aiDifficulty: AIDifficulty

    var freshGame: MancalaGame {
        MancalaGame(pits: pits, currentPlayer: .playerOne)
    }
}

enum ChallengeCatalog {
    /// Ordered easiest first; the list order is the difficulty order shown in
    /// the challenge menu.
    static let all: [MancalaChallenge] = [
        MancalaChallenge(
            id: "last-stone",
            title: "The Last Stone",
            subtitle: "Bank your final stone to end it",
            pits: [0, 0, 0, 0, 0, 1, 10, 0, 0, 1, 0, 0, 0, 4],
            moveLimit: 1,
            aiDifficulty: .easy
        ),
        MancalaChallenge(
            id: "chain-reaction",
            title: "Chain Reaction",
            subtitle: "Land in your store for a free turn — order matters",
            pits: [0, 0, 0, 0, 2, 1, 8, 0, 2, 0, 2, 0, 0, 3],
            moveLimit: 2,
            aiDifficulty: .easy
        ),
        MancalaChallenge(
            id: "grand-capture",
            title: "The Grand Capture",
            subtitle: "Land in an empty pit to raid the far side",
            pits: [0, 1, 0, 0, 0, 1, 6, 1, 0, 0, 8, 0, 1, 5],
            moveLimit: 2,
            aiDifficulty: .easy
        ),
        MancalaChallenge(
            id: "swift-finish",
            title: "Swift Finish",
            subtitle: "Clear your side before the budget runs dry",
            pits: [0, 0, 1, 0, 2, 1, 11, 3, 0, 2, 0, 1, 0, 4],
            moveLimit: 3,
            aiDifficulty: .medium
        ),
        MancalaChallenge(
            id: "uphill-climb",
            title: "Uphill Climb",
            subtitle: "Behind on stones — captures are your ladder",
            pits: [0, 0, 1, 0, 2, 1, 9, 1, 2, 4, 1, 1, 1, 8],
            moveLimit: 5,
            aiDifficulty: .hard
        ),
        MancalaChallenge(
            id: "masters-gauntlet",
            title: "Master's Gauntlet",
            subtitle: "A tangled board, a ruthless opponent, eight sows",
            pits: [3, 1, 0, 2, 1, 2, 7, 1, 4, 2, 0, 3, 2, 10],
            moveLimit: 8,
            aiDifficulty: .hard
        )
    ]
}
