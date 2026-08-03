import Foundation

/// Iterative-deepening alpha-beta search over Kalah(6,4).
///
/// Board layout matches `MancalaGame`: indices 0–5 are player one's pits, 6
/// their store, 7–12 player two's pits, 13 player two's store. All internal
/// scores are **player-two-positive**, so the root maximises when player two is
/// to move and minimises when player one is.
///
/// Two things about this search are easy to get wrong and are called out here
/// because both were bugs at one point:
///
/// * `depth` counts **turns, not sows**. A move that lands in your own store
///   keeps the turn, so it does not consume depth (up to an extension budget).
///   Counting sows instead lets the horizon fall in the middle of an extra-turn
///   chain, which badly overrates whoever happens to be sowing at the cut-off.
/// * A transposition entry's `.exact` *bound* means "exact for the depth it was
///   searched to", which is **not** the same as "this is the true value of the
///   position". Only `proven` means the latter, and only `proven` may stop
///   iterative deepening early.
struct MancalaOptimalSolver {

    // MARK: - Public surface

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

    /// One legal move and its score **from the moving player's point of view**,
    /// so callers can rank moves without knowing the internal sign convention.
    struct RankedMove: Sendable {
        let move: Int
        let score: Int
    }

    struct Options: Sendable {
        var maxPositions: Int
        var timeLimit: TimeInterval?
        /// Iterative-deepening cap in turns. `nil` derives one from the budget.
        var depthLimit: Int?
        /// Search to terminal once this many or fewer stones sit outside the stores.
        var exactEndgameStoneThreshold: Int

        init(
            maxPositions: Int = 10_000_000,
            timeLimit: TimeInterval? = nil,
            depthLimit: Int? = nil,
            exactEndgameStoneThreshold: Int = MancalaOptimalSolver.defaultEndgameStoneThreshold
        ) {
            self.maxPositions = maxPositions
            self.timeLimit = timeLimit
            self.depthLimit = depthLimit
            self.exactEndgameStoneThreshold = exactEndgameStoneThreshold
        }
    }

    struct Outcome: Sendable {
        /// Best first, from the moving player's point of view.
        let rankedMoves: [RankedMove]
        /// The position's value, also from the moving player's point of view.
        let score: Int
        /// True only when the returned value is the position's true game value.
        let proven: Bool
        let completedDepth: Int
        let nodes: Int

        var bestMove: Int? { rankedMoves.first?.move }
    }

    /// Applies a move with the solver's own rules engine.
    ///
    /// The solver deliberately keeps a fast private copy of the rules rather
    /// than driving `MancalaGame`. That copy is a divergence risk, so
    /// `Scripts/ai-arena.swift rules-diff` uses this hook to prove the two
    /// agree. The app does not call it.
    nonisolated static func applyMove(
        pits: [Int],
        currentPlayer: Int,
        move: Int
    ) -> (pits: [Int], currentPlayer: Int) {
        let next = play(move, in: State(pits: pits, currentPlayer: currentPlayer))
        return (next.pits, next.currentPlayer)
    }

    nonisolated static let defaultEndgameStoneThreshold = 18

    nonisolated private static let winScore = 100_000
    nonisolated private static let infinity = 1_000_000
    nonisolated private static let maximumSearchDepth = 96
    nonisolated private static let aspirationWindow = 80

    /// Convenience entry point kept for existing callers and tests.
    nonisolated static func bestMove(
        pits: [Int],
        currentPlayer: Int,
        maxPositions: Int,
        timeLimit: TimeInterval?,
        progress: @escaping @Sendable (String) -> Void,
        progressUpdate: @escaping @Sendable (SearchProgress) -> Void
    ) -> Int? {
        search(
            pits: pits,
            currentPlayer: currentPlayer,
            options: Options(maxPositions: maxPositions, timeLimit: timeLimit),
            progress: progress,
            progressUpdate: progressUpdate
        ).bestMove
    }

    nonisolated static func search(
        pits: [Int],
        currentPlayer: Int,
        options: Options,
        progress: @escaping @Sendable (String) -> Void = { _ in },
        progressUpdate: @escaping @Sendable (SearchProgress) -> Void = { _ in }
    ) -> Outcome {
        let state = State(pits: pits, currentPlayer: currentPlayer)
        let rootMoves = legalMoves(for: currentPlayer, pits: pits)

        guard !rootMoves.isEmpty else {
            let value = terminalScore(pits, ply: 0)
            return Outcome(
                rankedMoves: [],
                score: currentPlayer == 2 ? value : -value,
                proven: true,
                completedDepth: 0,
                nodes: 0
            )
        }

        let context = SearchContext(options: options, pits: pits, progress: progress, progressUpdate: progressUpdate)

        progress("Legal first moves to analyze: \(rootMoves.count).")
        progress("Iterative deepening with alpha-beta, extra-turn extensions and exact endgame solving.")
        if let timeLimit = context.timeLimit {
            progress("Budget: \(Int(timeLimit))s, with safety cap \(context.maxPositions) positions.")
        } else {
            progress("Budget: \(context.maxPositions) positions.")
        }

        let depthLimit = options.depthLimit
            ?? budgetDepthLimit(maxPositions: context.maxPositions, timeLimit: context.timeLimit)

        var ranked = rootMoves.map { RankedMove(move: $0, score: 0) }
        var proven = false
        var previousScore: Int?

        for depth in 1...max(1, depthLimit) {
            do {
                let result = try rootSearch(state, depth: depth, previousScore: previousScore, context: context)
                ranked = result.ranked
                proven = result.proven
                previousScore = result.score
                context.completedDepth = depth
                context.bestMove = result.ranked.first?.move
                context.proven = proven

                context.emitProgressUpdate()
                progress("Depth \(depth) complete: best pit \(result.ranked.first.map { String($0.move) } ?? "--"), score \(result.score), cached \(context.table.count).")

                if proven {
                    progress("Proved the outcome after \(context.nodes) positions.")
                    break
                }
            } catch SearchAbort.cancelled {
                progress("Search cancelled after \(context.nodes) positions.")
                return Outcome(
                    rankedMoves: [],
                    score: 0,
                    proven: false,
                    completedDepth: context.completedDepth,
                    nodes: context.nodes
                )
            } catch {
                break
            }
        }

        context.emitProgressUpdate()

        let elapsed = Date().timeIntervalSince(context.startTime)
        if context.reachedTimeLimit {
            progress("Time budget reached after \(String(format: "%.1f", elapsed))s; using depth \(context.completedDepth) result.")
        } else if context.reachedLimit {
            progress("Position budget reached at \(context.nodes) nodes; using depth \(context.completedDepth) result.")
        } else if !proven {
            progress("Search stopped at depth \(context.completedDepth); using best completed result.")
        }

        let rootScore = previousScore ?? 0
        return Outcome(
            rankedMoves: ranked,
            score: currentPlayer == 2 ? rootScore : -rootScore,
            proven: proven,
            completedDepth: context.completedDepth,
            nodes: context.nodes
        )
    }

    // MARK: - Internal types

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
        /// True only when the score came entirely from terminal or already-decided
        /// positions — never from a depth-limited heuristic evaluation.
        var proven: Bool
    }

    private struct RootResult {
        var ranked: [RankedMove]
        var score: Int
        var proven: Bool
    }

    /// A packed board key. Hashing a 15-element `[Int]` at every node was a
    /// meaningful share of search time; this is two words and no allocation.
    private struct TTKey: Hashable {
        let low: UInt64
        let high: UInt64
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
        let proven: Bool
    }

    private enum SearchAbort: Error {
        case cancelled
        case budgetReached
    }

    private final class SearchContext {
        var table: [TTKey: TranspositionEntry] = [:]
        let tableLimit: Int
        let maxPositions: Int
        let timeLimit: TimeInterval?
        let startTime = Date()
        let endgameThreshold: Int
        let totalStones: Int

        var nodes = 0
        var cacheHits = 0
        var lastReportedNodeCount = 0
        var reachedLimit = false
        var reachedTimeLimit = false
        var completedDepth = 0
        var bestMove: Int?
        var proven = false

        /// Two killer slots per ply, plus a per-player move history score.
        var killers: [Int]
        var history: [Int]

        let progress: (String) -> Void
        let progressUpdate: (SearchProgress) -> Void

        init(
            options: Options,
            pits: [Int],
            progress: @escaping (String) -> Void,
            progressUpdate: @escaping (SearchProgress) -> Void
        ) {
            maxPositions = max(1, options.maxPositions)
            timeLimit = options.timeLimit.map { max(0.05, $0) }
            endgameThreshold = max(0, options.exactEndgameStoneThreshold)
            totalStones = pits.reduce(0, +)
            tableLimit = min(max(50_000, maxPositions / 3), 4_000_000)
            killers = [Int](repeating: -1, count: (MancalaOptimalSolver.maximumSearchDepth + 2) * 2)
            history = [Int](repeating: 0, count: 28)
            self.progress = progress
            self.progressUpdate = progressUpdate
        }

        func isKiller(_ move: Int, ply: Int) -> Bool {
            guard ply >= 0, ply <= MancalaOptimalSolver.maximumSearchDepth else { return false }
            return killers[ply * 2] == move || killers[ply * 2 + 1] == move
        }

        func recordKiller(_ move: Int, ply: Int) {
            guard ply >= 0, ply <= MancalaOptimalSolver.maximumSearchDepth else { return }
            let slot = ply * 2
            guard killers[slot] != move else { return }
            killers[slot + 1] = killers[slot]
            killers[slot] = move
        }

        func historyScore(_ move: Int, player: Int) -> Int {
            min(history[(player - 1) * 14 + move], 4_000)
        }

        func recordHistory(_ move: Int, player: Int, depth: Int) {
            history[(player - 1) * 14 + move] += depth * depth
        }

        func emitProgressUpdate() {
            progressUpdate(
                SearchProgress(
                    searched: nodes,
                    maximum: maxPositions,
                    elapsed: Date().timeIntervalSince(startTime),
                    timeLimit: timeLimit,
                    completedDepth: completedDepth,
                    cacheEntries: table.count,
                    bestMove: bestMove,
                    isExact: proven
                )
            )
        }
    }

    // MARK: - Root

    nonisolated private static func rootSearch(
        _ state: State,
        depth: Int,
        previousScore: Int?,
        context: SearchContext
    ) throws -> RootResult {
        // Try a narrow window around the last iteration's score first; fall back
        // to full width if the true score escapes it.
        if depth >= 3, let previousScore {
            let alpha = previousScore - aspirationWindow
            let beta = previousScore + aspirationWindow
            let attempt = try rootSearch(state, depth: depth, alpha: alpha, beta: beta, context: context)
            if attempt.score > alpha && attempt.score < beta {
                return attempt
            }
        }

        return try rootSearch(state, depth: depth, alpha: -infinity, beta: infinity, context: context)
    }

    nonisolated private static func rootSearch(
        _ state: State,
        depth: Int,
        alpha: Int,
        beta: Int,
        context: SearchContext
    ) throws -> RootResult {
        let maximizing = state.currentPlayer == 2
        let moves = orderedMoves(for: state, ttMove: context.bestMove, ply: 0, context: context)
        var alpha = alpha
        var beta = beta
        var bestScore = maximizing ? -infinity : infinity
        var proven = true
        var scored: [RankedMove] = []
        scored.reserveCapacity(moves.count)

        for move in moves {
            try checkBudget(context)
            let child = try descend(from: state, move: move, depth: depth, ply: 0, extensions: extensionBudget(for: depth), alpha: alpha, beta: beta, context: context)
            proven = proven && child.proven

            // Rank from the mover's point of view so callers need not know the
            // internal player-two-positive convention.
            scored.append(RankedMove(move: move, score: maximizing ? child.score : -child.score))

            if maximizing {
                if child.score > bestScore {
                    bestScore = child.score
                }
                alpha = max(alpha, bestScore)
            } else {
                if child.score < bestScore {
                    bestScore = child.score
                }
                beta = min(beta, bestScore)
            }
        }

        scored.sort { $0.score > $1.score }
        return RootResult(ranked: scored, score: bestScore, proven: proven)
    }

    // MARK: - Search

    /// Applies `move` and recurses, handling extra-turn extensions.
    ///
    /// A move that lands in your own store keeps the turn, so it must not
    /// consume a turn of depth — otherwise the horizon lands mid-chain.
    nonisolated private static func descend(
        from state: State,
        move: Int,
        depth: Int,
        ply: Int,
        extensions: Int,
        alpha: Int,
        beta: Int,
        context: SearchContext
    ) throws -> SearchResult {
        let next = play(move, in: state)
        let keepsTurn = next.currentPlayer == state.currentPlayer && !isGameOver(next.pits)
        let extend = keepsTurn && extensions > 0
        return try alphaBeta(
            next,
            depth: extend ? depth : depth - 1,
            ply: ply + 1,
            extensions: extend ? extensions - 1 : extensions,
            alpha: alpha,
            beta: beta,
            context: context
        )
    }

    nonisolated private static func alphaBeta(
        _ state: State,
        depth: Int,
        ply: Int,
        extensions: Int,
        alpha: Int,
        beta: Int,
        context: SearchContext
    ) throws -> SearchResult {
        try checkBudget(context)
        reportProgressIfNeeded(context)

        if isGameOver(state.pits) {
            return SearchResult(score: terminalScore(state.pits, ply: ply), move: nil, proven: true)
        }

        // Once one store holds more than half the stones the game is decided no
        // matter what follows. Cheap to test and it prunes whole subtrees.
        if let decided = decidedScore(state.pits, totalStones: context.totalStones, ply: ply) {
            return SearchResult(score: decided, move: nil, proven: true)
        }

        // Interior endgame extension: solve small positions to terminal rather
        // than cutting off with a heuristic. Bounded by ply so recursion cannot
        // run away.
        var searchDepth = depth
        if nonStoreStoneCount(state.pits) <= context.endgameThreshold {
            searchDepth = max(searchDepth, maximumSearchDepth - ply)
        }

        if searchDepth <= 0 || ply >= maximumSearchDepth {
            return SearchResult(score: evaluate(state.pits), move: nil, proven: false)
        }

        let originalAlpha = alpha
        let originalBeta = beta
        var alpha = alpha
        var beta = beta
        let key = cacheKey(for: state)
        var ttMove: Int?

        if let cached = context.table[key] {
            ttMove = cached.move
            if cached.depth >= searchDepth {
                context.cacheHits += 1
                switch cached.bound {
                case .exact:
                    // `proven` is tracked separately from the bound on purpose: a
                    // depth-limited PV score is exact for its depth but is not the
                    // position's true value, and must never stop deepening.
                    return SearchResult(score: cached.score, move: cached.move, proven: cached.proven)
                case .lower:
                    alpha = max(alpha, cached.score)
                case .upper:
                    beta = min(beta, cached.score)
                }

                if alpha >= beta {
                    return SearchResult(score: cached.score, move: cached.move, proven: cached.proven)
                }
            }
        }

        let moves = orderedMoves(for: state, ttMove: ttMove, ply: ply, context: context)
        guard !moves.isEmpty else {
            return SearchResult(score: terminalScore(state.pits, ply: ply), move: nil, proven: true)
        }

        let maximizing = state.currentPlayer == 2
        var bestScore = maximizing ? -infinity : infinity
        var bestMove: Int?
        var childrenProven = true
        var pruned = false

        for move in moves {
            let child = try descend(
                from: state,
                move: move,
                depth: searchDepth,
                ply: ply,
                extensions: extensions,
                alpha: alpha,
                beta: beta,
                context: context
            )
            childrenProven = childrenProven && child.proven

            if maximizing {
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
                pruned = true
                context.recordKiller(move, ply: ply)
                context.recordHistory(move, player: state.currentPlayer, depth: searchDepth)
                break
            }
        }

        // A cut-off leaves siblings unexamined, so the value is only a bound —
        // unless it is already a win or a loss, which the unexamined siblings
        // cannot overturn for the side that would have chosen them.
        let decisive = bestScore >= winScore || bestScore <= -winScore
        let proven = childrenProven && (!pruned || decisive)

        let bound: TranspositionEntry.Bound
        if bestScore <= originalAlpha {
            bound = .upper
        } else if bestScore >= originalBeta {
            bound = .lower
        } else {
            bound = .exact
        }

        store(
            key: key,
            entry: TranspositionEntry(depth: searchDepth, score: bestScore, move: bestMove, bound: bound, proven: proven),
            context: context
        )

        return SearchResult(score: bestScore, move: bestMove, proven: proven)
    }

    /// Depth-preferred replacement with a genuine cap.
    ///
    /// The previous policy read `depth >= (table[key]?.depth ?? -1)`, which is
    /// always true when the key is absent — so the limit never bound anything
    /// and the table grew without end.
    nonisolated private static func store(key: TTKey, entry: TranspositionEntry, context: SearchContext) {
        if let existing = context.table[key] {
            if entry.depth >= existing.depth || (entry.proven && !existing.proven) {
                context.table[key] = entry
            }
            return
        }

        guard context.table.count < context.tableLimit else { return }
        context.table[key] = entry
    }

    // MARK: - Budget

    nonisolated private static func extensionBudget(for depth: Int) -> Int {
        // Enough to follow realistic extra-turn chains without letting a deep
        // search balloon: chains longer than this are vanishingly rare.
        min(12, depth + 4)
    }

    nonisolated private static func checkBudget(_ context: SearchContext) throws {
        if Task.isCancelled {
            throw SearchAbort.cancelled
        }

        if context.nodes >= context.maxPositions {
            context.reachedLimit = true
            throw SearchAbort.budgetReached
        }

        context.nodes += 1

        if let timeLimit = context.timeLimit, context.nodes == 1 || context.nodes.isMultiple(of: 2_048) {
            if Date().timeIntervalSince(context.startTime) >= timeLimit {
                context.reachedTimeLimit = true
                throw SearchAbort.budgetReached
            }
        }
    }

    nonisolated private static func reportProgressIfNeeded(_ context: SearchContext) {
        guard context.nodes - context.lastReportedNodeCount >= 25_000 else { return }
        context.lastReportedNodeCount = context.nodes
        context.progress("Depth \(context.completedDepth + 1): searched \(context.nodes) nodes, cached \(context.table.count), hits \(context.cacheHits).")
        context.emitProgressUpdate()
    }

    nonisolated private static func budgetDepthLimit(maxPositions: Int, timeLimit: TimeInterval?) -> Int {
        // Depth counts turns, and extra turns are free, so these are deliberately
        // lower than a sow-counting search would use.
        if let timeLimit {
            switch timeLimit {
            case ..<3: return 9
            case ..<8: return 12
            case ..<20: return 15
            default: return 20
            }
        }

        switch maxPositions {
        case ..<250_000: return 9
        case ..<1_000_000: return 12
        case ..<10_000_000: return 15
        default: return 20
        }
    }

    // MARK: - Move ordering

    nonisolated private static func orderedMoves(
        for state: State,
        ttMove: Int?,
        ply: Int,
        context: SearchContext
    ) -> [Int] {
        let moves = legalMoves(for: state.currentPlayer, pits: state.pits)
        guard moves.count > 1 else { return moves }

        var scored: [(move: Int, score: Int)] = []
        scored.reserveCapacity(moves.count)

        for move in moves {
            var score = staticMoveScore(move, in: state)
            if move == ttMove {
                score += 1_000_000
            } else if context.isKiller(move, ply: ply) {
                score += 20_000
            }
            score += context.historyScore(move, player: state.currentPlayer)
            scored.append((move, score))
        }

        // Score each move once, then sort — the previous version recomputed a
        // full board copy plus evaluation inside the sort comparator.
        scored.sort { $0.score > $1.score }
        return scored.map(\.move)
    }

    /// A cheap, allocation-free ordering estimate: does the move end in our
    /// store (free turn), does it capture, and how much does it bank on the way.
    nonisolated private static func staticMoveScore(_ move: Int, in state: State) -> Int {
        let pits = state.pits
        let stones = pits[move]
        guard stones > 0 else { return 0 }

        let ownStore = storeIndex(for: state.currentPlayer)
        let opponentStore = storeIndex(for: opponent(of: state.currentPlayer))
        var index = move
        var remaining = stones
        var banked = 0

        while remaining > 0 {
            index = (index + 1) % 14
            if index == opponentStore { continue }
            if index == ownStore { banked += 1 }
            remaining -= 1
        }

        var score = banked * 60

        if index == ownStore {
            score += 900
        } else if isPlayablePit(index, for: state.currentPlayer) {
            // The starting pit is emptied first, so landing back on it counts as empty.
            let occupancy = index == move ? 0 : pits[index]
            if occupancy == 0 {
                let opposite = 12 - index
                let captured = opposite == move ? 0 : pits[opposite]
                if captured > 0 {
                    score += (captured + 1) * 45
                }
            }
        }

        return score
    }

    // MARK: - Evaluation

    /// Player-two-positive static evaluation.
    nonisolated private static func evaluate(_ pits: [Int]) -> Int {
        var score = (pits[13] - pits[6]) * 128

        var playerOneSide = 0
        var playerTwoSide = 0
        var playerOneAdvance = 0
        var playerTwoAdvance = 0

        for index in 0...5 {
            let stones = pits[index]
            playerOneSide += stones
            // Higher index sits closer to player one's store at 6.
            playerOneAdvance += stones * (index + 1)
        }

        for index in 7...12 {
            let stones = pits[index]
            playerTwoSide += stones
            // Higher index sits closer to player two's store at 13.
            playerTwoAdvance += stones * (index - 6)
        }

        score += (playerTwoSide - playerOneSide) * 10
        score += playerTwoAdvance - playerOneAdvance
        score += (freeTurnMoves(for: 2, pits: pits) - freeTurnMoves(for: 1, pits: pits)) * 22
        // Stones sitting opposite an empty pit are capture bait; player one's
        // exposure is good for player two.
        score += (captureExposure(for: 1, pits: pits) - captureExposure(for: 2, pits: pits)) * 6

        return score
    }

    /// Moves that would land exactly in the player's own store, earning a free turn.
    nonisolated private static func freeTurnMoves(for player: Int, pits: [Int]) -> Int {
        let store = storeIndex(for: player)
        let range = player == 1 ? 0...5 : 7...12
        var count = 0
        for index in range where pits[index] == store - index {
            count += 1
        }
        return count
    }

    /// Stones of `player` that sit opposite an empty pit, and so could be swept
    /// up if the opponent lands there.
    nonisolated private static func captureExposure(for player: Int, pits: [Int]) -> Int {
        let range = player == 1 ? 0...5 : 7...12
        var exposed = 0
        for index in range where pits[index] > 0 && pits[12 - index] == 0 {
            exposed += pits[index]
        }
        return exposed
    }

    /// Prefers winning sooner and losing later, which stops the engine dawdling
    /// in a won position and giving the opponent chances to climb back.
    nonisolated private static func terminalScore(_ pits: [Int], ply: Int) -> Int {
        let difference = pits[13] - pits[6]
        if difference > 0 {
            return winScore + difference * 4 - ply
        }
        if difference < 0 {
            return -winScore + difference * 4 + ply
        }
        return 0
    }

    /// A store holding more than half the stones has already won, whatever
    /// happens to the rest of the board.
    nonisolated private static func decidedScore(_ pits: [Int], totalStones: Int, ply: Int) -> Int? {
        let playerTwoLead = pits[13] * 2 - totalStones
        if playerTwoLead > 0 {
            return winScore + playerTwoLead * 4 - ply
        }

        let playerOneLead = pits[6] * 2 - totalStones
        if playerOneLead > 0 {
            return -winScore - playerOneLead * 4 + ply
        }

        return nil
    }

    // MARK: - Rules
    //
    // These mirror `MancalaGame`. `Scripts/ai-arena.swift rules-diff` exists
    // specifically to prove the two stay in agreement.

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

        if isPlayablePit(index, for: currentPlayer), pits[index] == 1 {
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
        var moves: [Int] = []
        moves.reserveCapacity(6)
        let range = player == 1 ? 0...5 : 7...12
        for index in range where pits[index] > 0 {
            moves.append(index)
        }
        return moves
    }

    nonisolated private static func isPlayablePit(_ index: Int, for player: Int) -> Bool {
        player == 1 ? (index >= 0 && index <= 5) : (index >= 7 && index <= 12)
    }

    nonisolated private static func storeIndex(for player: Int) -> Int {
        player == 1 ? 6 : 13
    }

    nonisolated private static func isGameOver(_ pits: [Int]) -> Bool {
        sideIsEmpty(1, pits: pits) || sideIsEmpty(2, pits: pits)
    }

    nonisolated private static func sideIsEmpty(_ player: Int, pits: [Int]) -> Bool {
        let range = player == 1 ? 0...5 : 7...12
        for index in range where pits[index] > 0 {
            return false
        }
        return true
    }

    nonisolated private static func nonStoreStoneCount(_ pits: [Int]) -> Int {
        var total = 0
        for index in 0...5 { total += pits[index] }
        for index in 7...12 { total += pits[index] }
        return total
    }

    nonisolated private static func cacheKey(for state: State) -> TTKey {
        var low: UInt64 = 0
        for index in 0..<8 {
            low |= UInt64(UInt8(truncatingIfNeeded: state.pits[index])) << UInt64(index * 8)
        }

        var high: UInt64 = 0
        for index in 8..<14 {
            high |= UInt64(UInt8(truncatingIfNeeded: state.pits[index])) << UInt64((index - 8) * 8)
        }
        high |= UInt64(state.currentPlayer) << 56

        return TTKey(low: low, high: high)
    }

    nonisolated private static func collectRemainingStones(in pits: inout [Int]) {
        for player in [1, 2] {
            let range = player == 1 ? 0...5 : 7...12
            var remaining = 0
            for index in range {
                remaining += pits[index]
                pits[index] = 0
            }
            pits[storeIndex(for: player)] += remaining
        }
    }

    nonisolated private static func opponent(of player: Int) -> Int {
        player == 1 ? 2 : 1
    }
}
