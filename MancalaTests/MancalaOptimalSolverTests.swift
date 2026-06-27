import Testing
@testable import Mancala

private final class SolverProgressBox: @unchecked Sendable {
    var messages: [String] = []
    var latestProgress: MancalaOptimalSolver.SearchProgress?
}

struct MancalaOptimalSolverTests {
    @Test func impossibleSolverReturnsLegalMoveWithinPositionBudget() {
        let game = MancalaGame(currentPlayer: .playerTwo)
        let progress = SolverProgressBox()

        let move = MancalaOptimalSolver.bestMove(
            pits: game.pits,
            currentPlayer: 2,
            maxPositions: 2_500,
            timeLimit: nil,
            progress: { progress.messages.append($0) },
            progressUpdate: { progress.latestProgress = $0 }
        )

        #expect(move != nil)
        #expect(game.legalPits(for: .playerTwo).contains(move ?? -1))
        #expect(progress.messages.contains { $0.contains("Budget:") })
        #expect((progress.latestProgress?.searched ?? 0) <= 2_500)
    }

    @Test func impossibleSolverHonorsShortTimeBudget() {
        let game = MancalaGame(currentPlayer: .playerTwo)
        let progress = SolverProgressBox()

        let move = MancalaOptimalSolver.bestMove(
            pits: game.pits,
            currentPlayer: 2,
            maxPositions: 100_000_000,
            timeLimit: 0.1,
            progress: { _ in },
            progressUpdate: { progress.latestProgress = $0 }
        )

        #expect(move != nil)
        #expect(game.legalPits(for: .playerTwo).contains(move ?? -1))
        #expect(progress.latestProgress?.timeLimit == 0.1)
    }

    @Test func impossibleSolverReturnsNilWhenNoLegalMoveExists() {
        let move = MancalaOptimalSolver.bestMove(
            pits: [0, 0, 0, 0, 0, 0, 24, 0, 0, 0, 0, 0, 0, 24],
            currentPlayer: 2,
            maxPositions: 100,
            timeLimit: nil,
            progress: { _ in },
            progressUpdate: { _ in }
        )

        #expect(move == nil)
    }
}
