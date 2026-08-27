// Verifies the contract between two devices in an online match: that a turn
// handed over as an `OnlineMatchPayload` can be replayed by the receiver and
// land on exactly the board the sender says it reached.
//
// This is the gate that decides whether an opponent's move animates or snaps,
// so a regression here is silent in the app — the stones just stop moving.
// Run after touching MancalaGame's rules or the payload:
//
//   swiftc -O -o /tmp/verify-online-replay \
//     Mancala/Models/Player.swift Mancala/Models/MancalaGame.swift \
//     Mancala/Models/PersistenceModels.swift \
//     Mancala/Online/OnlineMatchPayload.swift \
//     Scripts/verify-online-replay.swift \
//   && /tmp/verify-online-replay
//
// Foundation only; do not add files that import SwiftUI or GameKit.

import Foundation

var failures: [String] = []
var checks = 0

func expect(_ condition: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if !condition { failures.append(what()) }
}

/// One device's turn: sow until the turn actually passes, collecting every pit
/// played. This mirrors what `handleOnlineMoveIfNeeded` accumulates — an extra
/// turn keeps the board on the sender's side for another sow, and the whole run
/// travels as one handover.
func takeWholeTurn(_ game: inout MancalaGame, as player: Player, rng: inout SystemRandomNumberGenerator) -> [Int] {
    var moves: [Int] = []
    while !game.isGameOver, game.currentPlayer == player {
        let legal = game.legalPits(for: player)
        guard let pit = legal.randomElement(using: &rng) else { break }
        game.playPit(at: pit)
        moves.append(pit)
    }
    return moves
}

/// Plays whole games as two separate devices, handing the board back and forth
/// through encoded payloads, and checks the receiver can always replay what it
/// is sent.
func playSessions(_ count: Int) {
    var rng = SystemRandomNumberGenerator()
    var longestRun = 0
    var multiSowTurns = 0

    for session in 0..<count {
        // Two genuinely separate boards, the way two phones have.
        var sender = MancalaGame()
        var receiver = MancalaGame()
        var turn = Player.playerOne

        while !sender.isGameOver {
            let before = receiver
            let moves = takeWholeTurn(&sender, as: turn, rng: &rng)

            guard !moves.isEmpty else {
                failures.append("session \(session): \(turn.name) had no legal move on a live board")
                break
            }

            longestRun = max(longestRun, moves.count)
            if moves.count > 1 { multiSowTurns += 1 }

            // Over the wire and back, as real JSON.
            let payload = OnlineMatchPayload(
                game: sender,
                moveIndices: moves,
                playerOneName: "A",
                playerTwoName: "B",
                playerOneGamePlayerID: nil,
                playerTwoGamePlayerID: nil
            )

            guard let data = try? JSONEncoder().encode(payload),
                  let decoded = try? JSONDecoder().decode(OnlineMatchPayload.self, from: data) else {
                failures.append("session \(session): payload would not round-trip through JSON")
                break
            }

            expect(decoded.moves == moves,
                   "session \(session): moves survived encoding as \(decoded.moves), sent \(moves)")

            let arrived = decoded.game.game
            expect(before.canReplay(decoded.moves, as: turn, arrivingAt: arrived),
                   "session \(session): receiver could not replay \(moves) from \(before.pits) to \(arrived.pits)")

            // What the receiver's animation actually does to its own board.
            for move in decoded.moves where receiver.canPlayPit(at: move) {
                receiver.playPit(at: move)
            }

            expect(receiver.matches(sender),
                   "session \(session): boards diverged — receiver \(receiver.pits), sender \(sender.pits)")

            turn = sender.currentPlayer
        }

        expect(receiver.matches(sender),
               "session \(session): final boards disagree — receiver \(receiver.pits), sender \(sender.pits)")
    }

    print("  longest handover: \(longestRun) sows; turns needing more than one: \(multiSowTurns)")
}

/// The rehearsal has to refuse everything it can't reproduce, or a drifted
/// board would animate its way somewhere plausible and wrong.
func checkRefusals() {
    let fresh = MancalaGame()
    var played = fresh
    played.playPit(at: 2)

    expect(!fresh.canReplay([2], as: .playerOne, arrivingAt: fresh),
           "a move that reaches a different board should be refused")

    expect(fresh.canReplay([2], as: .playerOne, arrivingAt: played),
           "a legal move reaching the stated board should be accepted")

    expect(!fresh.canReplay([2], as: .playerTwo, arrivingAt: played),
           "a move in the other side's pits should be refused")

    expect(!fresh.canReplay([7], as: .playerTwo, arrivingAt: played),
           "a move by the side that isn't on turn should be refused")

    expect(!fresh.canReplay([], as: .playerOne, arrivingAt: played),
           "an empty run should be refused")

    expect(!fresh.canReplay([6], as: .playerOne, arrivingAt: played),
           "sowing from a store should be refused")

    // A drifted receiver: same move, but its board has moved on underneath.
    var drifted = fresh
    drifted.playPit(at: 0)
    expect(!drifted.canReplay([2], as: .playerOne, arrivingAt: played),
           "a replay onto a drifted board should be refused")
}

/// A payload from a build that only ever sent its last move still has to
/// decode, and report that one move.
func checkVersionOneCompatibility() {
    // Hand-written in the old shape on purpose — no `moveIndices` key at all.
    // The board is a fresh game with pit 0 sowed: four stones into pits 1-4.
    let legacy = """
    {"version":1,"game":{"pits":[0,5,5,5,5,4,0,4,4,4,4,4,4,0],"currentPlayer":"playerTwo","isDraw":false},\
    "lastMoveIndex":0,"playerOneName":"A","playerTwoName":"B"}
    """

    guard let data = legacy.data(using: .utf8),
          let payload = try? JSONDecoder().decode(OnlineMatchPayload.self, from: data) else {
        failures.append("a version-1 payload no longer decodes")
        return
    }

    expect(payload.version == 1, "version-1 payload reported version \(payload.version)")
    expect(payload.moves == [0], "version-1 payload should fall back to its last move, got \(payload.moves)")

    let fresh = MancalaGame()
    expect(fresh.canReplay(payload.moves, as: .playerOne, arrivingAt: payload.game.game),
           "a single-sow version-1 payload should still replay")
}

@main
struct OnlineReplayVerifier {
    static func main() {
        let sessions = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 500

        print("==> refusals")
        checkRefusals()

        print("==> version-1 payloads")
        checkVersionOneCompatibility()

        print("==> \(sessions) simulated sessions")
        playSessions(sessions)

        print()
        if failures.isEmpty {
            print("All \(checks) online-replay checks passed.")
            exit(0)
        }

        print("FAILED \(failures.count) of \(checks) checks:")
        for failure in failures.prefix(20) {
            print("  - \(failure)")
        }
        if failures.count > 20 {
            print("  ... and \(failures.count - 20) more")
        }
        exit(1)
    }
}
