import Foundation
import GameKit
import Observation
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Why an online session stopped short of a finished game. Each one puts the
/// same choice in front of the player: back to the menu, or straight into
/// another match.
enum OnlineMatchEnding: Equatable {
    case opponentLeft(String)
    case opponentTimedOut(String)
    case localTimedOut

    var title: String {
        switch self {
        case .opponentLeft: "Opponent Left"
        case .opponentTimedOut: "Out of Time"
        case .localTimedOut: "Out of Time"
        }
    }

    var message: String {
        switch self {
        case .opponentLeft(let name):
            "\(name) left the game."
        case .opponentTimedOut(let name):
            "\(name) ran out of time. You win by forfeit."
        case .localTimedOut:
            "You ran out of time, so the match was forfeited."
        }
    }
}

/// One inbound match update, handed to the view as a whole. Carried behind a
/// monotonically rising `updateVersion` rather than watched field by field:
/// an opponent who plays the same pit twice running produces two identical
/// `lastMoveIndex` values, and an `onChange` on that value would sleep
/// through the second one.
struct OnlineMatchUpdate {
    let matchID: String
    let payload: OnlineMatchPayload?
    /// The match arrived with no board on it — nobody has moved yet, so this
    /// is the start of a session and the board belongs at the opening layout.
    let isNewMatch: Bool
}

@MainActor
@Observable
final class GameCenterMultiplayerManager: NSObject {
    enum ConnectionState: Equatable {
        case unavailable(String)
        case signedOut
        case ready
        case matching
        case inMatch
        case error(String)
    }

    /// How long a player has to sow once the turn is theirs. Sent to Game
    /// Center as the match's own turn timeout as well, so a device that never
    /// comes back still loses the turn server-side.
    static let turnTimeLimit: TimeInterval = 60

    /// Extra time the *waiting* side allows before calling an opponent's
    /// clock expired. The opponent forfeits itself the moment its own clock
    /// runs out; this covers the round trip of that message, so the two sides
    /// don't both declare a timeout from slightly different clocks.
    private static let opponentTimeoutGrace: TimeInterval = 6

    private(set) var state: ConnectionState = .signedOut
    private(set) var currentMatchID: String?
    private(set) var localPlayerSide: Player?
    private(set) var isLocalPlayersTurn = false
    private(set) var opponentName = "Opponent"
    private(set) var statusMessage = "Sign in to Game Center to play online."
    private(set) var pendingUpdate: OnlineMatchUpdate?
    private(set) var updateVersion = 0

    /// Set when a session stopped for a reason the player needs to see — an
    /// opponent walking out, or either clock running down. Cleared by the
    /// view once it has shown the notice.
    private(set) var matchEnding: OnlineMatchEnding?

    /// When the side that is on the clock runs out of time, or `nil` when no
    /// clock is running. Published as a deadline rather than a ticking count
    /// so the countdown redraws inside its own view instead of invalidating
    /// everything that reads this manager once a second.
    private(set) var turnDeadline: Date?
    /// True while `turnDeadline` belongs to the local player.
    private(set) var isLocalTurnClock = false

    @ObservationIgnored private var turnClockTask: Task<Void, Never>?

    /// Matches this device has walked out of. A quit comes back around as a
    /// match-ended event of its own, and without this the player who left
    /// would be told their opponent left.
    @ObservationIgnored private var abandonedMatchIDs: Set<String> = []

    /// The dev-only stand-in for the far device, present only while
    /// `OnlineDevMenu.isSimulationActive` — which is false in anything that
    /// ships. See `OnlineMatchSimulator`.
    private(set) var simulator: OnlineMatchSimulator?
    @ObservationIgnored private var simulationTask: Task<Void, Never>?

    var isAuthenticated: Bool {
        GKLocalPlayer.local.isAuthenticated
    }

    var canStartMatch: Bool {
        if OnlineDevMenu.isSimulationActive { return true }
        return isAuthenticated && !isMultiplayerRestricted
    }

    /// Whether an online match can be started right now: really signed in, or
    /// the dev simulator standing in for Game Center.
    var isReadyToPlayOnline: Bool {
        OnlineDevMenu.isSimulationActive || isAuthenticated
    }

    var isMultiplayerRestricted: Bool {
        GKLocalPlayer.local.isMultiplayerGamingRestricted
    }

    /// True while there is a live session the player would be walking out of.
    var isInActiveMatch: Bool {
        currentMatchID != nil
    }

    func authenticateLocalPlayer() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }

                if let viewController {
                    self.present(viewController)
                    return
                }

                if let error {
                    self.state = .error(error.localizedDescription)
                    self.statusMessage = "Game Center is unavailable: \(error.localizedDescription)"
                    return
                }

                guard GKLocalPlayer.local.isAuthenticated else {
                    self.state = .signedOut
                    self.statusMessage = "Sign in to Game Center to play online."
                    return
                }

                GKLocalPlayer.local.register(self)

                if GKLocalPlayer.local.isMultiplayerGamingRestricted {
                    self.state = .unavailable("Multiplayer is restricted for this Game Center account.")
                    self.statusMessage = "Multiplayer is restricted for this Game Center account."
                } else {
                    self.state = .ready
                    self.statusMessage = "Ready to start an online match."
                }
            }
        }
    }

    func startMatch() {
        if OnlineDevMenu.isSimulationActive {
            matchEnding = nil
            startSimulatedMatch()
            return
        }

        guard canStartMatch else {
            statusMessage = isAuthenticated ? "Multiplayer is restricted for this account." : "Sign in to Game Center first."
            return
        }

        matchEnding = nil

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.inviteMessage = "Play \(AppInfo.name) with me."

        let viewController = GKTurnBasedMatchmakerViewController(matchRequest: request)
        viewController.turnBasedMatchmakerDelegate = self
        viewController.showExistingMatches = true
        state = .matching
        statusMessage = "Choose an opponent in Game Center."
        present(viewController)
    }

    func showAchievements() {
        guard isAuthenticated else {
            statusMessage = "Sign in to Game Center first."
            authenticateLocalPlayer()
            return
        }

        #if os(macOS)
        state = .unavailable("Game Center presentation is available on iPhone and iPad in this version.")
        statusMessage = "Game Center presentation is available on iPhone and iPad in this version."
        #else
        GKAccessPoint.shared.trigger(state: .achievements) { }
        #endif
    }

    func clearPendingUpdate() {
        pendingUpdate = nil
    }

    func clearMatchEnding() {
        matchEnding = nil
    }

    func noteLocalExtraTurn() {
        isLocalPlayersTurn = true
        statusMessage = "Extra turn."
        startTurnClock(isLocal: true)
    }

    /// Restarts the local clock from now. Called once the board has finished
    /// replaying the opponent's sows, so the seconds spent watching stones
    /// travel don't come out of the player's own minute.
    func restartLocalTurnClock() {
        guard isInActiveMatch, isLocalPlayersTurn else { return }
        startTurnClock(isLocal: true)
    }

    func sendTurn(
        game: MancalaGame,
        moveIndices: [Int],
        playerOneName: String,
        playerTwoName: String
    ) {
        guard let matchID = currentMatchID else {
            state = .error("No active online match.")
            statusMessage = "No active online match."
            return
        }

        if simulator != nil {
            let payload = OnlineMatchPayload(
                game: game,
                moveIndices: moveIndices,
                playerOneName: playerOneName,
                playerTwoName: playerTwoName,
                playerOneGamePlayerID: gamePlayerID(for: .playerOne),
                playerTwoGamePlayerID: gamePlayerID(for: .playerTwo)
            )
            guard let data = try? JSONEncoder().encode(payload) else {
                state = .error("Unable to encode online match data.")
                statusMessage = "Unable to send the turn."
                return
            }
            sendSimulatedTurn(data, matchID: matchID, isGameOver: game.isGameOver)
            return
        }

        GKTurnBasedMatch.load(withID: matchID) { [weak self] match, error in
            guard let manager = self else { return }
            Task { @MainActor in
                guard let match else {
                    manager.state = .error(error?.localizedDescription ?? "Unable to load match.")
                    manager.statusMessage = "Unable to load the current match."
                    return
                }

                manager.applyMatchMetadata(match)

                guard manager.isCurrentParticipant(match.currentParticipant) else {
                    manager.statusMessage = "Waiting for your turn."
                    manager.isLocalPlayersTurn = false
                    return
                }

                let payload = OnlineMatchPayload(
                    game: game,
                    moveIndices: moveIndices,
                    playerOneName: playerOneName,
                    playerTwoName: playerTwoName,
                    playerOneGamePlayerID: manager.gamePlayerID(for: .playerOne),
                    playerTwoGamePlayerID: manager.gamePlayerID(for: .playerTwo)
                )

                guard let data = try? JSONEncoder().encode(payload) else {
                    manager.state = .error("Unable to encode online match data.")
                    manager.statusMessage = "Unable to send the turn."
                    return
                }

                if game.isGameOver {
                    manager.applyOutcomes(to: match, game: game)
                    match.endMatchInTurn(withMatch: data) { error in
                        Task { @MainActor in
                            if let error {
                                manager.state = .error(error.localizedDescription)
                                manager.statusMessage = "Unable to end match: \(error.localizedDescription)"
                            } else {
                                manager.state = .inMatch
                                manager.statusMessage = "Online match ended."
                                manager.concludeMatch(matchID)
                            }
                        }
                    }
                } else {
                    let nextParticipants = manager.nextParticipants(after: match.currentParticipant, in: match)
                    match.message = "Your turn in \(AppInfo.name)."
                    match.endTurn(
                        withNextParticipants: nextParticipants,
                        turnTimeout: Self.turnTimeLimit,
                        match: data
                    ) { error in
                        Task { @MainActor in
                            if let error {
                                manager.state = .error(error.localizedDescription)
                                manager.statusMessage = "Unable to send turn: \(error.localizedDescription)"
                            } else {
                                manager.isLocalPlayersTurn = false
                                manager.state = .inMatch
                                manager.statusMessage = "Waiting for \(manager.opponentName)."
                                // The opponent is on the clock now, and this
                                // side watches it run: their device forfeits
                                // itself if it is still awake, and this timer
                                // is the backstop for when it isn't.
                                manager.startTurnClock(isLocal: false)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The player deliberately walking out — the confirmation sheet, or the
    /// app going to the background. Their side is recorded as a quit, which
    /// is what reaches the opponent as "they left the game".
    func leaveCurrentMatch() {
        quitCurrentMatch(outcome: .quit, statusMessage: "Online match left.")
    }

    /// Detaches from the current match and records `outcome` against the local
    /// player. The outcome is what the far side reads to tell walking out from
    /// running down the clock, so it isn't always `.quit`.
    private func quitCurrentMatch(outcome: GKTurnBasedMatch.Outcome, statusMessage message: String) {
        guard let matchID = currentMatchID else { return }

        stopTurnClock()

        if let simulator {
            cancelSimulation()
            simulator.note("Local player left the match.")
        } else {
            quitWithGameCenter(matchID: matchID, outcome: outcome)
        }

        abandonedMatchIDs.insert(matchID)
        currentMatchID = nil
        localPlayerSide = nil
        isLocalPlayersTurn = false
        pendingUpdate = nil
        state = canStartMatch ? .ready : .signedOut
        statusMessage = message
    }

    private func quitWithGameCenter(matchID: String, outcome: GKTurnBasedMatch.Outcome) {
        GKTurnBasedMatch.load(withID: matchID) { [weak self] match, _ in
            guard let manager = self else { return }
            Task { @MainActor in
                guard let match else { return }

                if manager.isCurrentParticipant(match.currentParticipant) {
                    let nextParticipants = match.participants.filter { $0 != match.currentParticipant && $0.status != .done }
                    match.participantQuitInTurn(
                        with: outcome,
                        nextParticipants: nextParticipants,
                        turnTimeout: Self.turnTimeLimit,
                        match: match.matchData ?? Data()
                    ) { _ in }
                } else {
                    match.participantQuitOutOfTurn(with: outcome) { _ in }
                }
            }
        }
    }

    /// The app is being closed or sent to the background. A session here is
    /// live — there is a minute on the clock — so leaving the app leaves the
    /// match, and the opponent is told rather than left staring at a board
    /// nobody is going to move.
    func handleAppDidEnterBackground() {
        guard isInActiveMatch else { return }
        quitCurrentMatch(outcome: .quit, statusMessage: "Online match left.")
    }

    /// A match that played itself out. Nothing is left to leave, forfeit, or
    /// time out, so the session is closed here — but `localPlayerSide` stays,
    /// because the end-game screen and the achievement report both still need
    /// to know which side of the finished board was this player's.
    private func concludeMatch(_ matchID: String) {
        stopTurnClock()
        abandonedMatchIDs.insert(matchID)
        currentMatchID = nil
        isLocalPlayersTurn = false
    }

    // MARK: Simulated matches (development only)

    /// Stands a local stand-in up in place of Game Center and opens a session
    /// against it. Everything from here on rejoins the shipping path: the
    /// board hears about it through `applyInbound`, the same funnel a real
    /// turn event uses.
    private func startSimulatedMatch() {
        cancelSimulation()

        let simulator = self.simulator ?? OnlineMatchSimulator()
        self.simulator = simulator

        let matchID = "SIM-\(UUID().uuidString.prefix(8))"
        let localSide = OnlineDevMenu.settings.localSeat.side
        localPlayerSide = localSide
        opponentName = OnlineDevMenu.opponentName
        simulator.startMatch(localSide: localSide)

        // An empty payload is how a match nobody has moved in yet arrives, and
        // it is what the board reads as the start of a session.
        let opponentOpens = simulator.side == .playerOne
        applyInbound(
            matchID: matchID,
            payload: nil,
            isLocalTurn: !opponentOpens,
            isEnded: false,
            deadline: Date().addingTimeInterval(Self.turnTimeLimit),
            ending: nil,
            didBecomeActive: true
        )

        guard opponentOpens else { return }
        runSimulation(matchID: matchID) { await simulator.openingTurn() }
    }

    private func sendSimulatedTurn(_ data: Data, matchID: String, isGameOver: Bool) {
        guard let simulator else { return }

        isLocalPlayersTurn = false
        state = .inMatch

        if isGameOver {
            statusMessage = "Online match ended."
            concludeMatch(matchID)
            return
        }

        statusMessage = "Waiting for \(opponentName)."
        startTurnClock(isLocal: false)
        runSimulation(matchID: matchID) { await simulator.respond(to: data) }
    }

    private func runSimulation(matchID: String, _ reply: @escaping () async -> OnlineMatchSimulator.Reply) {
        simulationTask = Task { @MainActor [weak self] in
            let reply = await reply()
            guard !Task.isCancelled, let self, self.currentMatchID == matchID else { return }
            self.applySimulated(reply, matchID: matchID)
        }
    }

    private func applySimulated(_ reply: OnlineMatchSimulator.Reply, matchID: String) {
        switch reply {
        case .silent:
            // Nothing comes back on purpose; the clock is left to run out,
            // which is the behaviour being tested.
            break

        case .left:
            applyInbound(
                matchID: matchID,
                payload: nil,
                isLocalTurn: false,
                isEnded: false,
                deadline: Date(),
                ending: .opponentLeft(opponentName),
                didBecomeActive: false
            )

        case .moved(let data, let isGameOver):
            applyInbound(
                matchID: matchID,
                payload: try? JSONDecoder().decode(OnlineMatchPayload.self, from: data),
                isLocalTurn: !isGameOver,
                isEnded: isGameOver,
                deadline: Date().addingTimeInterval(Self.turnTimeLimit),
                ending: nil,
                didBecomeActive: false
            )
        }
    }

    /// Drops the far device out of the session on the spot, for testing the
    /// notice without waiting for a turn to come round.
    func simulateOpponentLeaving() {
        guard let matchID = currentMatchID, let simulator else { return }
        cancelSimulation()
        simulator.note("Opponent left (forced from the dev panel).")
        applyInbound(
            matchID: matchID,
            payload: nil,
            isLocalTurn: false,
            isEnded: false,
            deadline: Date(),
            ending: .opponentLeft(opponentName),
            didBecomeActive: false
        )
    }

    /// Pulls the clock in to a few seconds from now, so the forfeit paths can
    /// be watched without sitting through a full minute.
    func expireTurnClockSoon(in seconds: TimeInterval = 3) {
        guard isInActiveMatch, turnDeadline != nil else { return }
        startTurnClock(deadline: Date().addingTimeInterval(seconds), isLocal: isLocalTurnClock)
    }

    private func cancelSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
    }

    // MARK: Turn clock

    private func startTurnClock(isLocal: Bool) {
        startTurnClock(deadline: Date().addingTimeInterval(Self.turnTimeLimit), isLocal: isLocal)
    }

    private func startTurnClock(deadline: Date, isLocal: Bool) {
        turnClockTask?.cancel()
        turnDeadline = deadline
        isLocalTurnClock = isLocal

        // The waiting side gives the opponent's own device a moment to report
        // its forfeit before calling the timeout itself.
        let expiry = deadline.addingTimeInterval(isLocal ? 0 : Self.opponentTimeoutGrace)
        turnClockTask = Task { @MainActor [weak self] in
            let wait = expiry.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled, let self else { return }
            // A turn may have changed hands while this was sleeping.
            guard let current = self.turnDeadline, current == deadline else { return }
            self.handleTurnClockExpiry(isLocal: isLocal)
        }
    }

    private func stopTurnClock() {
        turnClockTask?.cancel()
        turnClockTask = nil
        turnDeadline = nil
        isLocalTurnClock = false
    }

    private func handleTurnClockExpiry(isLocal: Bool) {
        guard isInActiveMatch else { return }

        if isLocal {
            // `.timeExpired` rather than `.quit`, so the opponent is told the
            // clock ran out rather than that this player walked off.
            quitCurrentMatch(outcome: .timeExpired, statusMessage: "You ran out of time.")
            matchEnding = .localTimedOut
        } else {
            // The opponent's own device forfeits itself the moment its clock
            // runs out; reaching here means it never got the chance — it was
            // closed, or it lost the network. Claiming the win is the only
            // move available out of turn.
            let name = opponentName
            quitCurrentMatch(outcome: .won, statusMessage: "\(name) ran out of time.")
            matchEnding = .opponentTimedOut(name)
        }
    }

    // MARK: Inbound match events

    private func handle(match: GKTurnBasedMatch, didBecomeActive: Bool) {
        // A match this device already left still sends its own quit back; none
        // of what follows applies to it.
        guard !abandonedMatchIDs.contains(match.matchID) else { return }

        applyMatchMetadata(match)

        let payload = decodePayload(from: match)

        applyInbound(
            matchID: match.matchID,
            payload: payload,
            isLocalTurn: isCurrentParticipant(match.currentParticipant),
            isEnded: match.status == .ended,
            deadline: deadline(from: match),
            ending: ending(for: match, payload: payload),
            didBecomeActive: didBecomeActive
        )
    }

    /// Everything an inbound match update does to this manager, with no
    /// GameKit in it. `handle(match:)` reads a `GKTurnBasedMatch` down to these
    /// arguments; the dev simulator produces the same arguments from a local
    /// stand-in. Both go through here, so the simulated path can't quietly
    /// drift away from the one that ships.
    private func applyInbound(
        matchID: String,
        payload: OnlineMatchPayload?,
        isLocalTurn: Bool,
        isEnded: Bool,
        deadline: Date,
        ending: OnlineMatchEnding?,
        didBecomeActive: Bool
    ) {
        if let ending {
            stopTurnClock()
            cancelSimulation()
            // Done with this one, so a repeat event can't re-raise the notice.
            abandonedMatchIDs.insert(matchID)
            currentMatchID = nil
            localPlayerSide = nil
            isLocalPlayersTurn = false
            pendingUpdate = nil
            state = canStartMatch ? .ready : .signedOut
            statusMessage = ending.message
            matchEnding = ending
            return
        }

        currentMatchID = matchID
        matchEnding = nil
        state = .inMatch

        pendingUpdate = OnlineMatchUpdate(
            matchID: matchID,
            payload: payload,
            isNewMatch: payload == nil
        )
        updateVersion &+= 1

        if isEnded {
            statusMessage = "Online match ended."
            concludeMatch(matchID)
        } else if isLocalTurn {
            isLocalPlayersTurn = true
            statusMessage = didBecomeActive ? "Your turn." : "Your turn against \(opponentName)."
            startTurnClock(deadline: deadline, isLocal: true)
        } else {
            isLocalPlayersTurn = false
            statusMessage = "Waiting for \(opponentName)."
            startTurnClock(deadline: deadline, isLocal: false)
        }
    }

    /// Game Center's own timeout date for the side on the clock when it has
    /// one, so both devices count down to the same instant; a fresh minute
    /// otherwise.
    private func deadline(from match: GKTurnBasedMatch) -> Date {
        let fallback = Date().addingTimeInterval(Self.turnTimeLimit)
        guard let timeoutDate = match.currentParticipant?.timeoutDate else { return fallback }
        // A match created with the week-long default carries a timeout far
        // outside this game's minute; treat anything past it as absent.
        guard timeoutDate > Date(), timeoutDate.timeIntervalSinceNow <= Self.turnTimeLimit else { return fallback }
        return timeoutDate
    }

    /// Reads a walked-out opponent off the match. A match that ended because
    /// somebody won carries a finished board in its payload; one that ended
    /// with an opponent marked quit or timed out, and no finished board, is
    /// somebody leaving.
    private func ending(for match: GKTurnBasedMatch, payload: OnlineMatchPayload?) -> OnlineMatchEnding? {
        if payload?.game.game.isGameOver == true { return nil }

        let localID = GKLocalPlayer.local.gamePlayerID
        let opponents = match.participants.filter { $0.player?.gamePlayerID != localID }
        guard let opponent = opponents.first(where: { $0.matchOutcome == .quit || $0.matchOutcome == .timeExpired })
            ?? opponents.first(where: { $0.status == .done }) else {
            return nil
        }

        let name = opponent.player?.displayName ?? opponentName
        return opponent.matchOutcome == .timeExpired ? .opponentTimedOut(name) : .opponentLeft(name)
    }

    private func decodePayload(from match: GKTurnBasedMatch) -> OnlineMatchPayload? {
        guard let data = match.matchData, !data.isEmpty,
              let payload = try? JSONDecoder().decode(OnlineMatchPayload.self, from: data),
              payload.version <= OnlineMatchPayload.currentVersion,
              payload.game.pits.count == 14 else {
            return nil
        }

        return payload
    }

    private func applyMatchMetadata(_ match: GKTurnBasedMatch) {
        let activeParticipants = match.participants.filter { $0.status != .done }
        if let localIndex = activeParticipants.firstIndex(where: { $0.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID }) {
            localPlayerSide = localIndex == 0 ? .playerOne : .playerTwo
        } else if let localIndex = match.participants.firstIndex(where: { $0.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID }) {
            localPlayerSide = localIndex == 0 ? .playerOne : .playerTwo
        } else {
            localPlayerSide = nil
        }

        opponentName = match.participants
            .compactMap { $0.player }
            .first { $0.gamePlayerID != GKLocalPlayer.local.gamePlayerID }?
            .displayName ?? "Opponent"
    }

    private func gamePlayerID(for player: Player) -> String? {
        guard localPlayerSide == player else { return nil }
        return GKLocalPlayer.local.gamePlayerID
    }

    private func isCurrentParticipant(_ participant: GKTurnBasedParticipant?) -> Bool {
        participant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
    }

    private func nextParticipants(after currentParticipant: GKTurnBasedParticipant?, in match: GKTurnBasedMatch) -> [GKTurnBasedParticipant] {
        let activeParticipants = match.participants.filter { $0.status != .done }
        guard activeParticipants.count > 1 else { return activeParticipants }
        guard let currentParticipant,
              let currentIndex = activeParticipants.firstIndex(of: currentParticipant) else {
            return activeParticipants
        }

        let nextIndex = (currentIndex + 1) % activeParticipants.count
        return Array(activeParticipants[nextIndex..<activeParticipants.count]) + Array(activeParticipants[0..<nextIndex])
    }

    private func applyOutcomes(to match: GKTurnBasedMatch, game: MancalaGame) {
        for participant in match.participants {
            guard let side = side(for: participant, in: match) else {
                participant.matchOutcome = .none
                continue
            }

            if game.isDraw {
                participant.matchOutcome = .tied
            } else if game.winner == side {
                participant.matchOutcome = .won
            } else {
                participant.matchOutcome = .lost
            }
        }
    }

    private func side(for participant: GKTurnBasedParticipant, in match: GKTurnBasedMatch) -> Player? {
        guard let index = match.participants.firstIndex(of: participant) else { return nil }
        return index == 0 ? .playerOne : .playerTwo
    }

    private func present(_ viewController: Any) {
        #if os(macOS)
        state = .unavailable("Game Center presentation is available on iPhone and iPad in this version.")
        statusMessage = "Game Center presentation is available on iPhone and iPad in this version."
        #elseif canImport(UIKit)
        guard let presenter = rootViewController(),
              let viewController = viewController as? UIViewController else {
            state = .error("Unable to present Game Center.")
            statusMessage = "Unable to present Game Center."
            return
        }
        presenter.present(viewController, animated: true)
        #endif
    }

    private func dismiss(_ viewController: Any) {
        #if os(macOS)
        return
        #elseif canImport(UIKit)
        (viewController as? UIViewController)?.dismiss(animated: true)
        #endif
    }

    #if canImport(UIKit)
    private func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMostPresentedViewController
    }
    #endif
}

extension GameCenterMultiplayerManager: GKTurnBasedMatchmakerViewControllerDelegate {
    nonisolated func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
        Task { @MainActor in
            dismiss(viewController)
            state = canStartMatch ? .ready : .signedOut
            statusMessage = "Online matchmaking cancelled."
        }
    }

    nonisolated func turnBasedMatchmakerViewController(_ viewController: GKTurnBasedMatchmakerViewController, didFailWithError error: Error) {
        Task { @MainActor in
            dismiss(viewController)
            state = .error(error.localizedDescription)
            statusMessage = "Game Center error: \(error.localizedDescription)"
        }
    }

    nonisolated func turnBasedMatchmakerViewController(_ viewController: GKTurnBasedMatchmakerViewController, playerQuitFor match: GKTurnBasedMatch) {
        Task { @MainActor in
            handle(match: match, didBecomeActive: false)
        }
    }
}

extension GameCenterMultiplayerManager: GKLocalPlayerListener {
    nonisolated func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        Task { @MainActor in
            handle(match: match, didBecomeActive: didBecomeActive)
        }
    }

    /// The far side quitting arrives here rather than as a turn event when it
    /// leaves nobody to play on.
    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        Task { @MainActor in
            handle(match: match, didBecomeActive: false)
        }
    }

    nonisolated func player(_ player: GKPlayer, didRequestMatchWithOtherPlayers playersToInvite: [GKPlayer]) {
        Task { @MainActor in
            let request = GKMatchRequest()
            request.minPlayers = 2
            request.maxPlayers = 2
            request.recipients = playersToInvite
            let viewController = GKTurnBasedMatchmakerViewController(matchRequest: request)
            viewController.turnBasedMatchmakerDelegate = self
            present(viewController)
        }
    }
}

#if canImport(UIKit)
private extension UIViewController {
    var topMostPresentedViewController: UIViewController {
        presentedViewController?.topMostPresentedViewController ?? self
    }
}
#endif
