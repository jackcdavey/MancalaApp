// Verifies every ChallengeCatalog layout is winnable within its move limit
// against a WORST-CASE opponent (exhaustive adversarial search, so the shipped
// AI can only be easier). Each player sow — extra turns included — costs one
// move from the budget. Run after editing the catalog:
//
//   swiftc -O -o /tmp/verify-challenges \
//     Mancala/Models/Player.swift Mancala/Models/MancalaGame.swift \
//     Mancala/Models/AIDifficulty.swift Mancala/AI/MancalaOptimalSolver.swift \
//     Mancala/Models/ChallengeCatalog.swift Scripts/verify-challenges.swift \
//   && /tmp/verify-challenges
//
// AIDifficulty lives in its own SwiftUI-free file so it can be compiled here;
// do not include Mancala/Models/GameSettings.swift, which imports SwiftUI.

import Foundation

struct SearchKey: Hashable {
    let pits: [Int]
    let isPlayerOne: Bool
    let movesUsed: Int
}

var memo: [SearchKey: Bool] = [:]

/// True when player one can force a win using at most `limit - used` more sows,
/// with player two playing perfectly against them.
func playerOneCanWin(_ game: MancalaGame, used: Int, limit: Int) -> Bool {
    if game.isGameOver {
        return game.winner == .playerOne
    }

    let key = SearchKey(pits: game.pits, isPlayerOne: game.currentPlayer == .playerOne, movesUsed: used)
    if let cached = memo[key] {
        return cached
    }

    let result: Bool
    if game.currentPlayer == .playerOne {
        if used >= limit {
            result = false
        } else {
            result = game.legalPits(for: .playerOne).contains { move in
                var next = game
                next.playPit(at: move)
                return playerOneCanWin(next, used: used + 1, limit: limit)
            }
        }
    } else {
        result = game.legalPits(for: .playerTwo).allSatisfy { move in
            var next = game
            next.playPit(at: move)
            return playerOneCanWin(next, used: used, limit: limit)
        }
    }

    memo[key] = result
    return result
}

@main
struct ChallengeVerifier {
    static func main() {
        var allPassed = true

        for challenge in ChallengeCatalog.all {
            let stoneTotal = challenge.pits.reduce(0, +)
            guard challenge.pits.count == 14 else {
                print("FAIL \(challenge.id): layout must have 14 slots")
                allPassed = false
                continue
            }

            // Minimal budget that still forces a win, to show how tight the limit is.
            var minimalBudget: Int?
            for budget in 1...(challenge.moveLimit + 3) {
                memo.removeAll(keepingCapacity: true)
                if playerOneCanWin(challenge.freshGame, used: 0, limit: budget) {
                    minimalBudget = budget
                    break
                }
            }

            if let minimalBudget, minimalBudget <= challenge.moveLimit {
                let slack = challenge.moveLimit - minimalBudget
                print("PASS \(challenge.id): forced win in \(minimalBudget) (limit \(challenge.moveLimit), slack \(slack), \(stoneTotal) stones)")
            } else if let minimalBudget {
                print("FAIL \(challenge.id): needs \(minimalBudget) moves but limit is \(challenge.moveLimit)")
                allPassed = false
            } else {
                print("FAIL \(challenge.id): no forced win within \(challenge.moveLimit + 3) moves")
                allPassed = false
            }
        }

        exit(allPassed ? 0 : 1)
    }
}
