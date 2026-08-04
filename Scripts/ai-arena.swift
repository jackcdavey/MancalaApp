// Headless AI arena: plays whole games between any two opponents with no UI,
// so difficulty tuning can be measured instead of guessed. Build and run:
//
//   swiftc -O -o /tmp/ai-arena \
//     Mancala/Models/Player.swift Mancala/Models/MancalaGame.swift \
//     Mancala/AI/MancalaHeuristicAI.swift Mancala/AI/MancalaOptimalSolver.swift \
//     Scripts/ai-arena.swift \
//   && /tmp/ai-arena ladder
//
// Subcommands:
//   ladder                     round-robin over every shipped difficulty
//   match <a> <b> [games]      head-to-head, agent <a> as Player 1
//   gauntlet <agent> [games]   <agent> as Player 2 against every probe opponent
//   selfcheck                  solver sanity checks on solved endgames
//
// Agent names: easy, medium, hard, impossible, random, greedy, minimax<N>
// (minimax4, minimax8, … is a reference engine used as a yardstick — it is not
// something the app ships).
//
// Like Scripts/verify-challenges.swift, this file supplies a bare AIDifficulty
// stand-in so the AI sources compile without SwiftUI; do not include
// Mancala/Models/GameSettings.swift.

import Foundation

enum AIDifficulty: String {
    case easy
    case medium
    case hard
    case impossible

    var title: String { rawValue.capitalized }
}

// MARK: - Agents

/// Everything the arena can seat at the board.
enum Agent {
    case difficulty(AIDifficulty)
    /// Uniformly random legal move — the floor any real difficulty must clear.
    case random
    /// Pure one-ply greed: take the biggest immediate store gain, extra turns first.
    case greedy
    /// Fixed-depth minimax with the solver's evaluation. The yardstick.
    case minimax(depth: Int)

    var name: String {
        switch self {
        case .difficulty(let value): value.rawValue
        case .random: "random"
        case .greedy: "greedy"
        case .minimax(let depth): "minimax\(depth)"
        }
    }

    static func parse(_ raw: String) -> Agent? {
        if let difficulty = AIDifficulty(rawValue: raw) { return .difficulty(difficulty) }
        switch raw {
        case "random": return .random
        case "greedy": return .greedy
        default: break
        }
        if raw.hasPrefix("minimax"), let depth = Int(raw.dropFirst("minimax".count)), depth > 0 {
            return .minimax(depth: depth)
        }
        return nil
    }

    /// Impossible runs a real search; keep its budget small enough that a few
    /// hundred games finish, but large enough to be the same engine users face.
    static let arenaSearchPositions = 400_000
}

func chooseMove(
    _ agent: Agent,
    in game: MancalaGame,
    for player: Player,
    using generator: inout SeededGenerator
) -> Int? {
    let legalPits = game.legalPits(for: player)
    guard !legalPits.isEmpty else { return nil }

    switch agent {
    case .random:
        return legalPits.randomElement(using: &generator)

    case .greedy:
        return legalPits.max { lhs, rhs in
            greedyScore(lhs, in: game, for: player) < greedyScore(rhs, in: game, for: player)
        }

    case .minimax(let depth):
        return MancalaOptimalSolver.bestMove(
            pits: game.pits,
            currentPlayer: player == .playerOne ? 1 : 2,
            maxPositions: Int.max,
            timeLimit: nil,
            fixedDepth: depth,
            progress: { _ in },
            progressUpdate: { _ in }
        ) ?? legalPits.first

    case .difficulty(.impossible):
        return MancalaOptimalSolver.bestMove(
            pits: game.pits,
            currentPlayer: player == .playerOne ? 1 : 2,
            maxPositions: Agent.arenaSearchPositions,
            timeLimit: nil,
            progress: { _ in },
            progressUpdate: { _ in }
        ) ?? legalPits.first

    case .difficulty(let difficulty):
        return MancalaHeuristicAI.chooseMove(in: game, for: player, difficulty: difficulty, using: &generator)
    }
}

private func greedyScore(_ pit: Int, in game: MancalaGame, for player: Player) -> Int {
    var simulated = game
    let before = simulated.storeCount(for: player)
    simulated.playPit(at: pit)
    let gain = simulated.storeCount(for: player) - before
    let extraTurn = simulated.currentPlayer == player && !simulated.isGameOver ? 100 : 0
    return gain * 10 + extraTurn
}

// MARK: - Playing games

enum Outcome {
    case playerOne
    case playerTwo
    case draw
}

struct GameRecord {
    let outcome: Outcome
    let playerOneScore: Int
    let playerTwoScore: Int
    let plies: Int
}

/// Plays a game out from `start`. Both agents are deterministic in every
/// difficulty that matters, so the variety has to come from `start`.
func playGame(
    playerOne: Agent,
    playerTwo: Agent,
    from start: MancalaGame,
    seed: UInt64
) -> GameRecord {
    var game = start
    var generator = SeededGenerator(seed: seed)
    var plies = 0

    // 300 sows is far beyond any real game; it only guards a broken agent.
    while !game.isGameOver && plies < 300 {
        let agent = game.currentPlayer == .playerOne ? playerOne : playerTwo
        guard let move = chooseMove(agent, in: game, for: game.currentPlayer, using: &generator) else { break }
        game.playPit(at: move)
        plies += 1
    }

    let one = game.storeCount(for: .playerOne)
    let two = game.storeCount(for: .playerTwo)
    let outcome: Outcome = one > two ? .playerOne : (two > one ? .playerTwo : .draw)
    return GameRecord(outcome: outcome, playerOneScore: one, playerTwoScore: two, plies: plies)
}

// MARK: - Openings

/// Opening positions used to give deterministic agents something to disagree
/// about. Two agents that both play the book line would otherwise replay one
/// game per seat, and every match would read 50%.
///
/// Each opening is the standard position plus a few random legal sows. That is
/// enough to fan out across the real opening tree without handing anyone a
/// contrived advantage, and it is seeded, so a run reproduces exactly.
enum OpeningBook {
    static func positions(count: Int, plies: Int, seed: UInt64 = 0xB0A12D) -> [MancalaGame] {
        var seen: Set<[Int]> = []
        var openings: [MancalaGame] = []
        var attempt: UInt64 = 0

        // The untouched start position is always opening zero — it is the one
        // players actually see, so it must never be sampled away.
        openings.append(MancalaGame())
        seen.insert(MancalaGame().pits + [1])

        while openings.count < count && attempt < UInt64(count) * 200 {
            var generator = SeededGenerator(seed: seed &+ attempt &* 0x9E3779B97F4A7C15)
            attempt += 1

            var game = MancalaGame()
            for _ in 0..<plies {
                let legal = game.legalPits(for: game.currentPlayer)
                guard let move = legal.randomElement(using: &generator) else { break }
                game.playPit(at: move)
            }

            guard !game.isGameOver else { continue }
            let key = game.pits + [game.currentPlayer == .playerOne ? 1 : 2]
            guard seen.insert(key).inserted else { continue }
            openings.append(game)
        }

        return openings
    }
}

// MARK: - Match results

/// A match from one agent's point of view. `share` counts a draw as half a win,
/// so 50% means evenly matched regardless of how many games drew.
struct MatchResult {
    var wins = 0
    var losses = 0
    var draws = 0
    var stonesFor = 0
    var stonesAgainst = 0
    /// Split out because the whole question is whether opening first decides it.
    var winsWhenMovingFirst = 0
    var gamesMovingFirst = 0
    var drawsWhenMovingFirst = 0

    var games: Int { wins + losses + draws }

    var share: Double {
        games == 0 ? 0 : (Double(wins) + Double(draws) / 2) / Double(games)
    }

    var shareMovingFirst: Double {
        gamesMovingFirst == 0 ? 0 : (Double(winsWhenMovingFirst) + Double(drawsWhenMovingFirst) / 2) / Double(gamesMovingFirst)
    }

    var shareMovingSecond: Double {
        let gamesSecond = games - gamesMovingFirst
        guard gamesSecond > 0 else { return 0 }
        let winsSecond = wins - winsWhenMovingFirst
        let drawsSecond = draws - drawsWhenMovingFirst
        return (Double(winsSecond) + Double(drawsSecond) / 2) / Double(gamesSecond)
    }

    var averageMargin: Double {
        games == 0 ? 0 : Double(stonesFor - stonesAgainst) / Double(games)
    }

    mutating func record(_ record: GameRecord, subjectWasPlayerOne: Bool, subjectMovedFirst: Bool) {
        let subjectScore = subjectWasPlayerOne ? record.playerOneScore : record.playerTwoScore
        let otherScore = subjectWasPlayerOne ? record.playerTwoScore : record.playerOneScore
        stonesFor += subjectScore
        stonesAgainst += otherScore

        let won: Bool
        let drew = record.outcome == .draw
        switch record.outcome {
        case .draw: won = false
        case .playerOne: won = subjectWasPlayerOne
        case .playerTwo: won = !subjectWasPlayerOne
        }

        if drew {
            draws += 1
        } else if won {
            wins += 1
        } else {
            losses += 1
        }

        if subjectMovedFirst {
            gamesMovingFirst += 1
            if won { winsWhenMovingFirst += 1 }
            if drew { drawsWhenMovingFirst += 1 }
        }
    }

    static func + (lhs: MatchResult, rhs: MatchResult) -> MatchResult {
        var merged = lhs
        merged.wins += rhs.wins
        merged.losses += rhs.losses
        merged.draws += rhs.draws
        merged.stonesFor += rhs.stonesFor
        merged.stonesAgainst += rhs.stonesAgainst
        merged.winsWhenMovingFirst += rhs.winsWhenMovingFirst
        merged.gamesMovingFirst += rhs.gamesMovingFirst
        merged.drawsWhenMovingFirst += rhs.drawsWhenMovingFirst
        return merged
    }
}

/// Plays every opening twice — once with `subject` as Player 1, once as Player 2
/// — so the first-move edge cancels out of the headline number while still being
/// reported separately.
func runMatch(subject: Agent, opponent: Agent, openings: [MancalaGame]) -> MatchResult {
    let pairings = openings.count * 2
    let lock = NSLock()
    var total = MatchResult()

    DispatchQueue.concurrentPerform(iterations: pairings) { index in
        let opening = openings[index / 2]
        let subjectIsPlayerOne = index.isMultiple(of: 2)
        let seed = UInt64(index) &* 0x9E3779B97F4A7C15 &+ 0x5EED

        let record = playGame(
            playerOne: subjectIsPlayerOne ? subject : opponent,
            playerTwo: subjectIsPlayerOne ? opponent : subject,
            from: opening,
            seed: seed
        )
        let subjectMovedFirst = (opening.currentPlayer == .playerOne) == subjectIsPlayerOne

        lock.lock()
        total.record(record, subjectWasPlayerOne: subjectIsPlayerOne, subjectMovedFirst: subjectMovedFirst)
        lock.unlock()
    }

    return total
}

// MARK: - Reporting

func percent(_ value: Double) -> String {
    String(format: "%5.1f%%", value * 100)
}

func padded(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func printMatch(subject: Agent, opponent: Agent, result: MatchResult) {
    print("""
      \(subject.name) vs \(opponent.name) — \(result.games) games, seats swapped every opening

        share            \(percent(result.share))   (\(result.wins)W \(result.losses)L \(result.draws)D)
        moving first     \(percent(result.shareMovingFirst))
        moving second    \(percent(result.shareMovingSecond))
        stone margin     \(String(format: "%+.2f", result.averageMargin)) per game
    """)
}

// MARK: - Commands

let ladderAgents: [Agent] = [
    .random,
    .greedy,
    .difficulty(.easy),
    .difficulty(.medium),
    .difficulty(.hard),
    .difficulty(.impossible),
]

/// Every difficulty against every other, both seats, over a shared opening set.
/// A correct ladder reads as a monotonically rising final column.
func runLadder(openingCount: Int, openingPlies: Int) {
    let openings = OpeningBook.positions(count: openingCount, plies: openingPlies)
    print("Round robin over \(openings.count) openings (\(openingPlies) random plies), \(openings.count * 2) games per pair.\n")

    var grid: [String: [String: Double]] = [:]
    var totals: [String: (share: Double, matches: Int)] = [:]

    for (index, subject) in ladderAgents.enumerated() {
        for opponent in ladderAgents[(index + 1)...] {
            let result = runMatch(subject: subject, opponent: opponent, openings: openings)
            grid[subject.name, default: [:]][opponent.name] = result.share
            grid[opponent.name, default: [:]][subject.name] = 1 - result.share

            let subjectRunning = totals[subject.name] ?? (0, 0)
            totals[subject.name] = (subjectRunning.share + result.share, subjectRunning.matches + 1)
            let opponentRunning = totals[opponent.name] ?? (0, 0)
            totals[opponent.name] = (opponentRunning.share + (1 - result.share), opponentRunning.matches + 1)
        }
    }

    print("  " + padded("", 12) + ladderAgents.map { padded($0.name, 12) }.joined() + "field")
    for subject in ladderAgents {
        var row = "  " + padded(subject.name, 12)
        for opponent in ladderAgents {
            row += padded(subject.name == opponent.name ? "--" : percent(grid[subject.name]?[opponent.name] ?? 0), 12)
        }
        let running = totals[subject.name] ?? (0, 0)
        row += percent(running.matches == 0 ? 0 : running.share / Double(running.matches))
        print(row)
    }

    // The ladder is only useful if it is ordered; say so out loud.
    let field = ladderAgents.map { agent -> Double in
        let running = totals[agent.name] ?? (0, 0)
        return running.matches == 0 ? 0 : running.share / Double(running.matches)
    }
    let breaks = zip(zip(ladderAgents, field), zip(ladderAgents, field).dropFirst())
        .filter { $0.1 > $1.1 }
        .map { "\($0.0.name) > \($1.0.name)" }

    if breaks.isEmpty {
        print("\n  Ladder ordering: OK — every rung outperforms the one below it.")
    } else {
        print("\n  Ladder ordering: BROKEN — \(breaks.joined(separator: ", "))")
    }
}

/// One agent against a fixed panel, split by who opened. This is the view that
/// answers "is Impossible only beatable because the player moves first?".
func runGauntlet(agent: Agent, openingCount: Int, openingPlies: Int) {
    let probes = ladderAgents.filter { $0.name != agent.name } + [.minimax(depth: 6), .minimax(depth: 10)]
    let openings = OpeningBook.positions(count: openingCount, plies: openingPlies)
    print("\(agent.name) over \(openings.count) openings, \(openings.count * 2) games per opponent.\n")
    print("  " + padded("opponent", 12) + padded("share", 10) + padded("opens", 10) + padded("responds", 10) + "margin")

    for probe in probes {
        let result = runMatch(subject: agent, opponent: probe, openings: openings)
        print("  " + padded(probe.name, 12)
            + padded(percent(result.share), 10)
            + padded(percent(result.shareMovingFirst), 10)
            + padded(percent(result.shareMovingSecond), 10)
            + String(format: "%+.2f", result.averageMargin))
    }
}

/// Positions with a known answer. If the solver misses these, no amount of
/// win-rate tuning matters.
func runSelfCheck() {
    struct Probe {
        let name: String
        let pits: [Int]
        let player: Int
        let expected: [Int]
        let note: String
    }

    let probes: [Probe] = [
        Probe(
            name: "free extra turn",
            pits: [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0],
            player: 2,
            expected: [12],
            note: "pit 12 holds one stone and lands in the store"
        ),
        Probe(
            name: "capture available",
            pits: [0, 0, 0, 0, 5, 0, 0, 0, 3, 0, 0, 0, 0, 0],
            player: 2,
            expected: [8],
            note: "sowing 8 ends on the empty pit 11 opposite a loaded pit"
        ),
        Probe(
            name: "must take the win",
            pits: [1, 0, 0, 0, 0, 0, 20, 0, 0, 0, 0, 0, 2, 25],
            player: 2,
            expected: [12],
            note: "any move ends the game; take the larger store"
        ),
    ]

    var allPassed = true
    for probe in probes {
        let move = MancalaOptimalSolver.bestMove(
            pits: probe.pits,
            currentPlayer: probe.player,
            maxPositions: 5_000_000,
            timeLimit: nil,
            progress: { _ in },
            progressUpdate: { _ in }
        )
        let passed = move.map { probe.expected.contains($0) } ?? false
        allPassed = allPassed && passed
        print("  \(passed ? "PASS" : "FAIL") \(probe.name): chose \(move.map(String.init) ?? "--"), expected \(probe.expected) — \(probe.note)")
    }

    if !allPassed {
        exit(1)
    }
}

// MARK: - Entry point

@main
struct Arena {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        let plies = ProcessInfo.processInfo.environment["ARENA_PLIES"].flatMap(Int.init) ?? 4

        switch arguments.first ?? "ladder" {
        case "ladder":
            runLadder(openingCount: arguments.count > 1 ? Int(arguments[1]) ?? 24 : 24, openingPlies: plies)

        case "match":
            guard arguments.count >= 3,
                  let subject = Agent.parse(arguments[1]),
                  let opponent = Agent.parse(arguments[2]) else {
                print("usage: ai-arena match <agent> <agent> [openings]")
                exit(2)
            }
            let openings = OpeningBook.positions(count: arguments.count > 3 ? Int(arguments[3]) ?? 24 : 24, plies: plies)
            print("Openings: \(openings.count) (\(plies) random plies each)")
            printMatch(subject: subject, opponent: opponent, result: runMatch(subject: subject, opponent: opponent, openings: openings))

        case "gauntlet":
            guard arguments.count >= 2, let agent = Agent.parse(arguments[1]) else {
                print("usage: ai-arena gauntlet <agent> [openings]")
                exit(2)
            }
            runGauntlet(agent: agent, openingCount: arguments.count > 2 ? Int(arguments[2]) ?? 24 : 24, openingPlies: plies)

        case "selfcheck":
            runSelfCheck()

        default:
            print("usage: ai-arena [ladder|match|gauntlet|selfcheck] ...")
            exit(2)
        }
    }
}
