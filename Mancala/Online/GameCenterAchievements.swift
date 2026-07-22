import Foundation
import GameKit

// Achievement identifiers, names, and triggers live in AchievementCatalog.swift.

struct MancalaMoveAchievementResult {
    let movingPlayer: Player
    let capturedStones: Int
    let earnedExtraTurn: Bool
}

@MainActor
enum GameCenterAchievements {
    static func reportMove(_ result: MancalaMoveAchievementResult, gameMode: GameMode, localPlayerSide: Player?) {
        guard isLocalAchievementPlayer(result.movingPlayer, gameMode: gameMode, localPlayerSide: localPlayerSide) else { return }

        var achievements: [MancalaAchievement] = []
        if result.earnedExtraTurn {
            achievements.append(.extraTurn)
        }
        if result.capturedStones > 0 {
            achievements.append(.capture)
        }
        if result.capturedStones >= AchievementThresholds.bigCaptureStones {
            achievements.append(.bigCapture)
        }

        report(achievements)
    }

    static func reportCompletedGame(
        _ game: MancalaGame,
        gameMode: GameMode,
        difficulty: AIDifficulty,
        localPlayerSide: Player?
    ) {
        guard let winner = game.winner,
              isLocalAchievementPlayer(winner, gameMode: gameMode, localPlayerSide: localPlayerSide) else {
            return
        }

        let winnerScore = game.storeCount(for: winner)
        let loserScore = game.storeCount(for: winner.opponent)
        let margin = winnerScore - loserScore
        var achievements: [MancalaAchievement] = [.firstWin]

        if margin <= AchievementThresholds.closeWinMargin {
            achievements.append(.closeWin)
        }
        if margin >= AchievementThresholds.dominantWinMargin {
            achievements.append(.dominantWin)
        }

        switch gameMode {
        case .singlePlayer:
            achievements.append(.beatAI)
            if difficulty == .hard || difficulty == .impossible {
                achievements.append(.beatHardAI)
            }
            if difficulty == .impossible {
                achievements.append(.beatImpossibleAI)
            }
        case .onlineMultiplayer:
            achievements.append(.onlineWin)
        case .twoPlayer, .zeroPlayer:
            break
        }

        report(achievements)
    }

    private static func isLocalAchievementPlayer(_ player: Player, gameMode: GameMode, localPlayerSide: Player?) -> Bool {
        switch gameMode {
        case .singlePlayer:
            player == .playerOne
        case .twoPlayer:
            true
        case .onlineMultiplayer:
            player == localPlayerSide
        case .zeroPlayer:
            false
        }
    }

    private static func report(_ achievements: [MancalaAchievement]) {
        guard GKLocalPlayer.local.isAuthenticated else { return }

        let reports = Set(achievements).map { achievement -> GKAchievement in
            let report = GKAchievement(identifier: achievement.rawValue)
            report.percentComplete = 100
            report.showsCompletionBanner = true
            return report
        }

        guard !reports.isEmpty else { return }

        GKAchievement.report(reports) { error in
            if let error {
                print("Unable to report Game Center achievements: \(error.localizedDescription)")
            }
        }
    }
}
