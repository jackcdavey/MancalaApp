import Foundation

/// What one device hands the other when it finishes a turn: the board it
/// arrived at, and the run of sows that got it there.
///
/// Foundation only — no GameKit, no SwiftUI. It is the whole contract between
/// the two devices, so it is kept somewhere the headless checks can compile
/// (see `Scripts/verify-online-replay.swift`).
struct OnlineMatchPayload: Codable {
    static let currentVersion = 2

    let version: Int
    let game: SavedGameState
    let lastMoveIndex: Int?
    /// Every pit the sender sowed during the turn they just handed over, in
    /// order. A turn can be several sows long — landing in your own store
    /// earns another — and the receiver replays the whole run so the stones
    /// are seen moving rather than teleporting. Optional so a version-1
    /// payload from an older build still decodes; `moves` falls back to
    /// `lastMoveIndex` in that case.
    let moveIndices: [Int]?
    let playerOneName: String
    let playerTwoName: String
    let playerOneGamePlayerID: String?
    let playerTwoGamePlayerID: String?

    /// The sender's sow sequence, however the payload spelled it.
    var moves: [Int] {
        if let moveIndices, !moveIndices.isEmpty {
            return moveIndices
        }
        return lastMoveIndex.map { [$0] } ?? []
    }

    init(
        game: MancalaGame,
        moveIndices: [Int],
        playerOneName: String,
        playerTwoName: String,
        playerOneGamePlayerID: String?,
        playerTwoGamePlayerID: String?
    ) {
        version = Self.currentVersion
        self.game = SavedGameState(game: game)
        self.lastMoveIndex = moveIndices.last
        self.moveIndices = moveIndices
        self.playerOneName = playerOneName
        self.playerTwoName = playerTwoName
        self.playerOneGamePlayerID = playerOneGamePlayerID
        self.playerTwoGamePlayerID = playerTwoGamePlayerID
    }
}

extension MancalaGame {
    /// Whether `moves` can be replayed from this board, as `player`, and land
    /// on exactly `expected`.
    ///
    /// The one gate on animating an opponent's turn instead of snapping to its
    /// result. Animating from a board that has drifted would walk the stones
    /// somewhere plausible but wrong, and a desynced board is worse than an
    /// unanimated one — so the run is rehearsed on a copy, and anything that
    /// doesn't reproduce the sender's board exactly is refused before the
    /// board on screen moves at all.
    func canReplay(_ moves: [Int], as player: Player, arrivingAt expected: MancalaGame) -> Bool {
        guard !moves.isEmpty, !isGameOver else { return false }

        var rehearsal = self
        for move in moves {
            guard rehearsal.owner(ofPitAt: move) == player,
                  rehearsal.canPlayPit(at: move) else {
                return false
            }
            rehearsal.playPit(at: move)
        }

        return rehearsal.matches(expected)
    }

    /// Board-for-board equality: the same stones in the same wells, the same
    /// side to move, the same result.
    func matches(_ other: MancalaGame) -> Bool {
        pits == other.pits
            && currentPlayer == other.currentPlayer
            && winner == other.winner
            && isDraw == other.isDraw
    }
}
