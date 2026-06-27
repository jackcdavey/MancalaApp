import Testing
@testable import Mancala

struct MancalaGameTests {
    @Test func initialBoardHasFourStonesInEachPitAndPlayerOneStarts() {
        let game = MancalaGame()

        #expect(game.pits == [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0])
        #expect(game.currentPlayer == .playerOne)
        #expect(game.winner == nil)
        #expect(game.isDraw == false)
        #expect(game.legalPits(for: .playerOne) == [0, 1, 2, 3, 4, 5])
        #expect(game.legalPits(for: .playerTwo).isEmpty)
    }

    @Test func resetCanStartEitherPlayer() {
        var game = MancalaGame()
        game.playPit(at: 0)

        game.reset(startingPlayer: .playerTwo)

        #expect(game.pits == [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0])
        #expect(game.currentPlayer == .playerTwo)
        #expect(game.winner == nil)
        #expect(game.isDraw == false)
    }

    @Test func sowingPathSkipsOpponentStore() {
        let game = MancalaGame(
            pits: [0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0],
            currentPlayer: .playerOne
        )

        #expect(game.sowingPath(from: 5) == [6, 7, 8, 9, 10, 11, 12, 0])
    }

    @Test func landingInOwnStoreKeepsTurn() {
        var game = MancalaGame()

        game.playPit(at: 2)

        #expect(game.currentPlayer == .playerOne)
        #expect(game.pits[6] == 1)
    }

    @Test func normalMovePassesTurnToOpponent() {
        var game = MancalaGame()

        game.playPit(at: 0)

        #expect(game.currentPlayer == .playerTwo)
        #expect(game.pits == [0, 5, 5, 5, 5, 4, 0, 4, 4, 4, 4, 4, 4, 0])
    }

    @Test func captureMovesLandingStoneAndOppositePitIntoStore() {
        var game = MancalaGame(
            pits: [0, 0, 1, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0],
            currentPlayer: .playerOne
        )

        game.playPit(at: 2)

        #expect(game.pits[3] == 0)
        #expect(game.pits[9] == 0)
        #expect(game.pits[6] == 6)
        #expect(game.winner == .playerOne)
    }

    @Test func sideEmptyCollectsRemainingStonesAndDeclaresWinner() {
        var game = MancalaGame(
            pits: [0, 0, 0, 0, 0, 1, 10, 1, 1, 1, 1, 1, 1, 12],
            currentPlayer: .playerOne
        )

        game.playPit(at: 5)

        #expect(game.pits[6] == 11)
        #expect(game.pits[13] == 18)
        #expect(game.winner == .playerTwo)
        #expect(game.isGameOver)
    }

    @Test func invalidCustomPitCountFallsBackToDefaultBoard() {
        let game = MancalaGame(pits: [1, 2, 3], currentPlayer: .playerTwo)

        #expect(game.pits == [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0])
        #expect(game.currentPlayer == .playerTwo)
    }
}
