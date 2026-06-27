import SwiftUI
import Playgrounds

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var game = MancalaGame()
    @State private var cellFrames: [Int: CGRect] = [:]
    @State private var flyingStone: FlyingStone?
    @State private var isAnimatingMove = false
    @State private var hapticTrigger = 0

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        GeometryReader { geometry in
            let isPortrait = geometry.size.height > geometry.size.width
            let verticalPadding: CGFloat = isPortrait ? 8 : 20
            let availableHeight = geometry.size.height - (verticalPadding * 2)

            ZStack {
                background

                if isPortrait {
                    gameContent(isPortrait: true, availableHeight: availableHeight)
                        .padding(.horizontal, 16)
                        .padding(.vertical, verticalPadding)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    gameContent(isPortrait: false, availableHeight: availableHeight)
                        .padding(verticalPadding)
                        .frame(maxWidth: 980)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: hapticTrigger)
    }

    private var background: some View {
        LinearGradient(
            colors: isDarkMode ? darkBackgroundColors : lightBackgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var lightBackgroundColors: [Color] {
        [
            Color(red: 0.93, green: 0.97, blue: 1.00),
            Color(red: 0.82, green: 0.90, blue: 0.96),
            Color(red: 0.92, green: 0.90, blue: 0.84)
        ]
    }

    private var darkBackgroundColors: [Color] {
        [
            Color(red: 0.06, green: 0.08, blue: 0.11),
            Color(red: 0.10, green: 0.14, blue: 0.19),
            Color(red: 0.16, green: 0.15, blue: 0.12)
        ]
    }

    private var primaryText: Color {
        isDarkMode ? .white : Color(red: 0.08, green: 0.10, blue: 0.12)
    }

    private var secondaryText: Color {
        primaryText.opacity(isDarkMode ? 0.72 : 0.64)
    }

    private var boardTint: Color {
        isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.30)
    }

    private var pitTint: Color {
        isDarkMode ? Color.white.opacity(0.07) : Color.white.opacity(0.22)
    }

    private var playableTint: Color {
        isDarkMode ? Color.cyan.opacity(0.20) : Color.blue.opacity(0.18)
    }

    private var storeTint: Color {
        isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.24)
    }

    private var currentStoreTint: Color {
        isDarkMode ? Color.green.opacity(0.22) : Color.green.opacity(0.18)
    }

    private var quietStroke: Color {
        isDarkMode ? Color.white.opacity(0.18) : Color.black.opacity(0.16)
    }

    private var strongStroke: Color {
        isDarkMode ? Color.cyan.opacity(0.58) : Color.blue.opacity(0.56)
    }

    private func gameContent(isPortrait: Bool, availableHeight: CGFloat) -> some View {
        let contentSpacing: CGFloat = isPortrait ? 10 : 18
        let headerHeight: CGFloat = isPortrait ? 76 : 64
        let statusHeight: CGFloat = isPortrait ? 46 : 0
        let visibleStatusSpacing = isPortrait ? contentSpacing : 0
        let boardHeight = max(260, availableHeight - headerHeight - statusHeight - contentSpacing - visibleStatusSpacing)
        let portraitStoreHeight = min(54, max(38, boardHeight * 0.10))
        let portraitPitHeight = max(34, (boardHeight - 24 - 20 - (portraitStoreHeight * 2) - 40) / 6)

        return VStack(spacing: contentSpacing) {
            header(isPortrait: isPortrait)
                .frame(height: headerHeight)

            GlassEffectContainer(spacing: 16) {
                if isPortrait {
                    portraitBoard(pitHeight: portraitPitHeight, storeHeight: portraitStoreHeight)
                } else {
                    wideBoard
                }
            }
            .frame(height: isPortrait ? boardHeight : nil)
            .coordinateSpace(name: "BoardSpace")
            .overlayPreferenceValue(CellFramePreferenceKey.self) { preferences in
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateCellFrames(preferences, proxy: proxy)
                        }
                        .onChange(of: preferences) { _, newValue in
                            updateCellFrames(newValue, proxy: proxy)
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                if let flyingStone {
                    animatedStone(flyingStone)
                }
            }

            if isPortrait {
                statusPanel
                    .frame(height: statusHeight)
            }
        }
    }

    private func header(isPortrait: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Mancala")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                Text("\(game.storeCount(for: .playerOne)) - \(game.storeCount(for: .playerTwo))")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(secondaryText)
            }

            Spacer()

            if !isPortrait {
                statusPanel
                    .frame(maxWidth: 260)

                Spacer()
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    game.reset()
                    flyingStone = nil
                    isAnimatingMove = false
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .disabled(isAnimatingMove)
            .accessibilityLabel("Reset game")
        }
    }

    private var wideBoard: some View {
        HStack(spacing: 14) {
            storeView(owner: .playerTwo, compact: false)
                .frame(width: 128)
                .recordCellFrame(id: game.storeIndex(for: .playerTwo))

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(Array(game.playerTwoPitIndices.reversed()), id: \.self) { index in
                        pitButton(index: index, minHeight: 126)
                    }
                }

                HStack(spacing: 10) {
                    ForEach(game.playerOnePitIndices, id: \.self) { index in
                        pitButton(index: index, minHeight: 126)
                    }
                }
            }

            storeView(owner: .playerOne, compact: false)
                .frame(width: 128)
                .recordCellFrame(id: game.storeIndex(for: .playerOne))
        }
        .padding(14)
        .glassEffect(.regular.tint(boardTint).interactive(), in: .rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(quietStroke, lineWidth: 1)
        }
    }

    private func portraitBoard(pitHeight: CGFloat, storeHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            storeView(owner: .playerTwo, compact: true)
                .frame(height: storeHeight)
                .recordCellFrame(id: game.storeIndex(for: .playerTwo))

            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 8) {
                    ForEach(Array(game.playerTwoPitIndices.reversed()), id: \.self) { index in
                        pitButton(index: index, minHeight: pitHeight)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(game.playerOnePitIndices, id: \.self) { index in
                        pitButton(index: index, minHeight: pitHeight)
                    }
                }
            }

            storeView(owner: .playerOne, compact: true)
                .frame(height: storeHeight)
                .recordCellFrame(id: game.storeIndex(for: .playerOne))
        }
        .padding(12)
        .glassEffect(.regular.tint(boardTint).interactive(), in: .rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(quietStroke, lineWidth: 1)
        }
    }

    private var statusPanel: some View {
        Text(game.statusText)
            .font(.headline.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .glassEffect(.regular.tint(storeTint), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(quietStroke, lineWidth: 1)
            }
            .contentTransition(.numericText())
    }

    private func pitButton(index: Int, minHeight: CGFloat) -> some View {
        let owner = game.owner(ofPitAt: index)
        let isPlayable = game.canPlayPit(at: index) && !isAnimatingMove
        let isCompactPit = minHeight < 92
        let contentSpacing = isCompactPit ? max(2, minHeight * 0.04) : 5
        let verticalInset = isCompactPit ? max(3, minHeight * 0.07) : 8
        let clusterHeight = isCompactPit ? min(28, max(16, minHeight * 0.25)) : 46
        let countSize = isCompactPit ? min(22, max(17, minHeight * 0.27)) : 27

        return Button {
            Task {
                await animateMove(from: index)
            }
        } label: {
            VStack(spacing: contentSpacing) {
                Text(owner.shortName)
                    .font(.system(size: isCompactPit ? 11 : 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryText)

                stoneCluster(count: game.pits[index])
                    .frame(height: clusterHeight)

                Text("\(game.pits[index])")
                    .font(.system(size: countSize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(primaryText)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, verticalInset)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight)
            .glassEffect(.regular.tint(isPlayable ? playableTint : pitTint).interactive(isPlayable), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isPlayable ? strongStroke : quietStroke, lineWidth: isPlayable ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isPlayable)
        .recordCellFrame(id: index)
        .accessibilityLabel("\(owner.name) pit with \(game.pits[index]) stones")
    }

    @ViewBuilder
    private func storeView(owner: Player, compact: Bool) -> some View {
        let isCurrent = owner == game.currentPlayer && !game.isGameOver
        let tint = isCurrent ? currentStoreTint : storeTint
        let stroke = isCurrent ? Color.green.opacity(isDarkMode ? 0.60 : 0.54) : quietStroke

        if compact {
            HStack(spacing: 12) {
                Text(owner.shortName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryText)
                    .frame(width: 28)

                stoneCluster(count: game.storeCount(for: owner))
                    .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 38)

                Text("\(game.storeCount(for: owner))")
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(primaryText)
                    .frame(width: 48)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14)
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(stroke, lineWidth: isCurrent ? 1.5 : 1)
            }
        } else {
            VStack(spacing: 7) {
                Text(owner.shortName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryText)

                stoneCluster(count: game.storeCount(for: owner))
                    .frame(height: 48)

                Text("\(game.storeCount(for: owner))")
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(primaryText)
                    .contentTransition(.numericText())
            }
            .frame(minHeight: 148)
            .padding(10)
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(stroke, lineWidth: isCurrent ? 1.5 : 1)
            }
        }
    }

    private func stoneCluster(count: Int) -> some View {
        ZStack {
            ForEach(0..<min(count, 18), id: \.self) { index in
                Circle()
                    .fill(stoneColor(for: index).gradient)
                    .frame(width: 11, height: 11)
                    .offset(stoneOffset(for: index))
                    .shadow(color: isDarkMode ? .black.opacity(0.30) : .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: count)
    }

    private func animatedStone(_ stone: FlyingStone) -> some View {
        Circle()
            .fill(stoneColor(for: stone.colorIndex).gradient)
            .frame(width: 18, height: 18)
            .shadow(color: isDarkMode ? .black.opacity(0.42) : .black.opacity(0.24), radius: 5, x: 0, y: 3)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(isDarkMode ? 0.32 : 0.46), lineWidth: 1)
            }
            .position(stone.position)
            .allowsHitTesting(false)
    }

    @MainActor
    private func animateMove(from selectedIndex: Int) async {
        guard game.canPlayPit(at: selectedIndex), !isAnimatingMove else { return }

        let path = game.sowingPath(from: selectedIndex)
        guard let sourceFrame = cellFrames[selectedIndex], !path.isEmpty else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                game.playPit(at: selectedIndex)
            }
            return
        }

        isAnimatingMove = true
        game.beginAnimatedMove(from: selectedIndex)
        var currentPoint = sourceFrame.center

        for (step, destination) in path.enumerated() {
            guard let destinationFrame = cellFrames[destination] else { continue }
            let destinationPoint = destinationFrame.center

            flyingStone = FlyingStone(position: currentPoint, colorIndex: step)
            try? await Task.sleep(for: .milliseconds(35))

            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                flyingStone?.position = destinationPoint
            }

            try? await Task.sleep(for: .milliseconds(150))

            withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                game.depositStone(at: destination)
                hapticTrigger += 1
                flyingStone = nil
            }

            currentPoint = destinationPoint
            try? await Task.sleep(for: .milliseconds(30))
        }

        let lastIndex = path[path.count - 1]
        let animatedCapture = await animateCaptureIfNeeded(lastIndex: lastIndex)

        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            game.finishAnimatedMove(lastIndex: lastIndex, captureAlreadyApplied: animatedCapture)
            isAnimatingMove = false
        }
    }

    @MainActor
    private func animateCaptureIfNeeded(lastIndex: Int) async -> Bool {
        guard let capture = game.captureMove(afterLandingAt: lastIndex),
              let storeFrame = cellFrames[capture.storeIndex] else {
            return false
        }

        let capturedSources = [capture.landingIndex] + Array(repeating: capture.oppositeIndex, count: capture.capturedStones)
        let storePoint = storeFrame.center
        guard capturedSources.allSatisfy({ cellFrames[$0] != nil }) else {
            return false
        }

        for (step, sourceIndex) in capturedSources.enumerated() {
            let sourceFrame = cellFrames[sourceIndex, default: .zero]
            let sourcePoint = sourceFrame.center

            withAnimation(.spring(response: 0.18, dampingFraction: 0.80)) {
                game.removeStone(at: sourceIndex)
            }

            flyingStone = FlyingStone(position: sourcePoint, colorIndex: step + 2)
            try? await Task.sleep(for: .milliseconds(20))

            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                flyingStone?.position = storePoint
            }

            try? await Task.sleep(for: .milliseconds(95))

            withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                game.depositStone(at: capture.storeIndex)
                hapticTrigger += 1
                flyingStone = nil
            }

            try? await Task.sleep(for: .milliseconds(12))
        }

        return true
    }

    private func updateCellFrames(_ preferences: [Int: Anchor<CGRect>], proxy: GeometryProxy) {
        cellFrames = preferences.mapValues { proxy[$0] }
    }

    private func stoneColor(for index: Int) -> Color {
        let colors = [
            Color(red: 0.13, green: 0.42, blue: 0.92),
            Color(red: 0.95, green: 0.55, blue: 0.16),
            Color(red: 0.14, green: 0.62, blue: 0.56),
            Color(red: 0.84, green: 0.22, blue: 0.34),
            Color(red: 0.55, green: 0.42, blue: 0.86)
        ]
        return colors[index % colors.count]
    }

    private func stoneOffset(for index: Int) -> CGSize {
        let offsets = [
            CGSize(width: -16, height: -10), CGSize(width: 0, height: -14), CGSize(width: 16, height: -9),
            CGSize(width: -8, height: 1), CGSize(width: 9, height: 1), CGSize(width: -17, height: 11),
            CGSize(width: 1, height: 14), CGSize(width: 18, height: 10), CGSize(width: -2, height: -1)
        ]
        let base = offsets[index % offsets.count]
        let layer = CGFloat(index / offsets.count) * 2.2
        return CGSize(width: base.width + layer, height: base.height - layer)
    }
}

private struct FlyingStone: Equatable {
    var position: CGPoint
    let colorIndex: Int
}

private struct CaptureMove {
    let landingIndex: Int
    let oppositeIndex: Int
    let storeIndex: Int
    let capturedStones: Int
}

private enum Player: Equatable {
    case playerOne
    case playerTwo

    var name: String {
        switch self {
        case .playerOne: "Player 1"
        case .playerTwo: "Player 2"
        }
    }

    var shortName: String {
        switch self {
        case .playerOne: "P1"
        case .playerTwo: "P2"
        }
    }

    var opponent: Player {
        switch self {
        case .playerOne: .playerTwo
        case .playerTwo: .playerOne
        }
    }
}

private struct MancalaGame {
    private(set) var pits: [Int] = [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0]
    private(set) var currentPlayer: Player = .playerOne
    private(set) var winner: Player?
    private(set) var isDraw = false

    let playerOnePitIndices = Array(0...5)
    let playerTwoPitIndices = Array(7...12)

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

    mutating func reset() {
        pits = [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0]
        currentPlayer = .playerOne
        winner = nil
        isDraw = false
    }

    func canPlayPit(at index: Int) -> Bool {
        !isGameOver && playablePits(for: currentPlayer).contains(index) && pits[index] > 0
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

private struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private extension View {
    func recordCellFrame(id: Int) -> some View {
        anchorPreference(key: CellFramePreferenceKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
