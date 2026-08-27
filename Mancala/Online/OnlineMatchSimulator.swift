import Foundation
import Observation
import SwiftUI

/// The development-only door onto online multiplayer: a stand-in for the far
/// device, so a two-player online session can be exercised on one phone.
///
/// Game Center needs two accounts and a device can only hold one, so there is
/// no way to test online play for real on a single device. This replaces the
/// far *device*, not the code under test — everything inbound still arrives
/// through `GameCenterMultiplayerManager.applyInbound`, the same funnel a real
/// turn event goes through, and payloads are encoded and decoded as real JSON
/// on the way past. What you watch is the shipping code path.
///
/// Off by default. Flip `isEnabled` to `true` and an "Online Match Simulator"
/// entry appears in Settings; flip it back and every trace of this goes with
/// it — `isSimulationActive` is `false` whenever the flag is off, so the
/// manager never looks at any of it.
enum OnlineDevMenu {
    /// The switch. `false` for anything that ships.
    static let isEnabled = false

    static let settings = OnlineSimulatorSettings()

    /// Whether the manager should stand a simulator up in place of Game
    /// Center. Both the compile-time flag and the in-app toggle have to say
    /// yes, so the toggle can be left on between sessions without any risk of
    /// it reaching a build with the flag off.
    static var isSimulationActive: Bool {
        isEnabled && settings.isSimulatingMatches
    }

    static let opponentName = "Test Opponent"
}

/// What the simulator is told to do on its turn, so the awkward halves of a
/// live session — somebody closing the app, somebody's clock running out —
/// can be triggered rather than waited for.
enum OnlineSimulatorBehavior: String, CaseIterable, Identifiable {
    /// Plays a normal turn and hands the board back.
    case plays
    /// Quits, the way closing the app does.
    case leaves
    /// Goes quiet and never moves, so the local device's clock on the
    /// opponent runs all the way out.
    case stalls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plays: "Plays"
        case .leaves: "Leaves"
        case .stalls: "Stalls"
        }
    }

    var detail: String {
        switch self {
        case .plays: "Takes a normal turn and hands the board back."
        case .leaves: "Quits on its next turn, the way closing the app does."
        case .stalls: "Never moves, so the turn clock runs out."
        }
    }
}

/// Which side the local player sits on. Worth being able to change: the far
/// side is Player 2 in the usual case, and a bug in how Player 2's pits map to
/// the board only shows up when the local player is sitting there.
enum OnlineSimulatorSeat: String, CaseIterable, Identifiable {
    case playerOne
    case playerTwo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playerOne: "Player 1"
        case .playerTwo: "Player 2"
        }
    }

    var side: Player {
        switch self {
        case .playerOne: .playerOne
        case .playerTwo: .playerTwo
        }
    }
}

/// The simulator's knobs, remembered across launches so a scenario doesn't
/// have to be set up again on every run.
@Observable
final class OnlineSimulatorSettings {
    private enum Key {
        static let active = "dev.simulateOnlineMatches"
        static let behavior = "dev.simulatedOpponentBehavior"
        static let seat = "dev.simulatedLocalSeat"
        static let delay = "dev.simulatedOpponentDelay"
        static let difficulty = "dev.simulatedOpponentDifficulty"
    }

    var isSimulatingMatches: Bool {
        didSet { UserDefaults.standard.set(isSimulatingMatches, forKey: Key.active) }
    }

    var behavior: OnlineSimulatorBehavior {
        didSet { UserDefaults.standard.set(behavior.rawValue, forKey: Key.behavior) }
    }

    var localSeat: OnlineSimulatorSeat {
        didSet { UserDefaults.standard.set(localSeat.rawValue, forKey: Key.seat) }
    }

    /// How long the far device "thinks" before answering. Short enough to keep
    /// a test moving, long enough to see the waiting state.
    var moveDelay: Double {
        didSet { UserDefaults.standard.set(moveDelay, forKey: Key.delay) }
    }

    var difficulty: AIDifficulty {
        didSet { UserDefaults.standard.set(difficulty.rawValue, forKey: Key.difficulty) }
    }

    init() {
        let defaults = UserDefaults.standard
        isSimulatingMatches = defaults.bool(forKey: Key.active)
        behavior = defaults.string(forKey: Key.behavior)
            .flatMap(OnlineSimulatorBehavior.init(rawValue:)) ?? .plays
        localSeat = defaults.string(forKey: Key.seat)
            .flatMap(OnlineSimulatorSeat.init(rawValue:)) ?? .playerOne
        let storedDelay = defaults.double(forKey: Key.delay)
        moveDelay = storedDelay > 0 ? storedDelay : 1.5
        difficulty = defaults.string(forKey: Key.difficulty)
            .flatMap(AIDifficulty.init(rawValue:)) ?? .medium
    }
}

/// A local stand-in for the opponent's device.
///
/// It keeps a board of its own rather than reading the one on screen, so the
/// two sides can genuinely disagree — which is the point. Every payload it
/// receives is replayed against that board and checked against the board the
/// payload also carries, so a sender that ever describes its move wrongly is
/// caught here rather than in a silent desync between two real phones.
@MainActor
@Observable
final class OnlineMatchSimulator {
    /// What the far device does when it is handed the board.
    enum Reply {
        case moved(Data, isGameOver: Bool)
        case left
        /// Nothing comes back; the local clock is left to run out.
        case silent
    }

    private(set) var board = MancalaGame()
    private(set) var side: Player = .playerTwo
    private(set) var log: [String] = []
    /// Set the first time a payload fails to replay, so a desync is visible in
    /// the panel long after the line scrolls past.
    private(set) var hasSeenDesync = false

    private var settings: OnlineSimulatorSettings { OnlineDevMenu.settings }

    /// Puts the far device back to an opening board. Called at the start of
    /// every simulated session, which is the behaviour under test.
    func startMatch(localSide: Player) {
        side = localSide.opponent
        board = MancalaGame()
        log.removeAll()
        hasSeenDesync = false
        note("Match started. Local player is \(localSide.name); simulator is \(side.name).")
    }

    /// The far device opening the game, for when the local player is sitting
    /// in the second seat.
    func openingTurn() async -> Reply {
        await pause()
        return takeTurnIfWilling()
    }

    /// One round trip: take the local player's handover, check it, and answer.
    func respond(to data: Data) async -> Reply {
        guard let payload = try? JSONDecoder().decode(OnlineMatchPayload.self, from: data) else {
            note("⚠️ Could not decode the incoming payload.")
            return .silent
        }

        verifyHandover(payload)
        board = payload.game.game

        guard !board.isGameOver else {
            note("Game over on arrival — nothing to answer.")
            return .silent
        }

        await pause()
        return takeTurnIfWilling()
    }

    func clearLog() {
        log.removeAll()
        hasSeenDesync = false
    }

    func note(_ message: String) {
        log.append(message)
        if log.count > 60 {
            log.removeFirst(log.count - 60)
        }
    }

    // MARK: Internals

    private func pause() async {
        try? await Task.sleep(for: .seconds(max(0.1, settings.moveDelay)))
    }

    private func takeTurnIfWilling() -> Reply {
        switch settings.behavior {
        case .leaves:
            note("Opponent left the match.")
            return .left
        case .stalls:
            note("Opponent is stalling — letting the turn clock run out.")
            return .silent
        case .plays:
            break
        }

        guard board.currentPlayer == side, !board.isGameOver else {
            note("⚠️ Asked to move, but it isn't this side's turn.")
            return .silent
        }

        let moves = takeWholeTurn()
        guard !moves.isEmpty else {
            note("⚠️ No legal move available.")
            return .silent
        }

        let payload = OnlineMatchPayload(
            game: board,
            moveIndices: moves,
            playerOneName: side == .playerOne ? OnlineDevMenu.opponentName : "You",
            playerTwoName: side == .playerTwo ? OnlineDevMenu.opponentName : "You",
            playerOneGamePlayerID: nil,
            playerTwoGamePlayerID: nil
        )

        guard let data = try? JSONEncoder().encode(payload) else {
            note("⚠️ Could not encode the reply.")
            return .silent
        }

        note("Played \(list(moves))\(moves.count > 1 ? " (extra turns)" : "").")
        return .moved(data, isGameOver: board.isGameOver)
    }

    /// Sows until the turn actually passes — landing in your own store earns
    /// another, and the whole run has to travel as one handover.
    private func takeWholeTurn() -> [Int] {
        var moves: [Int] = []
        while !board.isGameOver, board.currentPlayer == side {
            let legal = board.legalPits(for: side)
            guard let pit = HeuristicAIPlayer.bestPit(
                in: board,
                for: side,
                difficulty: settings.difficulty,
                legalPits: legal
            ) else { break }

            board.playPit(at: pit)
            moves.append(pit)
        }
        return moves
    }

    /// The receiving device's rehearsal, run from this side. If replaying what
    /// the payload says was played doesn't reach the board the payload also
    /// carries, the sender is describing its own move wrongly — and on two
    /// real phones that would show up only as an opponent's move refusing to
    /// animate.
    private func verifyHandover(_ payload: OnlineMatchPayload) {
        let moves = payload.moves
        guard !moves.isEmpty else {
            note("⚠️ Handover carried no moves — the far board can only snap.")
            hasSeenDesync = true
            return
        }

        // The very check the receiving device makes, run from this side and
        // through the same function, so this can't pass while the real one
        // fails.
        if board.canReplay(moves, as: side.opponent, arrivingAt: payload.game.game) {
            note("Received \(list(moves)) — replay agrees with the board sent.")
        } else {
            var rehearsal = board
            for move in moves where rehearsal.canPlayPit(at: move) {
                rehearsal.playPit(at: move)
            }
            note("⚠️ Desync: replaying \(list(moves)) gave \(rehearsal.pits), payload says \(payload.game.pits).")
            hasSeenDesync = true
        }
    }

    private func list(_ moves: [Int]) -> String {
        "pit\(moves.count == 1 ? "" : "s") " + moves.map(String.init).joined(separator: " → ")
    }
}

// MARK: - Dev panel

/// The Settings page for the simulator: set a scenario up before starting a
/// match, force the awkward endings while one is running, and read back what
/// the far device thought it was doing.
struct OnlineMatchSimulatorView: View {
    @Bindable var settings: OnlineSimulatorSettings
    var manager: GameCenterMultiplayerManager

    var body: some View {
        Form {
            Section {
                Toggle("Simulate Online Matches", isOn: $settings.isSimulatingMatches)

                Text("Replaces Game Center with a local stand-in for the far device, so an online session can be played through on one phone. Start a match the usual way — Settings, or Play Again — and this answers instead of a real opponent.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Scenario") {
                Picker("You Play As", selection: $settings.localSeat) {
                    ForEach(OnlineSimulatorSeat.allCases) { seat in
                        Text(seat.title).tag(seat)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.localSeat == .playerTwo
                     ? "The opponent opens, so the first move you see is a replayed one."
                     : "You open, and the opponent answers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Opponent", selection: $settings.behavior) {
                    ForEach(OnlineSimulatorBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.behavior.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Skill", selection: $settings.difficulty) {
                    ForEach(AIDifficulty.allCases) { difficulty in
                        Text(difficulty.title).tag(difficulty)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Thinking Time")
                        Spacer()
                        Text("\(settings.moveDelay, format: .number.precision(.fractionLength(1)))s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $settings.moveDelay, in: 0.1...10, step: 0.1)
                }
            }

            Section("While A Match Is Running") {
                Button("Start Simulated Match") {
                    manager.startMatch()
                }
                .disabled(!settings.isSimulatingMatches)

                Button("Opponent Leaves Now") {
                    manager.simulateOpponentLeaving()
                }
                .disabled(!manager.isInActiveMatch)

                Button("Run The Clock Down") {
                    manager.expireTurnClockSoon()
                }
                .disabled(!manager.isInActiveMatch)

                Text("The clock button pulls the current turn's deadline in to three seconds from now, so a forfeit can be watched without sitting through a full minute.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let simulator = manager.simulator {
                Section {
                    if simulator.log.isEmpty {
                        Text("Nothing yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(simulator.log.enumerated().reversed()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.element.hasPrefix("⚠️") ? Color.red : Color.secondary)
                        }
                    }

                    Button("Clear", role: .destructive) {
                        simulator.clearLog()
                    }
                    .disabled(simulator.log.isEmpty)
                } header: {
                    Text("Far Device Log")
                } footer: {
                    Text(simulator.hasSeenDesync
                         ? "⚠️ A handover didn't replay cleanly. On two real phones that shows up as an opponent's move refusing to animate."
                         : "Every handover is replayed against this side's own board and checked against the board that arrived with it.")
                    .font(.footnote)
                    .foregroundStyle(simulator.hasSeenDesync ? Color.red : Color.secondary)
                }
            }
        }
        .navigationTitle("Online Simulator")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
