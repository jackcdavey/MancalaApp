import Testing
@testable import Mancala

/// Covers the difficulty ladder and the solver invariants that were previously
/// only observable by playing the game by hand.
///
/// `Scripts/ai-arena.swift` runs the same checks at much larger sample sizes;
/// these are the fast versions that belong next to the code.
struct MancalaAITests {

    // MARK: - Rules

    /// `MancalaOptimalSolver` keeps its own copy of the rules for speed. If the
    /// two ever drift the search is optimising a different game than the one
    /// being played, and nothing else in the suite would notice.
    @Test func solverRulesMatchMancalaGame() {
        var rng = SplitMix64(seed: 99)
        var checked = 0

        for trial in 0..<2_000 {
            var game = MancalaGame()
            let openingPlies = trial % 30

            for _ in 0..<openingPlies {
                let legal = game.legalPits(for: game.currentPlayer)
                guard let index = rng.nextIndex(below: legal.count) else { break }
                game.playPit(at: legal[index])
            }

            guard !game.isGameOver else { continue }
            let mover = game.currentPlayer
            let legal = game.legalPits(for: mover)
            guard let index = rng.nextIndex(below: legal.count) else { continue }
            let move = legal[index]

            var expected = game
            expected.playPit(at: move)

            let actual = MancalaOptimalSolver.applyMove(
                pits: game.pits,
                currentPlayer: mover == .playerOne ? 1 : 2,
                move: move
            )

            checked += 1
            #expect(actual.pits == expected.pits)
            #expect(actual.currentPlayer == (expected.currentPlayer == .playerOne ? 1 : 2))
        }

        #expect(checked > 500)
    }

    // MARK: - Solver

    /// A store holding more than half the stones has already won. The search
    /// should recognise that outright rather than groping for a heuristic score.
    @Test func solverProvesAlreadyDecidedPosition() {
        // Player two holds 25 of 48 stones, so the rest cannot change the result.
        let pits = [1, 1, 1, 1, 1, 1, 15, 1, 0, 0, 0, 0, 1, 25]

        let outcome = MancalaOptimalSolver.search(
            pits: pits,
            currentPlayer: 2,
            options: MancalaOptimalSolver.Options(maxPositions: 200_000)
        )

        #expect(outcome.proven)
        #expect(outcome.score > 0)
    }

    /// The bug this guards against: a depth-limited heuristic score used to be
    /// stored with an `.exact` transposition bound and then read back as if the
    /// position had been solved, which stopped iterative deepening early.
    @Test func solverDoesNotClaimProofFromAShallowSearch() {
        let outcome = MancalaOptimalSolver.search(
            pits: MancalaGame().pits,
            currentPlayer: 1,
            options: MancalaOptimalSolver.Options(maxPositions: 5_000, depthLimit: 2)
        )

        #expect(outcome.bestMove != nil)
        #expect(!outcome.proven)
    }

    /// With few enough stones left the search solves to terminal, so it must
    /// pick a move that is optimal against an exhaustive minimax.
    @Test func solverPlaysEndgamesOptimally() {
        var rng = SplitMix64(seed: 5)
        var considered = 0

        for _ in 0..<20 {
            let game = Self.randomEndgame(stones: 6, rng: &rng)
            let mover = game.currentPlayer
            let legal = game.legalPits(for: mover)
            guard legal.count > 1 else { continue }

            var memo: [EndgameKey: Int] = [:]
            var values: [Int: Int] = [:]
            for move in legal {
                var next = game
                next.playPit(at: move)
                let margin = Self.exactMargin(next, memo: &memo)
                values[move] = mover == .playerOne ? margin : -margin
            }

            guard let best = values.values.max() else { continue }

            var moveRNG = SplitMix64(seed: rng.next())
            let chosen = AIMoveSelector.selectPit(
                in: game,
                for: mover,
                difficulty: .impossible,
                optionsOverride: MancalaOptimalSolver.Options(maxPositions: 2_000_000),
                rng: &moveRNG
            )

            guard let chosen else { continue }
            considered += 1
            #expect(values[chosen] == best)
        }

        #expect(considered > 5)
    }

    // MARK: - Difficulty ladder

    /// Impossible must never throw a game away on purpose.
    @Test func impossibleNeverDeviatesFromItsBestMove() {
        let game = MancalaGame(currentPlayer: .playerTwo)
        var moves: Set<Int> = []

        for seed in 0..<8 {
            var rng = SplitMix64(seed: UInt64(seed))
            let move = AIMoveSelector.selectPit(
                in: game,
                for: .playerTwo,
                difficulty: .impossible,
                optionsOverride: MancalaOptimalSolver.Options(maxPositions: 50_000, depthLimit: 4),
                rng: &rng
            )
            if let move { moves.insert(move) }
        }

        #expect(moves.count == 1)
    }

    /// Easy used to be fully deterministic, so one memorised line beat it every
    /// time. It should now vary.
    @Test func easyVariesItsPlay() {
        let game = MancalaGame(currentPlayer: .playerTwo)
        var moves: Set<Int> = []

        for seed in 0..<60 {
            var rng = SplitMix64(seed: UInt64(seed) &* 2_654_435_761)
            if let move = AIMoveSelector.selectPit(in: game, for: .playerTwo, difficulty: .easy, rng: &rng) {
                moves.insert(move)
            }
        }

        #expect(moves.count > 1)
    }

    /// Varying is only useful if it is still reproducible, otherwise the harness
    /// could not compare two runs.
    @Test func selectionIsReproducibleForAGivenSeed() {
        let game = MancalaGame(currentPlayer: .playerTwo)

        func sequence() -> [Int] {
            var rng = SplitMix64(seed: 1_234)
            var picks: [Int] = []
            for _ in 0..<25 {
                if let move = AIMoveSelector.selectPit(in: game, for: .playerTwo, difficulty: .easy, rng: &rng) {
                    picks.append(move)
                }
            }
            return picks
        }

        #expect(sequence() == sequence())
    }

    @Test func everyDifficultyReturnsALegalMove() {
        var rng = SplitMix64(seed: 11)

        for difficulty in AIDifficulty.allCases {
            let game = Self.randomEndgame(stones: 10, rng: &rng)
            let mover = game.currentPlayer
            let legal = game.legalPits(for: mover)

            var moveRNG = SplitMix64(seed: 7)
            let move = AIMoveSelector.selectPit(
                in: game,
                for: mover,
                difficulty: difficulty,
                optionsOverride: MancalaOptimalSolver.Options(maxPositions: 20_000),
                rng: &moveRNG
            )

            #expect(move != nil)
            #expect(legal.contains(move ?? -1))
        }
    }

    // MARK: - Helpers

    struct EndgameKey: Hashable {
        let pits: [Int]
        let playerOneToMove: Bool
    }

    /// Exhaustive minimax over `MancalaGame`, deliberately independent of the
    /// solver so it can serve as ground truth for it.
    static func exactMargin(_ game: MancalaGame, memo: inout [EndgameKey: Int]) -> Int {
        if game.isGameOver {
            return game.storeCount(for: .playerOne) - game.storeCount(for: .playerTwo)
        }

        let mover = game.currentPlayer
        let moves = game.legalPits(for: mover)
        guard !moves.isEmpty else {
            let one = game.storeCount(for: .playerOne) + (0...5).reduce(0) { $0 + game.pits[$1] }
            let two = game.storeCount(for: .playerTwo) + (7...12).reduce(0) { $0 + game.pits[$1] }
            return one - two
        }

        let key = EndgameKey(pits: game.pits, playerOneToMove: mover == .playerOne)
        if let cached = memo[key] { return cached }

        var best: Int?
        for move in moves {
            var next = game
            next.playPit(at: move)
            let value = exactMargin(next, memo: &memo)
            if let current = best {
                best = mover == .playerOne ? max(current, value) : min(current, value)
            } else {
                best = value
            }
        }

        let result = best ?? 0
        memo[key] = result
        return result
    }

    static func randomEndgame(stones: Int, rng: inout SplitMix64) -> MancalaGame {
        let playable = Array(0...5) + Array(7...12)

        while true {
            var pits = [Int](repeating: 0, count: 14)
            for _ in 0..<stones {
                guard let slot = rng.nextIndex(below: playable.count) else { continue }
                pits[playable[slot]] += 1
            }

            let one = (0...5).reduce(0) { $0 + pits[$1] }
            let two = (7...12).reduce(0) { $0 + pits[$1] }
            guard one > 0, two > 0 else { continue }

            let banked = 48 - stones
            pits[6] = banked / 2
            pits[13] = banked - pits[6]

            let mover: Player = (rng.nextIndex(below: 2) ?? 0) == 0 ? .playerOne : .playerTwo
            return MancalaGame(pits: pits, currentPlayer: mover)
        }
    }
}
