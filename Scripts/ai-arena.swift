// Headless AI validation harness.
//
// Plays games and probes the solver without touching the UI, so difficulty
// tuning stops being a matter of playing by hand and squinting.
//
//   swiftc -O -o /tmp/ai-arena \
//     Mancala/Models/Player.swift Mancala/Models/MancalaGame.swift \
//     Mancala/Models/AIDifficulty.swift Mancala/AI/SplitMix64.swift \
//     Mancala/AI/HeuristicAIPlayer.swift Mancala/AI/MancalaOptimalSolver.swift \
//     Mancala/AI/AIMoveSelector.swift Scripts/ai-arena.swift \
//   && /tmp/ai-arena ladder
//
// Do not include Mancala/Models/GameSettings.swift or ContentView.swift; both
// import SwiftUI.
//
// Everything is seeded, and time-based budgets are disabled by default, so two
// runs with the same flags produce identical results. That is what makes the
// `ladder` subcommand usable as a regression gate.

import Foundation

// MARK: - Argument parsing

struct Arguments {
    let subcommand: String
    private let values: [String: String]
    private let flags: Set<String>

    static let booleanFlags: Set<String> = ["swap-seats", "allow-time-limits", "verbose", "help"]

    init(_ raw: [String]) {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var subcommand = "help"
        var index = 0

        if index < raw.count, !raw[index].hasPrefix("--") {
            subcommand = raw[index]
            index += 1
        }

        while index < raw.count {
            let token = raw[index]
            guard token.hasPrefix("--") else {
                index += 1
                continue
            }

            let name = String(token.dropFirst(2))
            if Arguments.booleanFlags.contains(name) {
                flags.insert(name)
                index += 1
                continue
            }

            if index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
                values[name] = raw[index + 1]
                index += 2
            } else {
                flags.insert(name)
                index += 1
            }
        }

        self.subcommand = subcommand
        self.values = values
        self.flags = flags
    }

    func string(_ name: String, default fallback: String) -> String {
        values[name] ?? fallback
    }

    func string(_ name: String) -> String? {
        values[name]
    }

    func int(_ name: String, default fallback: Int) -> Int {
        values[name].flatMap(Int.init) ?? fallback
    }

    func double(_ name: String, default fallback: Double) -> Double {
        values[name].flatMap(Double.init) ?? fallback
    }

    func flag(_ name: String) -> Bool {
        flags.contains(name)
    }
}

// MARK: - Engine configuration

/// One side of a match: a difficulty plus any budget overrides.
///
/// Spec syntax is `<difficulty>[:key=value,...]`, for example
/// `impossible`, `impossible:positions=2000000`, `hard:depth=9`,
/// `impossible:time=5`.
struct EngineConfig {
    let label: String
    let difficulty: AIDifficulty
    let options: MancalaOptimalSolver.Options?

    static func parse(_ spec: String, budgetScale: Double, allowTimeLimits: Bool) -> EngineConfig? {
        let parts = spec.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let difficulty = AIDifficulty(rawValue: String(parts[0])) else { return nil }

        let profile = difficulty.profile
        guard profile.usesSearch else {
            // Easy is the one-ply heuristic; budgets do not apply to it.
            return EngineConfig(label: spec, difficulty: difficulty, options: nil)
        }

        var positions = profile.maxPositions
        var depth = profile.depthLimit
        var endgame = profile.exactEndgameStoneThreshold
        // Wall-clock budgets make runs unreproducible, so they are opt-in.
        var time: TimeInterval? = allowTimeLimits ? profile.timeLimit : nil
        var positionsWasExplicit = false

        if parts.count > 1, !parts[1].isEmpty {
            for setting in parts[1].split(separator: ",") {
                let pair = setting.split(separator: "=", maxSplits: 1)
                guard pair.count == 2 else { return nil }
                let key = String(pair[0])
                let value = String(pair[1])

                switch key {
                case "positions":
                    guard let parsed = Int(value) else { return nil }
                    positions = parsed
                    positionsWasExplicit = true
                case "depth":
                    guard let parsed = Int(value) else { return nil }
                    depth = parsed
                case "time":
                    guard let parsed = Double(value) else { return nil }
                    time = parsed
                case "endgame":
                    guard let parsed = Int(value) else { return nil }
                    endgame = parsed
                default:
                    return nil
                }
            }
        }

        if !positionsWasExplicit {
            positions = max(1_000, Int(Double(positions) * budgetScale))
        }

        return EngineConfig(
            label: spec,
            difficulty: difficulty,
            options: MancalaOptimalSolver.Options(
                maxPositions: positions,
                timeLimit: time,
                depthLimit: depth,
                exactEndgameStoneThreshold: endgame
            )
        )
    }
}

// MARK: - Game runner

struct GameOutcome {
    let playerOneStore: Int
    let playerTwoStore: Int
    let sows: Int
    let stalled: Bool

    var margin: Int { playerOneStore - playerTwoStore }

    var winner: Player? {
        if margin > 0 { return .playerOne }
        if margin < 0 { return .playerTwo }
        return nil
    }
}

enum Arena {
    /// Hard stop so a rules bug shows up as a reported stall rather than a hang.
    static let maximumSows = 600

    static func playGame(
        playerOne: EngineConfig,
        playerTwo: EngineConfig,
        randomPlies: Int,
        startingPlayer: Player,
        seed: UInt64
    ) -> GameOutcome {
        var game = MancalaGame(currentPlayer: startingPlayer)
        var rng = SplitMix64(seed: seed)
        var sows = 0

        while !game.isGameOver && sows < maximumSows {
            let mover = game.currentPlayer
            let legal = game.legalPits(for: mover)
            guard !legal.isEmpty else { break }

            let pit: Int
            if sows < randomPlies {
                // A seeded random opening. Without it both engines are
                // deterministic and every game in a pairing is the same game.
                pit = legal[rng.nextIndex(below: legal.count) ?? 0]
            } else {
                let config = mover == .playerOne ? playerOne : playerTwo
                pit = AIMoveSelector.selectPit(
                    in: game,
                    for: mover,
                    difficulty: config.difficulty,
                    optionsOverride: config.options,
                    rng: &rng
                ) ?? legal[0]
            }

            game.playPit(at: pit)
            sows += 1
        }

        return GameOutcome(
            playerOneStore: game.storeCount(for: .playerOne),
            playerTwoStore: game.storeCount(for: .playerTwo),
            sows: sows,
            stalled: !game.isGameOver
        )
    }
}

// MARK: - Match results

struct MatchRecord {
    var aWins = 0
    var bWins = 0
    var draws = 0
    var stalls = 0
    var margins: [Int] = []
    var sows = 0
    var elapsed: TimeInterval = 0

    var games: Int { aWins + bWins + draws }

    /// Draws count as half, so a pure win rate is comparable across pairings.
    var aScoreRate: Double {
        games == 0 ? 0 : (Double(aWins) + Double(draws) / 2) / Double(games)
    }

    var meanMargin: Double {
        margins.isEmpty ? 0 : Double(margins.reduce(0, +)) / Double(margins.count)
    }

    var medianMargin: Int {
        guard !margins.isEmpty else { return 0 }
        let sorted = margins.sorted()
        return sorted[sorted.count / 2]
    }

    var millisecondsPerSow: Double {
        sows == 0 ? 0 : elapsed * 1000 / Double(sows)
    }
}

/// Runs `games` games between two configs. With `swapSeats` each opening is
/// played twice, once from each side, which cancels out the first-player edge.
func runMatch(
    a: EngineConfig,
    b: EngineConfig,
    games: Int,
    randomPlies: Int,
    seed: UInt64,
    swapSeats: Bool
) -> MatchRecord {
    var record = MatchRecord()
    let started = Date()

    for index in 0..<games {
        // Alternate seats so neither config keeps the first move.
        let aIsPlayerOne = swapSeats ? index.isMultiple(of: 2) : true
        // Paired seats share an opening seed so the swap is a true mirror.
        let gameSeed = seed &+ UInt64(swapSeats ? index / 2 : index)

        let outcome = Arena.playGame(
            playerOne: aIsPlayerOne ? a : b,
            playerTwo: aIsPlayerOne ? b : a,
            randomPlies: randomPlies,
            startingPlayer: .playerOne,
            seed: gameSeed
        )

        if outcome.stalled {
            record.stalls += 1
        }

        let marginForA = aIsPlayerOne ? outcome.margin : -outcome.margin
        record.margins.append(marginForA)
        record.sows += outcome.sows

        if marginForA > 0 {
            record.aWins += 1
        } else if marginForA < 0 {
            record.bWins += 1
        } else {
            record.draws += 1
        }
    }

    record.elapsed = Date().timeIntervalSince(started)
    return record
}

// MARK: - Exact oracle
//
// Deliberately a separate, dumb, exhaustive minimax over `MancalaGame` rather
// than anything from `MancalaOptimalSolver`. An oracle built from the thing
// under test proves nothing.

struct OracleKey: Hashable {
    let pits: [Int]
    let playerOneToMove: Bool
}

/// Final store difference (player one minus player two) under optimal play.
func exactMargin(_ game: MancalaGame, memo: inout [OracleKey: Int]) -> Int {
    if game.isGameOver {
        return game.storeCount(for: .playerOne) - game.storeCount(for: .playerTwo)
    }

    let mover = game.currentPlayer
    let moves = game.legalPits(for: mover)
    guard !moves.isEmpty else {
        return sweptMargin(game)
    }

    let key = OracleKey(pits: game.pits, playerOneToMove: mover == .playerOne)
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

    let result = best ?? sweptMargin(game)
    memo[key] = result
    return result
}

/// Margin if every remaining stone were swept to its owner's store now.
func sweptMargin(_ game: MancalaGame) -> Int {
    let playerOne = game.storeCount(for: .playerOne) + (0...5).reduce(0) { $0 + game.pits[$1] }
    let playerTwo = game.storeCount(for: .playerTwo) + (7...12).reduce(0) { $0 + game.pits[$1] }
    return playerOne - playerTwo
}

// MARK: - Position generators

/// A random legal-looking position with `stones` left outside the stores.
func randomEndgamePosition(stones: Int, totalStones: Int, rng: inout SplitMix64) -> MancalaGame {
    // Two stones is the minimum that can leave both sides non-empty.
    let inPlay = min(max(stones, 2), totalStones)
    let playable = Array(0...5) + Array(7...12)

    while true {
        var pits = [Int](repeating: 0, count: 14)
        for _ in 0..<inPlay {
            let slot = playable[rng.nextIndex(below: playable.count) ?? 0]
            pits[slot] += 1
        }

        let playerOneSide = (0...5).reduce(0) { $0 + pits[$1] }
        let playerTwoSide = (7...12).reduce(0) { $0 + pits[$1] }
        guard playerOneSide > 0, playerTwoSide > 0 else { continue }

        // Bank the remainder so the board still totals `totalStones`, which is
        // what the solver's "more than half the stones wins" cut-off assumes.
        let banked = totalStones - inPlay
        pits[6] = banked / 2
        pits[13] = banked - pits[6]

        let mover: Player = (rng.nextIndex(below: 2) ?? 0) == 0 ? .playerOne : .playerTwo
        return MancalaGame(pits: pits, currentPlayer: mover)
    }
}

/// A midgame position reached by playing random sows from the opening.
func randomMidgamePosition(plies: Int, rng: inout SplitMix64) -> MancalaGame {
    var game = MancalaGame()
    var played = 0

    while played < plies && !game.isGameOver {
        let legal = game.legalPits(for: game.currentPlayer)
        guard !legal.isEmpty else { break }
        game.playPit(at: legal[rng.nextIndex(below: legal.count) ?? 0])
        played += 1
    }

    return game
}

// MARK: - Reference evaluation

/// The value of `game` to the side to move, according to `config`.
func referenceValue(_ game: MancalaGame, config: EngineConfig) -> Int {
    let outcome = MancalaOptimalSolver.search(
        pits: game.pits,
        currentPlayer: game.currentPlayer == .playerOne ? 1 : 2,
        options: config.options ?? MancalaOptimalSolver.Options()
    )
    return outcome.score
}

/// The value of playing `move` in `game`, to the player who plays it.
func referenceValue(of move: Int, in game: MancalaGame, config: EngineConfig) -> Int {
    let mover = game.currentPlayer
    var next = game
    next.playPit(at: move)

    if next.isGameOver {
        let margin = next.storeCount(for: mover) - next.storeCount(for: mover.opponent)
        return 100_000 + margin * 4
    }

    let value = referenceValue(next, config: config)
    // An extra turn keeps the same mover, so the sign only flips when it passes.
    return next.currentPlayer == mover ? value : -value
}

// MARK: - Formatting helpers
//
// Hand-rolled rather than String(format:) with %@, which is unreliable outside
// of Darwin Foundation and this script is meant to run on Linux too.

func oneDecimal(_ value: Double) -> String {
    String(format: "%.1f", value)
}

func twoDecimals(_ value: Double) -> String {
    String(format: "%.2f", value)
}

func percent(_ fraction: Double) -> String {
    String(format: "%.1f%%", fraction * 100)
}

func signedTwoDecimals(_ value: Double) -> String {
    (value >= 0 ? "+" : "") + twoDecimals(value)
}

func padded(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func leftPadded(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
}

// MARK: - Subcommands

let allDifficulties: [AIDifficulty] = [.easy, .medium, .hard, .impossible]

func runMatchCommand(_ args: Arguments) -> Int32 {
    let scale = args.double("budget-scale", default: 1.0)
    let allowTime = args.flag("allow-time-limits")

    guard let a = EngineConfig.parse(args.string("a", default: "hard"), budgetScale: scale, allowTimeLimits: allowTime),
          let b = EngineConfig.parse(args.string("b", default: "impossible"), budgetScale: scale, allowTimeLimits: allowTime) else {
        print("Could not parse --a/--b. Use e.g. `impossible` or `impossible:positions=2000000`.")
        return 2
    }

    let games = args.int("games", default: 40)
    let record = runMatch(
        a: a,
        b: b,
        games: games,
        randomPlies: args.int("random-plies", default: 4),
        seed: UInt64(args.int("seed", default: 42)),
        swapSeats: args.flag("swap-seats")
    )

    print("\(a.label) vs \(b.label) over \(record.games) games")
    print("  \(a.label): \(record.aWins) wins")
    print("  \(b.label): \(record.bWins) wins")
    print("  draws: \(record.draws)")
    print("  score rate for \(a.label): \(percent(record.aScoreRate))")
    print("  margin for \(a.label): mean \(twoDecimals(record.meanMargin)), median \(record.medianMargin)")
    print("  \(oneDecimal(record.millisecondsPerSow)) ms per sow, \(oneDecimal(record.elapsed))s total")
    if record.stalls > 0 {
        print("  WARNING: \(record.stalls) games hit the sow cap without finishing")
    }

    return record.stalls > 0 ? 1 : 0
}

func runLadderCommand(_ args: Arguments) -> Int32 {
    // Budgets are scaled down by default: the ladder measures relative strength,
    // and full budgets would make a round robin take hours.
    let scale = args.double("budget-scale", default: 0.05)
    let allowTime = args.flag("allow-time-limits")
    let games = args.int("games", default: 40)
    let randomPlies = args.int("random-plies", default: 4)
    let seed = UInt64(args.int("seed", default: 42))

    var configs: [AIDifficulty: EngineConfig] = [:]
    for difficulty in allDifficulties {
        guard let config = EngineConfig.parse(difficulty.rawValue, budgetScale: scale, allowTimeLimits: allowTime) else {
            print("Could not build a config for \(difficulty.rawValue).")
            return 2
        }
        configs[difficulty] = config
    }

    print("Round robin: \(games) games per pairing, budget scale \(scale), seed \(seed)")
    if !allowTime {
        print("Wall-clock budgets disabled for reproducibility (pass --allow-time-limits to include them).")
    }
    print("")

    var scoreRate: [AIDifficulty: Double] = [:]
    var played: [AIDifficulty: Int] = [:]
    var stalls = 0

    for (leftIndex, left) in allDifficulties.enumerated() {
        for right in allDifficulties[(leftIndex + 1)...] {
            let record = runMatch(
                a: configs[left]!,
                b: configs[right]!,
                games: games,
                randomPlies: randomPlies,
                seed: seed,
                swapSeats: true
            )
            stalls += record.stalls

            let scoreline = "\(record.aWins)-\(record.bWins)-\(record.draws)"
            print("\(padded(left.rawValue, 11)) vs \(padded(right.rawValue, 11))"
                + "  \(padded(scoreline, 10))"
                + "  \(leftPadded(percent(record.aScoreRate), 6)) for \(padded(left.rawValue, 11))"
                + "  mean margin \(signedTwoDecimals(record.meanMargin))"
                + ", \(oneDecimal(record.millisecondsPerSow)) ms/sow")

            scoreRate[left, default: 0] += record.aScoreRate
            scoreRate[right, default: 0] += 1 - record.aScoreRate
            played[left, default: 0] += 1
            played[right, default: 0] += 1
        }
    }

    print("")
    print("Overall score rate")
    var overall: [(difficulty: AIDifficulty, rate: Double)] = []
    for difficulty in allDifficulties {
        let rate = scoreRate[difficulty, default: 0] / Double(max(1, played[difficulty, default: 1]))
        overall.append((difficulty, rate))
        print("  \(padded(difficulty.rawValue, 11)) \(leftPadded(percent(rate), 6))")
    }

    // The gate: each tier must genuinely outscore the one below it.
    let minimumGap = args.double("minimum-gap", default: 0.03)
    var failures: [String] = []
    for index in 1..<overall.count {
        let lower = overall[index - 1]
        let higher = overall[index]
        if higher.rate < lower.rate + minimumGap {
            failures.append("\(higher.difficulty.rawValue) (\(percent(higher.rate)))"
                + " does not beat \(lower.difficulty.rawValue) (\(percent(lower.rate)))"
                + " by the required \(percent(minimumGap))")
        }
    }

    print("")
    if stalls > 0 {
        print("FAIL: \(stalls) games hit the sow cap without finishing")
    }
    if failures.isEmpty && stalls == 0 {
        print("PASS: difficulty ladder is monotone")
        return 0
    }
    for failure in failures {
        print("FAIL: \(failure)")
    }
    return 1
}

func runOracleEndgameCommand(_ args: Arguments) -> Int32 {
    let scale = args.double("budget-scale", default: 1.0)
    guard let config = EngineConfig.parse(
        args.string("cfg", default: "impossible"),
        budgetScale: scale,
        allowTimeLimits: args.flag("allow-time-limits")
    ) else {
        print("Could not parse --cfg.")
        return 2
    }

    let positions = args.int("games", default: 200)
    // Small enough for the exhaustive oracle to finish, large enough that the
    // engine has to actually search rather than stumble onto the right move.
    let stones = args.int("stones", default: 8)
    var rng = SplitMix64(seed: UInt64(args.int("seed", default: 7)))

    var agreed = 0
    var totalRegret = 0
    var worstRegret = 0
    var considered = 0

    for _ in 0..<positions {
        let game = randomEndgamePosition(stones: stones, totalStones: 48, rng: &rng)
        let mover = game.currentPlayer
        let legal = game.legalPits(for: mover)
        guard legal.count > 1 else { continue }

        var memo: [OracleKey: Int] = [:]
        var trueValue: [Int: Int] = [:]
        for move in legal {
            var next = game
            next.playPit(at: move)
            // Oracle margins are always player-one-positive; flip for player two.
            let margin = exactMargin(next, memo: &memo)
            trueValue[move] = mover == .playerOne ? margin : -margin
        }

        guard let bestValue = trueValue.values.max() else { continue }

        var moveRNG = SplitMix64(seed: rng.next())
        let chosen = AIMoveSelector.selectPit(
            in: game,
            for: mover,
            difficulty: config.difficulty,
            optionsOverride: config.options,
            rng: &moveRNG
        )

        guard let chosen, let chosenValue = trueValue[chosen] else { continue }

        considered += 1
        let regret = bestValue - chosenValue
        totalRegret += regret
        worstRegret = max(worstRegret, regret)
        if regret == 0 { agreed += 1 }
    }

    guard considered > 0 else {
        print("No usable positions generated.")
        return 2
    }

    print("Endgame oracle: \(config.label), \(considered) positions, \(stones) stones in play")
    print("  optimal move chosen: \(percent(Double(agreed) / Double(considered))) (\(agreed)/\(considered))")
    print("  mean regret: \(String(format: "%.3f", Double(totalRegret) / Double(considered))) stones")
    print("  worst regret: \(worstRegret) stones")

    // With an endgame this small the search should be solving outright.
    if agreed == considered {
        print("PASS: play is game-theoretically optimal on every position")
        return 0
    }
    print("FAIL: \(considered - agreed) positions were not optimal")
    return 1
}

func runOracleDeepCommand(_ args: Arguments) -> Int32 {
    let allowTime = args.flag("allow-time-limits")
    guard let engine = EngineConfig.parse(
        args.string("cfg", default: "impossible:positions=1000000"),
        budgetScale: 1.0,
        allowTimeLimits: allowTime
    ), let reference = EngineConfig.parse(
        args.string("reference", default: "impossible:positions=8000000"),
        budgetScale: 1.0,
        allowTimeLimits: allowTime
    ) else {
        print("Could not parse --cfg/--reference.")
        return 2
    }

    let positions = args.int("games", default: 40)
    var rng = SplitMix64(seed: UInt64(args.int("seed", default: 7)))

    var agreed = 0
    var considered = 0
    var totalRegret = 0
    var worstRegret = 0

    for index in 0..<positions {
        // Spread across the opening and middlegame.
        let plies = 4 + (index % 20)
        let game = randomMidgamePosition(plies: plies, rng: &rng)
        guard !game.isGameOver else { continue }
        let mover = game.currentPlayer
        let legal = game.legalPits(for: mover)
        guard legal.count > 1 else { continue }

        var values: [Int: Int] = [:]
        for move in legal {
            values[move] = referenceValue(of: move, in: game, config: reference)
        }
        guard let bestValue = values.values.max() else { continue }

        var moveRNG = SplitMix64(seed: rng.next())
        let chosen = AIMoveSelector.selectPit(
            in: game,
            for: mover,
            difficulty: engine.difficulty,
            optionsOverride: engine.options,
            rng: &moveRNG
        )
        guard let chosen, let chosenValue = values[chosen] else { continue }

        considered += 1
        let regret = bestValue - chosenValue
        totalRegret += regret
        worstRegret = max(worstRegret, regret)
        if regret == 0 { agreed += 1 }
    }

    guard considered > 0 else {
        print("No usable positions generated.")
        return 2
    }

    print("Deep oracle: \(engine.label) judged by \(reference.label), \(considered) positions")
    print("  reference's top move chosen: \(percent(Double(agreed) / Double(considered))) (\(agreed)/\(considered))")
    print("  mean regret: \(oneDecimal(Double(totalRegret) / Double(considered))) reference score units")
    print("  worst regret: \(worstRegret)")
    print("  Note: this is a proxy oracle, not ground truth. Track it across changes rather than reading it absolutely.")
    return 0
}

func runRulesDiffCommand(_ args: Arguments) -> Int32 {
    let trials = args.int("games", default: 20_000)
    var rng = SplitMix64(seed: UInt64(args.int("seed", default: 1)))
    var mismatches = 0
    var checked = 0

    for index in 0..<trials {
        // Mix fresh openings, midgames and thin endgames.
        let game: MancalaGame
        if index.isMultiple(of: 3) {
            game = randomEndgamePosition(stones: 2 + (index % 14), totalStones: 48, rng: &rng)
        } else {
            game = randomMidgamePosition(plies: index % 40, rng: &rng)
        }

        guard !game.isGameOver else { continue }
        let mover = game.currentPlayer
        let legal = game.legalPits(for: mover)
        guard !legal.isEmpty else { continue }
        let move = legal[rng.nextIndex(below: legal.count) ?? 0]

        var reference = game
        reference.playPit(at: move)

        let solver = MancalaOptimalSolver.applyMove(
            pits: game.pits,
            currentPlayer: mover == .playerOne ? 1 : 2,
            move: move
        )

        checked += 1
        let expectedPlayer = reference.currentPlayer == .playerOne ? 1 : 2
        if solver.pits != reference.pits || solver.currentPlayer != expectedPlayer {
            mismatches += 1
            if mismatches <= 5 {
                print("MISMATCH from \(game.pits) player \(mover.shortName) playing pit \(move)")
                print("  MancalaGame:          \(reference.pits) -> \(reference.currentPlayer.shortName)")
                print("  MancalaOptimalSolver: \(solver.pits) -> P\(solver.currentPlayer)")
            }
        }
    }

    print("Rules differential: \(checked) positions checked")
    if mismatches == 0 {
        print("PASS: the solver's rules engine matches MancalaGame")
        return 0
    }
    print("FAIL: \(mismatches) mismatches")
    return 1
}

func runBenchCommand(_ args: Arguments) -> Int32 {
    guard let config = EngineConfig.parse(
        args.string("cfg", default: "impossible"),
        budgetScale: args.double("budget-scale", default: 1.0),
        allowTimeLimits: args.flag("allow-time-limits")
    ) else {
        print("Could not parse --cfg.")
        return 2
    }

    var rng = SplitMix64(seed: UInt64(args.int("seed", default: 3)))
    var positions: [MancalaGame] = [MancalaGame()]
    for index in 0..<args.int("games", default: 8) {
        positions.append(randomMidgamePosition(plies: 6 + index * 3, rng: &rng))
    }

    var totalNodes = 0
    var totalElapsed: TimeInterval = 0

    print("Bench: \(config.label)")
    for (index, game) in positions.enumerated() where !game.isGameOver {
        let started = Date()
        let outcome = MancalaOptimalSolver.search(
            pits: game.pits,
            currentPlayer: game.currentPlayer == .playerOne ? 1 : 2,
            options: config.options ?? MancalaOptimalSolver.Options()
        )
        let elapsed = Date().timeIntervalSince(started)
        totalNodes += outcome.nodes
        totalElapsed += elapsed

        let knps = elapsed > 0 ? Double(outcome.nodes) / elapsed / 1000 : 0
        print("  position \(leftPadded(String(index), 2)):"
            + " depth \(leftPadded(String(outcome.completedDepth), 2)),"
            + " \(leftPadded(String(outcome.nodes), 9)) nodes,"
            + " \(leftPadded(twoDecimals(elapsed), 6))s,"
            + " \(leftPadded(String(Int(knps)), 6)) knps,"
            + " best pit \(outcome.bestMove ?? -1)"
            + (outcome.proven ? ", proven" : ""))
    }

    let totalKnps = totalElapsed > 0 ? Double(totalNodes) / totalElapsed / 1000 : 0
    print("  total: \(totalNodes) nodes in \(twoDecimals(totalElapsed))s (\(Int(totalKnps)) knps)")
    return 0
}

func printUsage() {
    print("""
    ai-arena — headless Mancala AI validation

    SUBCOMMANDS
      rules-diff        Prove the solver's rules engine matches MancalaGame.
      ladder            Round robin over all difficulties; fails if the ladder is not monotone.
      match             Head-to-head between two configs.
      oracle-endgame    Compare play against an exhaustive solve of small endgames.
      oracle-deep       Compare play against a much larger reference search.
      bench             Nodes/sec and time-to-depth.

    ENGINE SPECS
      <difficulty>[:key=value,...]   keys: positions, time, depth, endgame
      e.g. impossible   hard:depth=9   impossible:positions=2000000

    COMMON FLAGS
      --games N          Games or positions to run.
      --seed S           Seed. The same seed and flags reproduce a run exactly.
      --random-plies K   Seeded random opening sows before the engines take over.
      --swap-seats       Play each opening from both sides.
      --budget-scale F   Multiply search budgets (ladder defaults to 0.05).
      --minimum-gap F    Score-rate gap each tier must clear (ladder, default 0.03).
      --allow-time-limits  Re-enable wall-clock budgets. Makes runs unreproducible.

    EXAMPLES
      ai-arena rules-diff --games 20000
      ai-arena ladder --games 40
      ai-arena oracle-endgame --games 200 --stones 8
      ai-arena match --a hard --b impossible --games 40 --swap-seats
    """)
}

// MARK: - Entry point

@main
struct AIArena {
    static func main() {
        let args = Arguments(Array(CommandLine.arguments.dropFirst()))

        let status: Int32
        switch args.subcommand {
        case "match":
            status = runMatchCommand(args)
        case "ladder":
            status = runLadderCommand(args)
        case "oracle-endgame":
            status = runOracleEndgameCommand(args)
        case "oracle-deep":
            status = runOracleDeepCommand(args)
        case "rules-diff":
            status = runRulesDiffCommand(args)
        case "bench":
            status = runBenchCommand(args)
        default:
            printUsage()
            status = args.subcommand == "help" ? 0 : 2
        }

        exit(status)
    }
}
