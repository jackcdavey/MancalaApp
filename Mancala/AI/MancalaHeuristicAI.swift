import Foundation

/// A reproducible random source, so an arena run can be replayed exactly.
/// `SystemRandomNumberGenerator` is what the app uses; this is for `Scripts/ai-arena.swift`.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // SplitMix64 dislikes a zero seed less than most, but nudge it anyway.
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Move selection for every difficulty below Impossible.
///
/// Lives outside `ContentView` so `Scripts/ai-arena.swift` can play whole games
/// against it without a UI. The file deliberately avoids SwiftUI: the arena
/// script substitutes a bare `AIDifficulty` enum the same way
/// `Scripts/verify-challenges.swift` does.
enum MancalaHeuristicAI {
    static func chooseMove(
        in game: MancalaGame,
        for player: Player,
        difficulty: AIDifficulty
    ) -> Int? {
        var generator = SystemRandomNumberGenerator()
        return chooseMove(in: game, for: player, difficulty: difficulty, using: &generator)
    }

    static func chooseMove(
        in game: MancalaGame,
        for player: Player,
        difficulty: AIDifficulty,
        using generator: inout some RandomNumberGenerator
    ) -> Int? {
        let legalPits = game.legalPits(for: player)
        guard !legalPits.isEmpty else { return nil }

        let ranked = legalPits.map { pit in
            (pit: pit, score: score(move: pit, in: game, for: player, difficulty: difficulty))
        }

        return ranked.max { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.pit < rhs.pit
            }
            return lhs.score < rhs.score
        }?.pit
    }

    private static func score(
        move pitIndex: Int,
        in game: MancalaGame,
        for player: Player,
        difficulty: AIDifficulty
    ) -> Int {
        var simulated = game
        let startingStore = simulated.storeCount(for: player)
        let opponentStartingStore = simulated.storeCount(for: player.opponent)
        let path = simulated.sowingPath(from: pitIndex)
        let lastIndex = path.last
        let capturedStones = lastIndex.flatMap { simulated.captureMove(afterLandingAt: $0)?.capturedStones } ?? 0
        simulated.playPit(at: pitIndex)

        let storeGain = simulated.storeCount(for: player) - startingStore
        let opponentStoreGain = simulated.storeCount(for: player.opponent) - opponentStartingStore
        let extraTurnBonus = simulated.currentPlayer == player && !simulated.isGameOver ? 18 : 0
        let winBonus = simulated.winner == player ? 1_000 : 0
        let drawPenalty = simulated.isDraw ? 8 : 0
        let lossPenalty = simulated.winner == player.opponent ? 1_000 : 0
        let captureBonus = capturedStones * 5
        let storeAdvantage = simulated.storeCount(for: player) - simulated.storeCount(for: player.opponent)
        let sideBalance = player == .playerOne
            ? simulated.pits[0...5].reduce(0, +) - simulated.pits[7...12].reduce(0, +)
            : simulated.pits[7...12].reduce(0, +) - simulated.pits[0...5].reduce(0, +)

        let terminal = winBonus - drawPenalty - lossPenalty

        switch difficulty {
        case .easy:
            return storeGain + extraTurnBonus / 3 + captureBonus / 4
        case .medium:
            let base = storeGain * 4 + extraTurnBonus
            return base + captureBonus + storeAdvantage * 2
        case .hard:
            let base = storeGain * 6 + extraTurnBonus + captureBonus
            return base + storeAdvantage * 4 + sideBalance - opponentStoreGain * 3 + terminal
        case .impossible:
            let base = storeGain * 8 + extraTurnBonus + captureBonus
            return base + storeAdvantage * 5 + sideBalance + terminal
        }
    }
}
