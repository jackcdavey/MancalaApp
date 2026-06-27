import Foundation

struct MancalaOptimalSolver {
    struct SearchProgress: Sendable {
        let searched: Int
        let maximum: Int
        let elapsed: TimeInterval
        let timeLimit: TimeInterval?
        let completedDepth: Int
        let cacheEntries: Int
        let bestMove: Int?
        let isExact: Bool
    }

    private struct SearchStats {
        var nodes = 0
        var cacheHits = 0
        var lastReportedNodeCount = 0
        var reachedLimit = false
        var reachedTimeLimit = false
        var completedDepth = 0
        var bestMove: Int?
        var exact = false

        nonisolated init() {}
    }

    private struct State {
        var pits: [Int]
        var currentPlayer: Int

        nonisolated init(pits: [Int], currentPlayer: Int) {
            self.pits = pits
            self.currentPlayer = currentPlayer
        }
    }

    private struct SearchResult {
        var score: Int
        var move: Int?
        var exact: Bool
    }

    private struct TranspositionEntry {
        enum Bound {
            case exact
            case lower
            case upper
        }

        let depth: Int
        let score: Int
        let move: Int?
        let bound: Bound
    }

    private enum SearchAbort: Error {
        case cancelled
        case budgetReached
    }

    nonisolated private static let winScore = 10_000
    nonisolated private static let exactEndgameStoneThreshold = 16
    nonisolated private static let maximumSearchDepth = 80

    nonisolated static func bestMove(
        pits: [Int],
        currentPlayer: Int,
        maxPositions: Int,
        timeLimit: TimeInterval?,
        progress: @escaping @Sendable (String) -> Void,
        progressUpdate: @escaping @Sendable (SearchProgress) -> Void
    ) -> Int? {
        var table: [[Int]: TranspositionEntry] = [:]
        var stats = SearchStats()
        let state = State(pits: pits, currentPlayer: currentPlayer)
        let maxPositions = max(1, maxPositions)
        let tableLimit = min(max(20_000, maxPositions / 4), 1_000_000)
        let timeLimit = timeLimit.map { max(0.1, $0) }
        let startTime = Date()
        let rootMoves = orderedMoves(for: state, preferredMove: nil)
        var bestMove = rootMoves.first
        var bestScore = Int.min
        var exact = false

        progress("Legal first moves to analyze: \(rootMoves.count).")
        progress("Using iterative deepening with alpha-beta pruning and ordered moves.")
        if let timeLimit {
            progress("Budget: \(Int(timeLimit))s, with safety cap \(maxPositions.formatted()) positions.")
        } else {
            progress("Budget: \(maxPositions.formatted()) positions.")
        }

        if rootMoves.isEmpty {
            return nil
        }

        let depthLimit = nonStoreStoneCount(state.pits) <= exactEndgameStoneThreshold ? maximumSearchDepth : budgetDepthLimit(maxPositions: maxPositions, timeLimit: timeLimit)

        for depth in 1...depthLimit {
            do {
                let result = try rootSearch(
                    state,
                    depth: depth,
                    preferredMove: bestMove,
                    table: &table,
                    tableLimit: tableLimit,
                    stats: &stats,
                    maxPositions: maxPositions,
                    startTime: startTime,
                    timeLimit: timeLimit,
                    progress: progress,
                    progressUpdate: progressUpdate
                )
                bestMove = result.move ?? bestMove
                bestScore = result.score
                exact = result.exact
                stats.completedDepth = depth
                stats.bestMove = bestMove
                stats.exact = exact

                progressUpdate(currentProgress(stats: stats, maximum: maxPositions, startTime: startTime, timeLimit: timeLimit, cacheEntries: table.count))
                progress("Depth \(depth) complete: best pit \(bestMove.map(String.init) ?? "--"), score \(bestScore), cached \(table.count).")

                if exact {
                    progress("Exact result found after \(stats.nodes.formatted()) positions.")
                    break
                }
            } catch SearchAbort.cancelled {
                progress("Search cancelled after \(stats.nodes.formatted()) positions.")
                return nil
            } catch SearchAbort.budgetReached {
                break
            } catch {
                break
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        progressUpdate(currentProgress(stats: stats, maximum: maxPositions, startTime: startTime, timeLimit: timeLimit, cacheEntries: table.count))

        if stats.reachedTimeLimit {
            progress("Time budget reached after \(elapsed.formatted(.number.precision(.fractionLength(1))))s; using depth \(stats.completedDepth) result.")
        } else if stats.reachedLimit {
            progress("Position budget reached at \(stats.nodes.formatted()) nodes; using depth \(stats.completedDepth) result.")
        } else if !exact {
            progress("Search stopped at depth \(stats.completedDepth); using best completed result.")
        }

        return bestMove
    }

    nonisolated private static func rootSearch(
        _ state: State,
        depth: Int,
        preferredMove: Int?,
        table: inout [[Int]: TranspositionEntry],
        tableLimit: Int,
        stats: inout SearchStats,
        maxPositions: Int,
        startTime: Date,
        timeLimit: TimeInterval?,
        progress: @escaping @Sendable (String) -> Void,
        progressUpdate: @escaping @Sendable (SearchProgress) -> Void
    ) throws -> SearchResult {
        let moves = orderedMoves(for: state, preferredMove: preferredMove)
        let searchDepth = nonStoreStoneCount(state.pits) <= exactEndgameStoneThreshold ? maximumSearchDepth : depth
        var bestMove: Int?
        var bestScore = state.currentPlayer == 2 ? Int.min : Int.max
        var alpha = Int.min + 1
        var beta = Int.max - 1
        var allExact = true

        for move in moves {
            try checkBudget(stats: &stats, maxPositions: maxPositions, startTime: startTime, timeLimit: timeLimit)
            let nextState = play(move, in: state)
            let result = try alphaBeta(
                nextState,
                depth: searchDepth - 1,
                alpha: alpha,
                beta: beta,
                table: &table,
                tableLimit: tableLimit,
                stats: &stats,
                maxPositions: maxPositions,
                startTime: startTime,
                timeLimit: timeLimit,
                progress: progress,
                progressUpdate: progressUpdate
            )
            allExact = allExact && result.exact

            if state.currentPlayer == 2 {
                if result.score > bestScore {
                    bestScore = result.score
                    bestMove = move
                }
                alpha = max(alpha, bestScore)
            } else {
                if result.score < bestScore {
                    bestScore = result.score
                    bestMove = move
                }
                beta = min(beta, bestScore)
            }
        }

        return SearchResult(score: bestScore, move: bestMove, exact: allExact)
    }

    nonisolated private static func alphaBeta(
        _ state: State,
        depth: Int,
        alpha: Int,
        beta: Int,
        table: inout [[Int]: TranspositionEntry],
        tableLimit: Int,
        stats: inout SearchStats,
        maxPositions: Int,
        startTime: Date,
        timeLimit: TimeInterval?,
        progress: @escaping @Sendable (String) -> Void,
        progressUpdate: @escaping @Sendable (SearchProgress) -> Void
    ) throws -> SearchResult {
        try checkBudget(stats: &stats, maxPositions: maxPositions, startTime: startTime, timeLimit: timeLimit)
        reportProgressIfNeeded(stats: &stats, maximum: maxPositions, startTime: startTime, timeLimit: timeLimit, cacheEntries: table.count, progress: progress, progressUpdate: progressUpdate)

        if isGameOver(state.pits) {
            return SearchResult(score: terminalScore(state.pits), move: nil, exact: true)
        }

        if depth <= 0 {
            return SearchResult(score: evaluate(state.pits), move: nil, exact: false)
        }

        let originalAlpha = alpha
        let originalBeta = beta
        var alpha = alpha
        var beta = beta
        let cacheKey = cacheKey(for: state)

        if let cached = table[cacheKey], cached.depth >= depth {
            stats.cacheHits += 1
            switch cached.bound {
            case .exact:
                return SearchResult(score: cached.score, move: cached.move, exact: true)
            case .lower:
                alpha = max(alpha, cached.score)
            case .upper:
                beta = min(beta, cached.score)
            }

            if alpha >= beta {
                let cachedExact: Bool
                switch cached.bound {
                case .exact:
                    cachedExact = true
                case .lower, .upper:
                    cachedExact = false
                }
                return SearchResult(score: cached.score, move: cached.move, exact: cachedExact)
            }
        }

        let cachedMove = table[cacheKey]?.move
        let moves = orderedMoves(for: state, preferredMove: cachedMove)
        guard !moves.isEmpty else {
            return SearchResult(score: terminalScore(state.pits), move: nil, exact: true)
        }

        var bestMove: Int?
        var bestScore = state.currentPlayer == 2 ? Int.min : Int.max
        var allExact = true
        var prunedBranch = false

        for move in moves {
            let nextState = play(move, in: state)
            let child = try alphaBeta(
                nextState,
                depth: depth - 1,
                alpha: alpha,
                beta: beta,
                table: &table,
                tableLimit: tableLimit,
                stats: &stats,
                maxPositions: maxPositions,
                startTime: startTime,
                timeLimit: timeLimit,
                progress: progress,
                progressUpdate: progressUpdate
            )
            allExact = allExact && child.exact

            if state.currentPlayer == 2 {
                if child.score > bestScore {
                    bestScore = child.score
                    bestMove = move
                }
                alpha = max(alpha, bestScore)
            } else {
                if child.score < bestScore {
                    bestScore = child.score
                    bestMove = move
                }
                beta = min(beta, bestScore)
            }

            if alpha >= beta {
                prunedBranch = true
                break
            }
        }

        let isExactResult = allExact && !prunedBranch
        let bound: TranspositionEntry.Bound
        if isExactResult {
            bound = .exact
        } else if bestScore <= originalAlpha {
            bound = .upper
        } else if bestScore >= originalBeta {
            bound = .lower
        } else {
            bound = .exact
        }

        if table.count < tableLimit || depth >= (table[cacheKey]?.depth ?? -1) {
            table[cacheKey] = TranspositionEntry(depth: depth, score: bestScore, move: bestMove, bound: bound)
        }

        return SearchResult(score: bestScore, move: bestMove, exact: isExactResult)
    }

    nonisolated private static func checkBudget(
        stats: inout SearchStats,
        maxPositions: Int,
        startTime: Date,
        timeLimit: TimeInterval?
    ) throws {
        if Task.isCancelled {
            throw SearchAbort.cancelled
        }

        if stats.nodes >= maxPositions {
            stats.reachedLimit = true
            throw SearchAbort.budgetReached
        }

        stats.nodes += 1

        if let timeLimit, stats.nodes == 1 || stats.nodes.isMultiple(of: 2_048) {
            if Date().timeIntervalSince(startTime) >= timeLimit {
                stats.reachedTimeLimit = true
                throw SearchAbort.budgetReached
            }
        }
    }

    nonisolated private static func reportProgressIfNeeded(
        stats: inout SearchStats,
        maximum: Int,
        startTime: Date,
        timeLimit: TimeInterval?,
        cacheEntries: Int,
        progress: @escaping @Sendable (String) -> Void,
        progressUpdate: @escaping @Sendable (SearchProgress) -> Void
    ) {
        guard stats.nodes - stats.lastReportedNodeCount >= 25_000 else { return }
        stats.lastReportedNodeCount = stats.nodes
        progress("Depth \(stats.completedDepth + 1): searched \(stats.nodes.formatted()) nodes, cached \(cacheEntries.formatted()), hits \(stats.cacheHits.formatted()).")
        progressUpdate(currentProgress(stats: stats, maximum: maximum, startTime: startTime, timeLimit: timeLimit, cacheEntries: cacheEntries))
    }

    nonisolated private static func currentProgress(
        stats: SearchStats,
        maximum: Int,
        startTime: Date,
        timeLimit: TimeInterval?,
        cacheEntries: Int
    ) -> SearchProgress {
        SearchProgress(
            searched: stats.nodes,
            maximum: maximum,
            elapsed: Date().timeIntervalSince(startTime),
            timeLimit: timeLimit,
            completedDepth: stats.completedDepth,
            cacheEntries: cacheEntries,
            bestMove: stats.bestMove,
            isExact: stats.exact
        )
    }

    nonisolated private static func budgetDepthLimit(maxPositions: Int, timeLimit: TimeInterval?) -> Int {
        if let timeLimit {
            switch timeLimit {
            case ..<3:
                return 7
            case ..<8:
                return 9
            case ..<20:
                return 11
            default:
                return 13
            }
        }

        switch maxPositions {
        case ..<250_000:
            return 7
        case ..<1_000_000:
            return 9
        case ..<10_000_000:
            return 11
        default:
            return 13
        }
    }

    nonisolated private static func orderedMoves(for state: State, preferredMove: Int?) -> [Int] {
        legalMoves(for: state.currentPlayer, pits: state.pits)
            .sorted { left, right in
                if left == preferredMove { return true }
                if right == preferredMove { return false }
                let leftScore = moveOrderingScore(left, in: state)
                let rightScore = moveOrderingScore(right, in: state)
                return state.currentPlayer == 2 ? leftScore > rightScore : leftScore < rightScore
            }
    }

    nonisolated private static func moveOrderingScore(_ move: Int, in state: State) -> Int {
        let beforeStore = state.pits[storeIndex(for: state.currentPlayer)]
        let nextState = play(move, in: state)
        let afterStore = nextState.pits[storeIndex(for: state.currentPlayer)]
        let extraTurnBonus = nextState.currentPlayer == state.currentPlayer && !isGameOver(nextState.pits) ? 500 : 0
        let storeGain = (afterStore - beforeStore) * 30
        let evaluation = evaluate(nextState.pits)
        return extraTurnBonus + storeGain + evaluation
    }

    nonisolated private static func evaluate(_ pits: [Int]) -> Int {
        let playerOneSide = playablePits(for: 1).reduce(0) { $0 + pits[$1] }
        let playerTwoSide = playablePits(for: 2).reduce(0) { $0 + pits[$1] }
        let mobility = legalMoves(for: 2, pits: pits).count - legalMoves(for: 1, pits: pits).count
        return ((pits[13] - pits[6]) * 120) + ((playerTwoSide - playerOneSide) * 8) + (mobility * 3)
    }

    nonisolated private static func terminalScore(_ pits: [Int]) -> Int {
        let difference = pits[13] - pits[6]
        if difference > 0 {
            return winScore + difference
        }
        if difference < 0 {
            return -winScore + difference
        }
        return 0
    }

    nonisolated private static func play(_ selectedIndex: Int, in state: State) -> State {
        var pits = state.pits
        let currentPlayer = state.currentPlayer
        let opponentStore = storeIndex(for: opponent(of: currentPlayer))
        let ownStore = storeIndex(for: currentPlayer)
        var stones = pits[selectedIndex]
        pits[selectedIndex] = 0
        var index = selectedIndex

        while stones > 0 {
            index = (index + 1) % pits.count
            if index == opponentStore {
                continue
            }

            pits[index] += 1
            stones -= 1
        }

        let ownPits = playablePits(for: currentPlayer)
        if ownPits.contains(index), pits[index] == 1 {
            let oppositeIndex = 12 - index
            let capturedStones = pits[oppositeIndex]
            if capturedStones > 0 {
                pits[oppositeIndex] = 0
                pits[index] = 0
                pits[ownStore] += capturedStones + 1
            }
        }

        if sideIsEmpty(1, pits: pits) || sideIsEmpty(2, pits: pits) {
            collectRemainingStones(in: &pits)
            return State(pits: pits, currentPlayer: currentPlayer)
        }

        let nextPlayer = index == ownStore ? currentPlayer : opponent(of: currentPlayer)
        return State(pits: pits, currentPlayer: nextPlayer)
    }

    nonisolated private static func legalMoves(for player: Int, pits: [Int]) -> [Int] {
        playablePits(for: player).filter { pits[$0] > 0 }
    }

    nonisolated private static func playablePits(for player: Int) -> [Int] {
        switch player {
        case 1: Array(0...5)
        default: Array(7...12)
        }
    }

    nonisolated private static func storeIndex(for player: Int) -> Int {
        switch player {
        case 1: 6
        default: 13
        }
    }

    nonisolated private static func isGameOver(_ pits: [Int]) -> Bool {
        sideIsEmpty(1, pits: pits) || sideIsEmpty(2, pits: pits)
    }

    nonisolated private static func sideIsEmpty(_ player: Int, pits: [Int]) -> Bool {
        playablePits(for: player).allSatisfy { pits[$0] == 0 }
    }

    nonisolated private static func nonStoreStoneCount(_ pits: [Int]) -> Int {
        playablePits(for: 1).reduce(0) { $0 + pits[$1] } + playablePits(for: 2).reduce(0) { $0 + pits[$1] }
    }

    nonisolated private static func cacheKey(for state: State) -> [Int] {
        state.pits + [state.currentPlayer]
    }

    nonisolated private static func collectRemainingStones(in pits: inout [Int]) {
        for player in [1, 2] {
            let remaining = playablePits(for: player).reduce(0) { $0 + pits[$1] }
            pits[storeIndex(for: player)] += remaining
            for index in playablePits(for: player) {
                pits[index] = 0
            }
        }
    }

    nonisolated private static func opponent(of player: Int) -> Int {
        player == 1 ? 2 : 1
    }
}
