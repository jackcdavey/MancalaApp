import Foundation

struct CompletedGameResult: Codable, Identifiable {
    let id: UUID
    let playerOneName: String
    let playerTwoName: String
    let playerOneScore: Int
    let playerTwoScore: Int
    let winnerName: String?

    init(
        id: UUID = UUID(),
        playerOneName: String,
        playerTwoName: String,
        playerOneScore: Int,
        playerTwoScore: Int,
        winnerName: String?
    ) {
        self.id = id
        self.playerOneName = playerOneName
        self.playerTwoName = playerTwoName
        self.playerOneScore = playerOneScore
        self.playerTwoScore = playerTwoScore
        self.winnerName = winnerName
    }

    var winnerText: String {
        winnerName.map { "\($0) won" } ?? "Draw game"
    }
}

struct SavedGameState: Codable {
    let pits: [Int]
    let currentPlayer: String
    let winner: String?
    let isDraw: Bool

    init(game: MancalaGame) {
        pits = game.pits
        currentPlayer = game.currentPlayer.rawValue
        winner = game.winner?.rawValue
        isDraw = game.isDraw
    }

    var game: MancalaGame {
        MancalaGame(
            pits: pits,
            currentPlayer: Player(rawValue: currentPlayer) ?? .playerOne,
            winner: winner.flatMap(Player.init(rawValue:)),
            isDraw: isDraw
        )
    }
}
