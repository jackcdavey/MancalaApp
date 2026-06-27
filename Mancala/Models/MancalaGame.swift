import Foundation

struct CaptureMove {
    let landingIndex: Int
    let oppositeIndex: Int
    let storeIndex: Int
    let capturedStones: Int
}

struct MancalaGame {
    private(set) var pits: [Int] = [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0]
    private(set) var currentPlayer: Player = .playerOne
    private(set) var winner: Player?
    private(set) var isDraw = false

    let playerOnePitIndices = Array(0...5)
    let playerTwoPitIndices = Array(7...12)

    init(
        pits: [Int] = [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0],
        currentPlayer: Player = .playerOne,
        winner: Player? = nil,
        isDraw: Bool = false
    ) {
        self.pits = pits.count == 14 ? pits : [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0]
        self.currentPlayer = currentPlayer
        self.winner = winner
        self.isDraw = isDraw
    }

    var isGameOver: Bool {
        winner != nil || isDraw
    }

    var statusText: String {
        if isDraw {
            return "Draw game"
        }

        if let winner {
            return "\(winner.name) wins"
        }

        return "\(currentPlayer.name)'s turn"
    }

    mutating func reset(startingPlayer: Player = .playerOne) {
        pits = [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0]
        currentPlayer = startingPlayer
        winner = nil
        isDraw = false
    }

    func canPlayPit(at index: Int) -> Bool {
        !isGameOver && playablePits(for: currentPlayer).contains(index) && pits[index] > 0
    }

    func legalPits(for player: Player) -> [Int] {
        guard !isGameOver, currentPlayer == player else { return [] }
        return playablePits(for: player).filter { pits[$0] > 0 }
    }

    func owner(ofPitAt index: Int) -> Player {
        playerOnePitIndices.contains(index) ? .playerOne : .playerTwo
    }

    func storeCount(for player: Player) -> Int {
        pits[storeIndex(for: player)]
    }

    func storeIndex(for player: Player) -> Int {
        switch player {
        case .playerOne: 6
        case .playerTwo: 13
        }
    }

    func sowingPath(from selectedIndex: Int) -> [Int] {
        guard canPlayPit(at: selectedIndex) else { return [] }

        var stones = pits[selectedIndex]
        var index = selectedIndex
        var path: [Int] = []

        while stones > 0 {
            index = (index + 1) % pits.count
            if index == storeIndex(for: currentPlayer.opponent) {
                continue
            }

            path.append(index)
            stones -= 1
        }

        return path
    }

    mutating func beginAnimatedMove(from selectedIndex: Int) {
        guard canPlayPit(at: selectedIndex) else { return }
        pits[selectedIndex] = 0
    }

    mutating func depositStone(at index: Int) {
        pits[index] += 1
    }

    mutating func removeStone(at index: Int) {
        guard pits.indices.contains(index), pits[index] > 0 else { return }
        pits[index] -= 1
    }

    func captureMove(afterLandingAt lastIndex: Int) -> CaptureMove? {
        guard playablePits(for: currentPlayer).contains(lastIndex), pits[lastIndex] == 1 else { return nil }

        let oppositeIndex = 12 - lastIndex
        let capturedStones = pits[oppositeIndex]
        guard capturedStones > 0 else { return nil }

        return CaptureMove(
            landingIndex: lastIndex,
            oppositeIndex: oppositeIndex,
            storeIndex: storeIndex(for: currentPlayer),
            capturedStones: capturedStones
        )
    }

    mutating func finishAnimatedMove(lastIndex: Int, captureAlreadyApplied: Bool = false) {
        if !captureAlreadyApplied {
            captureIfNeeded(lastIndex: lastIndex)
        }
        finishTurn(lastIndex: lastIndex)
    }

    mutating func playPit(at selectedIndex: Int) {
        guard canPlayPit(at: selectedIndex) else { return }

        let path = sowingPath(from: selectedIndex)
        pits[selectedIndex] = 0
        for index in path {
            pits[index] += 1
        }

        if let lastIndex = path.last {
            finishAnimatedMove(lastIndex: lastIndex)
        }
    }

    private mutating func captureIfNeeded(lastIndex: Int) {
        guard playablePits(for: currentPlayer).contains(lastIndex), pits[lastIndex] == 1 else { return }

        let oppositeIndex = 12 - lastIndex
        let capturedStones = pits[oppositeIndex]
        guard capturedStones > 0 else { return }

        pits[oppositeIndex] = 0
        pits[lastIndex] = 0
        pits[storeIndex(for: currentPlayer)] += capturedStones + 1
    }

    private mutating func finishTurn(lastIndex: Int) {
        if sideIsEmpty(.playerOne) || sideIsEmpty(.playerTwo) {
            collectRemainingStones()
            updateWinner()
            return
        }

        if lastIndex != storeIndex(for: currentPlayer) {
            currentPlayer = currentPlayer.opponent
        }
    }

    private func playablePits(for player: Player) -> [Int] {
        switch player {
        case .playerOne: playerOnePitIndices
        case .playerTwo: playerTwoPitIndices
        }
    }

    private func sideIsEmpty(_ player: Player) -> Bool {
        playablePits(for: player).allSatisfy { pits[$0] == 0 }
    }

    private mutating func collectRemainingStones() {
        for player in [Player.playerOne, Player.playerTwo] {
            let remaining = playablePits(for: player).reduce(0) { $0 + pits[$1] }
            pits[storeIndex(for: player)] += remaining
            for index in playablePits(for: player) {
                pits[index] = 0
            }
        }
    }

    private mutating func updateWinner() {
        let playerOneScore = storeCount(for: .playerOne)
        let playerTwoScore = storeCount(for: .playerTwo)

        if playerOneScore == playerTwoScore {
            isDraw = true
        } else {
            winner = playerOneScore > playerTwoScore ? .playerOne : .playerTwo
        }
    }
}
