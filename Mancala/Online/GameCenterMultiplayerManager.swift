import Foundation
import GameKit
import Observation
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct OnlineMatchPayload: Codable {
    static let currentVersion = 1

    let version: Int
    let game: SavedGameState
    let lastMoveIndex: Int?
    let playerOneName: String
    let playerTwoName: String
    let playerOneGamePlayerID: String?
    let playerTwoGamePlayerID: String?

    init(
        game: MancalaGame,
        lastMoveIndex: Int?,
        playerOneName: String,
        playerTwoName: String,
        playerOneGamePlayerID: String?,
        playerTwoGamePlayerID: String?
    ) {
        version = Self.currentVersion
        self.game = SavedGameState(game: game)
        self.lastMoveIndex = lastMoveIndex
        self.playerOneName = playerOneName
        self.playerTwoName = playerTwoName
        self.playerOneGamePlayerID = playerOneGamePlayerID
        self.playerTwoGamePlayerID = playerTwoGamePlayerID
    }
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

    private(set) var state: ConnectionState = .signedOut
    private(set) var currentMatchID: String?
    private(set) var localPlayerSide: Player?
    private(set) var isLocalPlayersTurn = false
    private(set) var opponentName = "Opponent"
    private(set) var statusMessage = "Sign in to Game Center to play online."
    private(set) var pendingPayload: OnlineMatchPayload?
    private(set) var pendingRemoteMoveIndex: Int?

    var isAuthenticated: Bool {
        GKLocalPlayer.local.isAuthenticated
    }

    var canStartMatch: Bool {
        isAuthenticated && !isMultiplayerRestricted
    }

    var isMultiplayerRestricted: Bool {
        GKLocalPlayer.local.isMultiplayerGamingRestricted
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
        guard canStartMatch else {
            statusMessage = isAuthenticated ? "Multiplayer is restricted for this account." : "Sign in to Game Center first."
            return
        }

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.inviteMessage = "Play Mancala with me."

        let viewController = GKTurnBasedMatchmakerViewController(matchRequest: request)
        viewController.turnBasedMatchmakerDelegate = self
        viewController.showExistingMatches = true
        state = .matching
        statusMessage = "Choose an opponent in Game Center."
        present(viewController)
    }

    func clearPendingPayload() {
        pendingPayload = nil
        pendingRemoteMoveIndex = nil
    }

    func noteLocalExtraTurn() {
        isLocalPlayersTurn = true
        statusMessage = "Extra turn."
    }

    func sendTurn(
        game: MancalaGame,
        lastMoveIndex: Int,
        playerOneName: String,
        playerTwoName: String
    ) {
        guard let matchID = currentMatchID else {
            state = .error("No active online match.")
            statusMessage = "No active online match."
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
                    lastMoveIndex: lastMoveIndex,
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
                                manager.isLocalPlayersTurn = false
                                manager.state = .inMatch
                                manager.statusMessage = "Online match ended."
                            }
                        }
                    }
                } else {
                    let nextParticipants = manager.nextParticipants(after: match.currentParticipant, in: match)
                    match.message = "Your turn in Mancala."
                    match.endTurn(
                        withNextParticipants: nextParticipants,
                        turnTimeout: GKTurnTimeoutDefault,
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
                            }
                        }
                    }
                }
            }
        }
    }

    func forfeitCurrentMatch() {
        guard let matchID = currentMatchID else { return }

        GKTurnBasedMatch.load(withID: matchID) { [weak self] match, _ in
            guard let manager = self else { return }
            Task { @MainActor in
                guard let match else { return }

                if manager.isCurrentParticipant(match.currentParticipant) {
                    let nextParticipants = match.participants.filter { $0 != match.currentParticipant && $0.status != .done }
                    match.participantQuitInTurn(
                        with: .quit,
                        nextParticipants: nextParticipants,
                        turnTimeout: GKTurnTimeoutDefault,
                        match: match.matchData ?? Data()
                    ) { _ in }
                } else {
                    match.participantQuitOutOfTurn(with: .quit) { _ in }
                }

                manager.currentMatchID = nil
                manager.localPlayerSide = nil
                manager.isLocalPlayersTurn = false
                manager.state = manager.canStartMatch ? .ready : .signedOut
                manager.statusMessage = "Online match left."
            }
        }
    }

    private func handle(match: GKTurnBasedMatch, didBecomeActive: Bool) {
        currentMatchID = match.matchID
        applyMatchMetadata(match)
        decodePayload(from: match)
        state = .inMatch

        if match.status == .ended {
            isLocalPlayersTurn = false
            statusMessage = "Online match ended."
        } else if isCurrentParticipant(match.currentParticipant) {
            isLocalPlayersTurn = true
            statusMessage = didBecomeActive ? "Your turn." : "Your turn against \(opponentName)."
        } else {
            isLocalPlayersTurn = false
            statusMessage = "Waiting for \(opponentName)."
        }
    }

    private func decodePayload(from match: GKTurnBasedMatch) {
        guard let data = match.matchData, !data.isEmpty,
              let payload = try? JSONDecoder().decode(OnlineMatchPayload.self, from: data),
              payload.version <= OnlineMatchPayload.currentVersion,
              payload.game.pits.count == 14 else {
            pendingPayload = nil
            pendingRemoteMoveIndex = nil
            return
        }

        pendingPayload = payload
        pendingRemoteMoveIndex = payload.lastMoveIndex
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
        state = .unavailable("Online matchmaking is available on iPhone and iPad in this version.")
        statusMessage = "Online matchmaking is available on iPhone and iPad in this version."
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
            statusMessage = "A player left the online match."
        }
    }
}

extension GameCenterMultiplayerManager: GKLocalPlayerListener {
    nonisolated func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        Task { @MainActor in
            handle(match: match, didBecomeActive: didBecomeActive)
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
