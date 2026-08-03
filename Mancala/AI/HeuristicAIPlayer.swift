import Foundation

/// The cheap one-ply move chooser used by the Easy tier, and as a fallback for
/// any tier whose search is unavailable.
///
/// This was previously a `private func` on `ContentView` that read the view's
/// `@State` board directly. It takes the board as a parameter now so the
/// headless tools in `Scripts/` can drive it. The scoring weights are unchanged
/// from that version, so existing behaviour is preserved.
enum HeuristicAIPlayer {

    struct RankedPit {
        let pit: Int
        let score: Int
    }

    /// Legal pits ranked best-first for `player`.
    static func rankedPits(
        in game: MancalaGame,
        for player: Player,
        difficulty: AIDifficulty,
        legalPits: [Int]
    ) -> [RankedPit] {
        let ranked = legalPits.map { pitIndex -> RankedPit in
            var simulatedGame = game
            let startingStore = simulatedGame.storeCount(for: player)
            let opponentStartingStore = simulatedGame.storeCount(for: player.opponent)
            let path = simulatedGame.sowingPath(from: pitIndex)
            let lastIndex = path.last
            let capturedStones = lastIndex.flatMap { simulatedGame.captureMove(afterLandingAt: $0)?.capturedStones } ?? 0
            simulatedGame.playPit(at: pitIndex)

            let storeGain = simulatedGame.storeCount(for: player) - startingStore
            let opponentStoreGain = simulatedGame.storeCount(for: player.opponent) - opponentStartingStore
            let extraTurnBonus = simulatedGame.currentPlayer == player && !simulatedGame.isGameOver ? 18 : 0
            let winBonus = simulatedGame.winner == player ? 1_000 : 0
            let drawPenalty = simulatedGame.isDraw ? 8 : 0
            let lossPenalty = simulatedGame.winner == player.opponent ? 1_000 : 0
            let captureBonus = capturedStones * 5
            let storeAdvantage = simulatedGame.storeCount(for: player) - simulatedGame.storeCount(for: player.opponent)
            let sideBalance = player == .playerOne
                ? simulatedGame.pits[0...5].reduce(0, +) - simulatedGame.pits[7...12].reduce(0, +)
                : simulatedGame.pits[7...12].reduce(0, +) - simulatedGame.pits[0...5].reduce(0, +)

            let score: Int
            switch difficulty {
            case .easy:
                score = storeGain + extraTurnBonus / 3 + captureBonus / 4
            case .medium:
                score = storeGain * 4 + extraTurnBonus + captureBonus + storeAdvantage * 2
            case .hard, .impossible:
                score = storeGain * 6 + extraTurnBonus + captureBonus + storeAdvantage * 4 + sideBalance - opponentStoreGain * 3 + winBonus - drawPenalty - lossPenalty
            }

            return RankedPit(pit: pitIndex, score: score)
        }

        // `max(by:)` in the previous implementation kept replacing the incumbent
        // on a tie, so ties resolved to the *highest* pit index. Preserved here
        // so extracting this function did not silently change how Easy plays.
        return ranked.sorted { left, right in
            left.score == right.score ? left.pit > right.pit : left.score > right.score
        }
    }

    static func bestPit(
        in game: MancalaGame,
        for player: Player,
        difficulty: AIDifficulty,
        legalPits: [Int]
    ) -> Int? {
        rankedPits(in: game, for: player, difficulty: difficulty, legalPits: legalPits).first?.pit
    }
}
