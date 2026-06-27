import Foundation
import Testing
@testable import Mancala

struct MancalaPersistenceTests {
    @Test func savedGameStateRoundTripsBoardTurnAndOutcome() throws {
        let original = MancalaGame(
            pits: [0, 0, 0, 0, 0, 0, 24, 0, 0, 0, 0, 0, 0, 24],
            currentPlayer: .playerTwo,
            winner: nil,
            isDraw: true
        )

        let data = try JSONEncoder().encode(SavedGameState(game: original))
        let decoded = try JSONDecoder().decode(SavedGameState.self, from: data).game

        #expect(decoded.pits == original.pits)
        #expect(decoded.currentPlayer == .playerTwo)
        #expect(decoded.winner == nil)
        #expect(decoded.isDraw)
    }

    @Test func savedGameStateFallsBackToPlayerOneWhenStoredTurnIsUnknown() throws {
        let json = """
        {
            "pits": [4,4,4,4,4,4,0,4,4,4,4,4,4,0],
            "currentPlayer": "unknown",
            "winner": null,
            "isDraw": false
        }
        """

        let state = try JSONDecoder().decode(SavedGameState.self, from: Data(json.utf8))

        #expect(state.game.currentPlayer == .playerOne)
    }

    @Test func completedGameResultFormatsWinsAndDraws() {
        let win = CompletedGameResult(
            playerOneName: "Avery",
            playerTwoName: "Blake",
            playerOneScore: 31,
            playerTwoScore: 17,
            winnerName: "Avery"
        )
        let draw = CompletedGameResult(
            playerOneName: "Avery",
            playerTwoName: "Blake",
            playerOneScore: 24,
            playerTwoScore: 24,
            winnerName: nil
        )

        #expect(win.winnerText == "Avery won")
        #expect(draw.winnerText == "Draw game")
    }
}
