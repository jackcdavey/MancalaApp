import SwiftUI

struct ContentView: View {
    private static let defaultImpossibleSearchLimit = 10_000_000
    private static let defaultImpossibleTimeLimit = 10

    @Environment(\.colorScheme) private var colorScheme
    @State private var game = MancalaGame()
    @State private var cellFrames: [Int: CGRect] = [:]
    @State private var flyingStone: FlyingStone?
    @State private var isAnimatingMove = false
    @State private var hapticTrigger = 0
    @State private var endGameAnimationPulse = false
    @AppStorage("gameMode") private var gameMode = GameMode.twoPlayer
    @AppStorage("visualTheme") private var visualTheme = VisualTheme.liquidGlass
    @AppStorage("boardMaterialStyle") private var boardMaterialStyle = BoardMaterialStyle.walnut
    @AppStorage("gyroMotionEnabled") private var gyroMotionEnabled = true
    @AppStorage("stoneAnimationSpeed") private var stoneAnimationSpeed = 1.0
    @AppStorage("flipScreenForTwoPlayerTurns") private var flipScreenForTwoPlayerTurns = false
    @AppStorage("difficulty") private var difficulty = AIDifficulty.medium
    @AppStorage("zeroPlayerOneDifficulty") private var zeroPlayerOneDifficulty = AIDifficulty.medium
    @AppStorage("zeroPlayerTwoDifficulty") private var zeroPlayerTwoDifficulty = AIDifficulty.medium
    @AppStorage("startingPlayer") private var startingPlayer = StartingPlayer.human
    @AppStorage("singlePlayerUndoButtonEnabled") private var isSinglePlayerUndoButtonEnabled = false
    @AppStorage("twoPlayerUndoButtonEnabled") private var isTwoPlayerUndoButtonEnabled = false
    @AppStorage("singlePlayerShowNumberLabels") private var singlePlayerShowNumberLabels = true
    @AppStorage("twoPlayerShowNumberLabels") private var twoPlayerShowNumberLabels = true
    @AppStorage("zeroPlayerShowNumberLabels") private var zeroPlayerShowNumberLabels = true
    @AppStorage("onlineShowNumberLabels") private var onlineShowNumberLabels = true
    @AppStorage("singlePlayerOneName") private var singlePlayerOneName = "Player 1"
    @AppStorage("singlePlayerTwoName") private var singlePlayerTwoName = "Player 2"
    @AppStorage("twoPlayerOneName") private var twoPlayerOneName = "Player 1"
    @AppStorage("twoPlayerTwoName") private var twoPlayerTwoName = "Player 2"
    @AppStorage("zeroPlayerOneName") private var zeroPlayerOneName = "Player 1"
    @AppStorage("zeroPlayerTwoName") private var zeroPlayerTwoName = "Player 2"
    @AppStorage("onlinePlayerOneName") private var onlinePlayerOneName = "Player 1"
    @AppStorage("onlinePlayerTwoName") private var onlinePlayerTwoName = "Player 2"
    @AppStorage("playerOneName") private var legacyPlayerOneName = "Player 1"
    @AppStorage("playerTwoName") private var legacyPlayerTwoName = "Player 2"
    @AppStorage("modeSpecificPlayerNamesMigrated") private var modeSpecificPlayerNamesMigrated = false
    @State private var isSettingsPresented = false
    @State private var isGameHistoryPresented = false
    @State private var isRulesPresented = false
    @State private var hasRecordedCurrentCompletedGame = false
    @State private var undoHistory: [MancalaGame] = []
    @State private var isAIMovePending = false
    @State private var aiSearchGeneration = 0
    @State private var aiSearchTask: Task<Int?, Never>?
    @State private var isThoughtPanelExpanded = false
    @State private var aiThoughtLog: [String] = []
    @State private var isZeroPlayerPaused = true
    @State private var onlineManager = GameCenterMultiplayerManager()
    @AppStorage("impossibleSearchLimitMode") private var impossibleSearchLimitMode = ImpossibleSearchLimitMode.positions
    @AppStorage("impossibleSearchLimit") private var impossibleSearchLimit = ContentView.defaultImpossibleSearchLimit
    @AppStorage("impossibleSearchTimeLimit") private var impossibleSearchTimeLimit = ContentView.defaultImpossibleTimeLimit
    @State private var impossibleSearchProgress = 0.0
    @State private var impossibleSearchProgressText = ""
    @State private var hintedPitIndex: Int?
    @State private var isHintSearching = false
    @AppStorage("savedSinglePlayerGameState") private var savedSinglePlayerGameState = Data()
    @AppStorage("savedTwoPlayerGameState") private var savedTwoPlayerGameState = Data()
    @AppStorage("savedZeroPlayerGameState") private var savedZeroPlayerGameState = Data()
    @AppStorage("savedOnlineGameState") private var savedOnlineGameState = Data()
    @AppStorage("completedGameHistory") private var completedGameHistoryData = Data()
    @AppStorage("savedGameState") private var legacySavedGameState = Data()
    #if os(visionOS)
    @Environment(SpatialBoardModel.self) private var spatialBoard
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #else
    @State private var boardScene = BoardScene()
    @State private var motionParallax = MotionParallaxController()
    #endif

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        GeometryReader { geometry in
            let isPortrait = geometry.size.height > geometry.size.width
            let verticalPadding: CGFloat = isPortrait ? 8 : 10
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

                if game.isGameOver {
                    endGamePopup
                        .padding(.horizontal, 24)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .zIndex(4)
                }
            }
        }
        .environment(\.mancalaVisualTheme, visualTheme)
        .environment(\.mancalaBoardFlipped, tableRotationDegrees == 180)
        .animation(.spring(response: 0.44, dampingFraction: 0.78), value: game.isGameOver)
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        .sheet(isPresented: $isSettingsPresented) {
            settingsSheet
        }
        .sheet(isPresented: $isGameHistoryPresented) {
            gameHistorySheet
        }
        .sheet(isPresented: $isRulesPresented) {
            rulesSheet
        }
        .onAppear {
            migratePlayerNamesIfNeeded()
            restoreSavedGameIfNeeded()
            onlineManager.authenticateLocalPlayer()
        }
        #if os(visionOS)
        .task {
            spatialBoard.scene.onPitTapped = { index in
                Task { await animateMove(from: index) }
            }
            // The 3D theme lives in the room on visionOS; open the board
            // volume on launch. If the user closes it, `isOpen` goes false
            // and the window shows the 2D board instead.
            if visualTheme == .liquidGlass {
                setSpatialBoard(open: true)
            }
        }
        .onChange(of: spatialSyncState, initial: true) { _, _ in
            syncSpatialBoard()
        }
        .onChange(of: visualTheme) { _, theme in
            setSpatialBoard(open: theme == .liquidGlass)
        }
        #endif
        .onChange(of: onlineManager.currentMatchID) { _, _ in
            applyPendingOnlineMatchIfNeeded()
        }
        .onChange(of: onlineManager.pendingRemoteMoveIndex) { _, _ in
            applyPendingOnlineMatchIfNeeded()
        }
        .onChange(of: game.isGameOver) { _, isGameOver in
            guard isGameOver else {
                endGameAnimationPulse = false
                return
            }

            hapticTrigger += 1
            endGameAnimationPulse = false
            withAnimation(.easeInOut(duration: 0.78).repeatForever(autoreverses: true)) {
                endGameAnimationPulse = true
            }
        }
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
        if visualTheme == .calligraphy {
            return [.white, .white]
        }

        return [
            Color(red: 0.97, green: 0.97, blue: 0.98),
            Color(red: 0.91, green: 0.91, blue: 0.93),
            Color(red: 0.85, green: 0.86, blue: 0.88)
        ]
    }

    private var darkBackgroundColors: [Color] {
        if visualTheme == .calligraphy {
            return [.white, .white]
        }

        return [
            Color(red: 0.05, green: 0.05, blue: 0.06),
            Color(red: 0.09, green: 0.09, blue: 0.11),
            Color(red: 0.13, green: 0.13, blue: 0.16)
        ]
    }

    private var primaryText: Color {
        if visualTheme == .calligraphy {
            return .black
        }
        return isDarkMode ? .white : Color(red: 0.08, green: 0.10, blue: 0.12)
    }

    private var secondaryText: Color {
        primaryText.opacity(visualTheme == .calligraphy ? 0.58 : (isDarkMode ? 0.72 : 0.64))
    }

    private var boardTint: Color {
        if visualTheme == .calligraphy {
            return .white
        }
        return isDarkMode ? Color.white.opacity(0.09) : Color.white.opacity(0.62)
    }

    private var pitTint: Color {
        if visualTheme == .calligraphy {
            return .white
        }
        return isDarkMode ? Color.white.opacity(0.07) : Color.white.opacity(0.22)
    }

    private var playableTint: Color {
        if visualTheme == .calligraphy {
            return .white
        }
        return isDarkMode ? Color.cyan.opacity(0.14) : Color.blue.opacity(0.10)
    }

    private var storeTint: Color {
        if visualTheme == .calligraphy {
            return .white
        }
        return isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.24)
    }

    private var currentStoreTint: Color {
        if visualTheme == .calligraphy {
            return .white
        }
        return isDarkMode ? Color.green.opacity(0.16) : Color.green.opacity(0.10)
    }

    private func displayFont(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: visualTheme == .calligraphy ? .serif : .rounded)
    }

    private func countFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        displayFont(size: size, weight: weight).monospacedDigit()
    }

    private var isAIPlayAvailable: Bool {
        true
    }

    private var shouldShowStatusPanel: Bool {
        gameMode == .singlePlayer || gameMode == .zeroPlayer || gameMode == .onlineMultiplayer
    }

    private var shouldShowUndoButton: Bool {
        switch gameMode {
        case .singlePlayer:
            isSinglePlayerUndoButtonEnabled
        case .twoPlayer:
            isTwoPlayerUndoButtonEnabled
        case .zeroPlayer, .onlineMultiplayer:
            false
        }
    }

    private var canUndoTurn: Bool {
        guard shouldShowUndoButton, !isAnimatingMove else { return false }

        switch gameMode {
        case .singlePlayer:
            return undoHistory.contains { $0.currentPlayer == .playerOne }
        case .twoPlayer:
            return !undoHistory.isEmpty
        case .zeroPlayer, .onlineMultiplayer:
            return false
        }
    }

    private var tableRotationDegrees: Double {
        gameMode == .twoPlayer && flipScreenForTwoPlayerTurns && game.currentPlayer == .playerTwo && !game.isGameOver ? 180 : 0
    }

    private var boardTiltDegrees: Double {
        guard visualTheme == .liquidGlass else { return 0 }
        return tableRotationDegrees == 180 ? -22 : 22
    }

    /// The default theme renders as a real RealityKit board: in-window on
    /// iOS/macOS, anchored to a real surface via the immersive space on
    /// visionOS. On visionOS this is only "active" while the space is open —
    /// if the user closes it, the window falls back to the 2D board.
    private var is3DBoardActive: Bool {
        #if os(visionOS)
        return visualTheme == .liquidGlass && spatialBoard.isOpen
        #else
        return visualTheme == .liquidGlass
        #endif
    }

    /// The scene that stone-flight animations should target, when one is live.
    private var activeBoardScene: BoardScene? {
        #if os(visionOS)
        return spatialBoard.isOpen ? spatialBoard.scene : nil
        #else
        return is3DBoardActive ? boardScene : nil
        #endif
    }

    /// Pits the local player may tap right now; mirrors `pitButton`'s
    /// enablement predicate for the 3D board's highlight rings.
    private var playablePitSet: Set<Int> {
        guard !isAnimatingMove, !isAIMovePending else { return [] }
        return Set((0..<14).filter { game.canPlayPit(at: $0) && canHumanPlayPit(at: $0) })
    }

    private var shouldShowNumberLabels: Bool {
        switch gameMode {
        case .singlePlayer:
            singlePlayerShowNumberLabels
        case .twoPlayer:
            twoPlayerShowNumberLabels
        case .zeroPlayer:
            zeroPlayerShowNumberLabels
        case .onlineMultiplayer:
            onlineShowNumberLabels
        }
    }

    private var impossibleSearchLimitBinding: Binding<Int> {
        Binding(
            get: { impossibleSearchLimit },
            set: { impossibleSearchLimit = min(max($0, 100_000), 100_000_000) }
        )
    }

    private var impossibleSearchTimeLimitBinding: Binding<Int> {
        Binding(
            get: { impossibleSearchTimeLimit },
            set: { impossibleSearchTimeLimit = min(max($0, 1), 120) }
        )
    }

    private var currentPlayerOneNameBinding: Binding<String> {
        Binding(
            get: { playerName(for: .playerOne, in: gameMode) },
            set: { setPlayerName($0, for: .playerOne, in: gameMode) }
        )
    }

    private var currentPlayerTwoNameBinding: Binding<String> {
        Binding(
            get: { playerName(for: .playerTwo, in: gameMode) },
            set: { setPlayerName($0, for: .playerTwo, in: gameMode) }
        )
    }

    private func playerName(for player: Player, in mode: GameMode) -> String {
        switch (mode, player) {
        case (.singlePlayer, .playerOne):
            singlePlayerOneName
        case (.singlePlayer, .playerTwo):
            singlePlayerTwoName
        case (.twoPlayer, .playerOne):
            twoPlayerOneName
        case (.twoPlayer, .playerTwo):
            twoPlayerTwoName
        case (.zeroPlayer, .playerOne):
            zeroPlayerOneName
        case (.zeroPlayer, .playerTwo):
            zeroPlayerTwoName
        case (.onlineMultiplayer, .playerOne):
            onlinePlayerOneName
        case (.onlineMultiplayer, .playerTwo):
            onlinePlayerTwoName
        }
    }

    private func setPlayerName(_ name: String, for player: Player, in mode: GameMode) {
        switch (mode, player) {
        case (.singlePlayer, .playerOne):
            singlePlayerOneName = name
        case (.singlePlayer, .playerTwo):
            singlePlayerTwoName = name
        case (.twoPlayer, .playerOne):
            twoPlayerOneName = name
        case (.twoPlayer, .playerTwo):
            twoPlayerTwoName = name
        case (.zeroPlayer, .playerOne):
            zeroPlayerOneName = name
        case (.zeroPlayer, .playerTwo):
            zeroPlayerTwoName = name
        case (.onlineMultiplayer, .playerOne):
            onlinePlayerOneName = name
        case (.onlineMultiplayer, .playerTwo):
            onlinePlayerTwoName = name
        }
    }

    private func displayName(for player: Player) -> String {
        let defaultName = player == .playerOne ? "Player 1" : "Player 2"
        let storedName = playerName(for: player, in: gameMode)
        let trimmedName = storedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? defaultName : trimmedName
    }

    private func migratePlayerNamesIfNeeded() {
        guard !modeSpecificPlayerNamesMigrated else { return }

        singlePlayerOneName = legacyPlayerOneName
        singlePlayerTwoName = legacyPlayerTwoName
        twoPlayerOneName = legacyPlayerOneName
        twoPlayerTwoName = legacyPlayerTwoName
        zeroPlayerOneName = legacyPlayerOneName
        zeroPlayerTwoName = legacyPlayerTwoName
        onlinePlayerOneName = legacyPlayerOneName
        onlinePlayerTwoName = legacyPlayerTwoName
        modeSpecificPlayerNamesMigrated = true
    }

    private func aiDifficulty(for player: Player) -> AIDifficulty {
        switch gameMode {
        case .singlePlayer:
            difficulty
        case .zeroPlayer:
            player == .playerOne ? zeroPlayerOneDifficulty : zeroPlayerTwoDifficulty
        case .twoPlayer, .onlineMultiplayer:
            difficulty
        }
    }

    private var currentAIDifficulty: AIDifficulty {
        aiDifficulty(for: game.currentPlayer)
    }

    private func isAIControlled(_ player: Player) -> Bool {
        switch gameMode {
        case .zeroPlayer:
            true
        case .singlePlayer:
            player == .playerTwo
        case .twoPlayer, .onlineMultiplayer:
            false
        }
    }

    private var endGameTitle: String {
        if game.isDraw {
            return "Draw Game"
        }

        guard let winner = game.winner else {
            return "Game Over"
        }

        if gameMode == .singlePlayer {
            return winner == .playerOne ? "You Win" : "You Lose"
        }

        if gameMode == .onlineMultiplayer {
            return winner == onlineManager.localPlayerSide ? "You Win" : "You Lose"
        }

        return "\(displayName(for: winner)) Wins"
    }

    private var endGameSubtitle: String {
        "\(game.storeCount(for: .playerOne)) - \(game.storeCount(for: .playerTwo))"
    }

    private var endGameSymbolName: String {
        if game.isDraw {
            return "equal.circle.fill"
        }

        if gameMode == .singlePlayer, let winner = game.winner {
            return winner == .playerOne ? "crown.fill" : "flag.checkered"
        }

        if gameMode == .onlineMultiplayer, let winner = game.winner {
            return winner == onlineManager.localPlayerSide ? "crown.fill" : "flag.checkered"
        }

        return "crown.fill"
    }

    private var statusText: String {
        if gameMode == .onlineMultiplayer, !game.isGameOver {
            return onlineManager.statusMessage
        }

        if game.isDraw {
            return "Draw game"
        }

        if let winner = game.winner {
            return "\(displayName(for: winner)) wins"
        }

        if gameMode == .zeroPlayer && isZeroPlayerPaused {
            return "Paused • \(displayName(for: game.currentPlayer))'s turn"
        }

        return "\(displayName(for: game.currentPlayer))'s turn"
    }

    private var startingPlayerDescription: String {
        if gameMode == .zeroPlayer {
            switch startingPlayer {
            case .human:
                return "\(displayName(for: .playerOne)) starts."
            case .ai:
                return "\(displayName(for: .playerTwo)) starts."
            case .random:
                return "A starting side is chosen each time the game resets."
            }
        }

        switch startingPlayer {
        case .human:
            return "\(displayName(for: .playerOne)) makes the first move."
        case .ai:
            return "\(displayName(for: .playerTwo)) opens."
        case .random:
            return "A starting side is chosen each time the game resets."
        }
    }

    private func startingPlayerTitle(for startingPlayer: StartingPlayer) -> String {
        if gameMode == .zeroPlayer {
            switch startingPlayer {
            case .human:
                return "Player 1"
            case .ai:
                return "Player 2"
            case .random:
                return "Random"
            }
        }

        return startingPlayer.title
    }

    private var modelAvailabilityMessage: String? {
        if #available(iOS 27.0, *) {
            return FoundationModelAIMoveProvider.availabilityMessage
        }
        return "AI play uses local heuristics on iOS 26."
    }

    private func gameContent(isPortrait: Bool, availableHeight: CGFloat) -> some View {
        let contentSpacing: CGFloat = isPortrait ? 10 : 18
        let headerHeight: CGFloat = isPortrait ? 76 : (shouldShowStatusPanel && isThoughtPanelExpanded ? 172 : 64)
        let statusHeight: CGFloat = isPortrait && shouldShowStatusPanel ? (isThoughtPanelExpanded ? 172 : 46) : 0
        let visibleStatusSpacing = isPortrait && shouldShowStatusPanel ? contentSpacing : 0
        let slabClearance: CGFloat = visualTheme == .liquidGlass && !is3DBoardActive ? 42 : 0
        let boardHeight = max(260, availableHeight - headerHeight - statusHeight - contentSpacing - visibleStatusSpacing - slabClearance)
        let portraitStoreHeight = min(54, max(38, boardHeight * 0.10))
        let portraitPitHeight = max(34, (boardHeight - 24 - 20 - (portraitStoreHeight * 2) - 40) / 6)

        return VStack(spacing: contentSpacing) {
            header(isPortrait: isPortrait)
                .frame(height: headerHeight)

            if is3DBoardActive {
                #if os(visionOS)
                spatialBoardPlaceholder(boardHeight: boardHeight)
                #else
                board3DSection(isPortrait: isPortrait, boardHeight: boardHeight)
                    // Break out of `gameContent`'s horizontal inset so the board
                    // spans the full screen width and can travel to the real
                    // edges when parallax tilts it (header/status stay inset).
                    .padding(.horizontal, isPortrait ? -16 : -10)
                #endif
            } else {
                boardContainer {
                    if isPortrait {
                        portraitBoard(pitHeight: portraitPitHeight, storeHeight: portraitStoreHeight)
                    } else {
                        wideBoard
                    }
                }
                .padding(.horizontal, visualTheme == .liquidGlass ? (isPortrait ? 30 : 48) : 0)
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
                .rotation3DEffect(
                    .degrees(boardTiltDegrees),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.45
                )
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: boardTiltDegrees)
            }

            if isPortrait && shouldShowStatusPanel {
                statusPanel
                    .frame(height: statusHeight)
            }
        }
        .padding(.bottom, !isPortrait && visualTheme == .liquidGlass && !is3DBoardActive ? 30 : 0)
    }

    #if os(visionOS)
    /// Fills the window's board slot while the real board sits anchored out in
    /// the room; the window keeps score, status, and controls.
    private func spatialBoardPlaceholder(boardHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text("The board is placed in your space")
                .font(.headline)
                .foregroundStyle(primaryText)

            Text("Touch a pit — or look at it and pinch — to sow. Use the handle below the board to move it or snap it onto a surface.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button {
                setSpatialBoard(open: false)
            } label: {
                Label("Return Board to Window", systemImage: "arrow.down.forward.and.arrow.up.backward")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .frame(height: boardHeight)
    }

    /// Everything the anchored board mirrors, snapshotted so a single
    /// `onChange` can push updates into the shared scene.
    private var spatialSyncState: SpatialBoardSyncState {
        SpatialBoardSyncState(
            pits: game.pits,
            playable: playablePitSet,
            hinted: hintedPitIndex,
            currentStore: game.isGameOver ? nil : game.storeIndex(for: game.currentPlayer),
            showLabels: shouldShowNumberLabels,
            dark: isDarkMode,
            material: boardMaterialStyle
        )
    }

    private func syncSpatialBoard() {
        let state = spatialSyncState
        // No camera on visionOS, so flip/portrait/viewSize are inert.
        spatialBoard.scene.sync(
            pits: state.pits,
            playable: state.playable,
            hinted: state.hinted,
            currentStore: state.currentStore,
            flipped: false,
            portrait: false,
            viewSize: CGSize(width: 1, height: 1),
            showLabels: state.showLabels,
            dark: state.dark,
            material: state.material
        )
    }

    private func setSpatialBoard(open: Bool) {
        if open, !spatialBoard.isOpen {
            openWindow(id: SpatialBoardModel.windowID)
        } else if !open, spatialBoard.isOpen {
            dismissWindow(id: SpatialBoardModel.windowID)
        }
    }
    #else
    /// The RealityKit board used by the default theme. All surrounding
    /// chrome (header, status panel, popups) stays SwiftUI.
    private func board3DSection(isPortrait: Bool, boardHeight: CGFloat) -> some View {
        Board3DView(
            pits: game.pits,
            playablePits: playablePitSet,
            hintedPit: hintedPitIndex,
            currentStoreIndex: game.isGameOver ? nil : game.storeIndex(for: game.currentPlayer),
            flipped: tableRotationDegrees == 180,
            isPortrait: isPortrait,
            showLabels: shouldShowNumberLabels,
            isDarkMode: isDarkMode,
            boardMaterial: boardMaterialStyle,
            scene: boardScene
        )
        .frame(height: isPortrait ? boardHeight : nil)
        .frame(maxHeight: isPortrait ? nil : .infinity)
        .onAppear {
            boardScene.onPitTapped = { index in
                Task { await animateMove(from: index) }
            }
            if gyroMotionEnabled {
                startMotionParallax()
            }
        }
        .onDisappear {
            motionParallax.stop()
        }
        .onChange(of: gyroMotionEnabled) { _, enabled in
            if enabled {
                startMotionParallax()
            } else {
                motionParallax.stop()
                boardScene.setParallax(yaw: 0, pitch: 0)
            }
        }
    }

    private func startMotionParallax() {
        motionParallax.start { yaw, pitch in
            boardScene.setParallax(yaw: yaw, pitch: pitch)
        }
    }
    #endif

    /// The board renders its own frosted surfaces (no `glassEffect` inside),
    /// so it must not sit in a `GlassEffectContainer` — the container changes
    /// compositing on real hardware in ways the simulator doesn't reproduce.
    private func boardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
    }

    private var endGamePopup: some View {
        VStack(spacing: 18) {
            ZStack {
                ForEach(0..<10, id: \.self) { index in
                    Circle()
                        .fill(stoneColor(for: index).opacity(isDarkMode ? 0.82 : 0.92))
                        .frame(width: index.isMultiple(of: 2) ? 13 : 10, height: index.isMultiple(of: 2) ? 13 : 10)
                        .offset(endGameStoneOffset(for: index, expanded: endGameAnimationPulse))
                        .shadow(color: .black.opacity(isDarkMode ? 0.32 : 0.18), radius: 3, x: 0, y: 2)
                }

                Image(systemName: endGameSymbolName)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(game.isDraw ? Color.secondary : (visualTheme == .calligraphy ? Color.black : Color.yellow))
                    .scaleEffect(endGameAnimationPulse ? 1.08 : 0.96)
                    .shadow(color: .black.opacity(isDarkMode ? 0.34 : 0.16), radius: 8, x: 0, y: 4)
            }
            .frame(width: 126, height: 92)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(endGameTitle)
                    .font(displayFont(size: 34, weight: .bold))
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())

                Text(endGameSubtitle)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(secondaryText)
            }

            Button {
                playAgainFromEndGamePopup()
            } label: {
                Label(gameMode == .onlineMultiplayer ? "Play Again Online" : "Play Again", systemImage: "arrow.counterclockwise")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .mancalaGlassEffect(tint: playableTint, cornerRadius: 18, role: .control, interactive: true)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .mancalaGlassEffect(tint: storeTint, cornerRadius: 28, role: .panel, seed: 23)
        .shadow(color: .black.opacity(isDarkMode ? 0.36 : 0.18), radius: 24, x: 0, y: 18)
        .accessibilityElement(children: .contain)
    }

    private func endGameStoneOffset(for index: Int, expanded: Bool) -> CGSize {
        let angles = [0.0, 37.0, 76.0, 118.0, 162.0, 205.0, 248.0, 286.0, 318.0, 344.0]
        let baseRadius: CGFloat = 31
        let radius = baseRadius + (expanded ? CGFloat(index % 3) * 5 + 8 : CGFloat(index % 3) * 2)
        let radians = angles[index % angles.count] * .pi / 180
        return CGSize(width: cos(radians) * radius, height: sin(radians) * radius * 0.68)
    }

    private var difficultyPill: some View {
        let title: String
        let tint: Color
        let accessibilityLabel: String

        switch gameMode {
        case .singlePlayer:
            title = difficulty.title
            tint = difficulty.tint
            accessibilityLabel = "Difficulty: \(difficulty.title)"
        case .zeroPlayer:
            title = "\(zeroPlayerOneDifficulty.title) vs \(zeroPlayerTwoDifficulty.title)"
            tint = currentAIDifficulty.tint
            accessibilityLabel = "Zero player mode. Player 1 \(zeroPlayerOneDifficulty.title), Player 2 \(zeroPlayerTwoDifficulty.title)"
        case .twoPlayer:
            title = "2 Players"
            tint = Color.secondary
            accessibilityLabel = "Two player mode"
        case .onlineMultiplayer:
            title = "Online"
            tint = Color.indigo
            accessibilityLabel = "Online multiplayer mode"
        }

        return Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(visualTheme == .calligraphy ? Color.white : tint.opacity(isDarkMode ? 0.24 : 0.18))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        visualTheme == .calligraphy ? Color.black.opacity(0.65) : tint.opacity(isDarkMode ? 0.72 : 0.58),
                        lineWidth: 1
                    )
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private func header(isPortrait: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Mancala")
                    .font(displayFont(size: 34, weight: .semibold))
                    .foregroundStyle(primaryText)

                if visualTheme == .calligraphy {
                    InkDash()
                        .fill(Color.black.opacity(0.82))
                        .frame(width: 92, height: 5)
                        .padding(.bottom, 1)
                        .accessibilityHidden(true)
                }

                difficultyPill
            }
            .playerFacingRotation(tableRotationDegrees)

            Spacer()

            if !isPortrait && shouldShowStatusPanel {
                statusPanel
                    .frame(maxWidth: isThoughtPanelExpanded ? 360 : 260)

                Spacer()
            }

            if shouldShowUndoButton {
                Button {
                    undoLastTurn()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(primaryText)
                        .frame(width: 44, height: 44)
                        .playerFacingRotation(tableRotationDegrees)
                }
                .mancalaGlassButtonStyle()
                .disabled(!canUndoTurn)
                .accessibilityLabel("Undo last turn")
            }

            if gameMode == .zeroPlayer {
                Button {
                    toggleZeroPlayerPlayback()
                } label: {
                    Image(systemName: isZeroPlayerPaused ? "play.fill" : "pause.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(primaryText)
                        .frame(width: 44, height: 44)
                        .playerFacingRotation(tableRotationDegrees)
                }
                .mancalaGlassButtonStyle()
                .disabled(isAnimatingMove || game.isGameOver)
                .accessibilityLabel(isZeroPlayerPaused ? "Play zero player game" : "Pause zero player game")
            }

            #if os(visionOS)
            if visualTheme == .liquidGlass {
                Button {
                    setSpatialBoard(open: !spatialBoard.isOpen)
                } label: {
                    Image(systemName: spatialBoard.isOpen ? "arrow.down.forward.and.arrow.up.backward" : "cube")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(primaryText)
                        .frame(width: 44, height: 44)
                }
                .mancalaGlassButtonStyle()
                .accessibilityLabel(spatialBoard.isOpen ? "Return board to window" : "Place board in your space")
            }
            #endif

            Menu {
                Button {
                    isRulesPresented = true
                } label: {
                    Label("Rules", systemImage: "book.closed")
                }

                Button {
                    requestHint()
                } label: {
                    Label(isHintSearching ? "Finding Hint" : "Hint", systemImage: "lightbulb")
                }
                .disabled(!canRequestHint)

                Button {
                    isGameHistoryPresented = true
                } label: {
                    Label("Game History", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    isSettingsPresented = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                Button(role: .destructive) {
                    resetCurrentGame()
                } label: {
                    Label("Reset Game", systemImage: "arrow.counterclockwise")
                }
                .disabled(isAnimatingMove || gameMode == .onlineMultiplayer)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .frame(width: 44, height: 44)
                    .playerFacingRotation(tableRotationDegrees)
            }
            .mancalaGlassButtonStyle()
            .accessibilityLabel("More options")
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $visualTheme) {
                        ForEach(VisualTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(visualTheme == .calligraphy ? "Plain black and white, with hand-inked brushstrokes for the board and pits." : "A frosted glass board with depth, viewed at a slight angle.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if visualTheme == .liquidGlass {
                        Picker("Material", selection: $boardMaterialStyle) {
                            ForEach(BoardMaterialStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }

                        #if !os(visionOS)
                        Toggle("Motion Parallax", isOn: $gyroMotionEnabled)

                        Text("Tilts the board's perspective with your device's motion.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        #endif
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Pebble Speed")
                            Spacer()
                            Text(String(format: "%.1f×", stoneAnimationSpeed))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $stoneAnimationSpeed, in: 0.5...2.0, step: 0.1) {
                            Text("Pebble Speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }

                    Text("How quickly pebbles fly between pits.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Players") {
                    Picker("Mode", selection: $gameMode) {
                        Text("2 Players").tag(GameMode.twoPlayer)
                        Text("1 Player").tag(GameMode.singlePlayer)
                            .disabled(!isAIPlayAvailable)
                        Text("0 Player").tag(GameMode.zeroPlayer)
                            .disabled(!isAIPlayAvailable)
                        Text("Online").tag(GameMode.onlineMultiplayer)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: gameMode) { oldMode, newMode in
                        let resolvedMode: GameMode
                        if (newMode == .singlePlayer || newMode == .zeroPlayer), !isAIPlayAvailable {
                            resolvedMode = .twoPlayer
                            gameMode = .twoPlayer
                        } else {
                            resolvedMode = newMode
                        }

                        switchGameMode(from: oldMode, to: resolvedMode)
                    }

                    if let modelAvailabilityMessage {
                        Text(modelAvailabilityMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Names") {
                    TextField("Player 1", text: currentPlayerOneNameBinding)
                        .mancalaNameTextFieldStyle()

                    TextField("Player 2", text: currentPlayerTwoNameBinding)
                        .mancalaNameTextFieldStyle()

                    Text("Leave a field blank to use its default name.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if gameMode == .twoPlayer {
                    Section("Table") {
                        Toggle("Flip Screen Each Turn", isOn: $flipScreenForTwoPlayerTurns)

                        Text("Buttons and labels rotate to face the current player while the board layout stays in place.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Display") {
                        Toggle("Show Numbers", isOn: $twoPlayerShowNumberLabels)

                        Text("Shows the stone counts in each pit and store.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Undo") {
                        Toggle("Show Undo Button", isOn: $isTwoPlayerUndoButtonEnabled)
                            .onChange(of: isTwoPlayerUndoButtonEnabled) { _, newValue in
                                if !newValue {
                                    undoHistory.removeAll()
                                }
                            }

                        Text("Undo rolls back the last completed move.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Game Center") {
                    Text(onlineManager.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(onlineManager.isAuthenticated ? "View Achievements" : "Sign In to Game Center") {
                        if onlineManager.isAuthenticated {
                            onlineManager.showAchievements()
                        } else {
                            onlineManager.authenticateLocalPlayer()
                        }
                    }

                    if gameMode == .onlineMultiplayer {
                        Button(onlineManager.isAuthenticated ? "Start Online Match" : "Sign In to Game Center") {
                            if onlineManager.isAuthenticated {
                                onlineManager.startMatch()
                            } else {
                                onlineManager.authenticateLocalPlayer()
                            }
                        }
                        .disabled(onlineManager.isAuthenticated && !onlineManager.canStartMatch)

                        if onlineManager.currentMatchID != nil {
                            Button("Forfeit Online Match", role: .destructive) {
                                onlineManager.forfeitCurrentMatch()
                            }
                        }
                    }
                }

                if gameMode == .onlineMultiplayer {
                    Section("Display") {
                        Toggle("Show Numbers", isOn: $onlineShowNumberLabels)

                        Text("Shows the stone counts in each pit and store.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if gameMode == .singlePlayer || gameMode == .zeroPlayer {
                    Section("First Move") {
                        Picker("Starts", selection: $startingPlayer) {
                            ForEach(StartingPlayer.allCases) { startingPlayer in
                                Text(startingPlayerTitle(for: startingPlayer)).tag(startingPlayer)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: startingPlayer) { _, _ in
                            resetForSettingsChange()
                        }

                        Text(startingPlayerDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if gameMode == .singlePlayer {
                        Section("Difficulty") {
                            Picker("Skill", selection: $difficulty) {
                                ForEach(AIDifficulty.allCases) { difficulty in
                                    Text(difficulty.title).tag(difficulty)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: difficulty) { _, _ in
                                restartAIThinkingForUpdatedSettingsIfNeeded()
                            }

                            Text(difficulty.description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section("Player 1 Difficulty") {
                            Picker("Player 1 Skill", selection: $zeroPlayerOneDifficulty) {
                                ForEach(AIDifficulty.allCases) { difficulty in
                                    Text(difficulty.title).tag(difficulty)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: zeroPlayerOneDifficulty) { _, _ in
                                restartAIThinkingForUpdatedSettingsIfNeeded()
                            }

                            Text(zeroPlayerOneDifficulty.description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Section("Player 2 Difficulty") {
                            Picker("Player 2 Skill", selection: $zeroPlayerTwoDifficulty) {
                                ForEach(AIDifficulty.allCases) { difficulty in
                                    Text(difficulty.title).tag(difficulty)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: zeroPlayerTwoDifficulty) { _, _ in
                                restartAIThinkingForUpdatedSettingsIfNeeded()
                            }

                            Text(zeroPlayerTwoDifficulty.description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Display") {
                        Toggle(
                            "Show Numbers",
                            isOn: gameMode == .singlePlayer ? $singlePlayerShowNumberLabels : $zeroPlayerShowNumberLabels
                        )

                        Text("Shows the stone counts in each pit and store.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if gameMode == .singlePlayer {
                        Section("Undo") {
                            Toggle("Show Undo Button", isOn: $isSinglePlayerUndoButtonEnabled)
                                .onChange(of: isSinglePlayerUndoButtonEnabled) { _, newValue in
                                    if !newValue {
                                        undoHistory.removeAll()
                                    }
                                }

                            Text("Undo cancels AI thinking and rolls back the last player move, or rolls back the last player move plus the AI response.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if shouldShowImpossibleSearchSettings {
                        Section("Advanced") {
                            DisclosureGroup("Impossible Search") {
                                Picker("Limit by", selection: $impossibleSearchLimitMode) {
                                    ForEach(ImpossibleSearchLimitMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: impossibleSearchLimitMode) { _, _ in
                                    restartAIThinkingForUpdatedSettingsIfNeeded()
                                }

                                if impossibleSearchLimitMode == .positions {
                                    impossiblePositionsLimitStepper
                                } else {
                                    impossibleTimeLimitStepper
                                }

                                Text(impossibleSearchLimitMode.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .onChange(of: impossibleSearchLimit) { _, _ in
                                restartAIThinkingForUpdatedSettingsIfNeeded()
                            }
                            .onChange(of: impossibleSearchTimeLimit) { _, _ in
                                restartAIThinkingForUpdatedSettingsIfNeeded()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isSettingsPresented = false
                        Task {
                            await runAIMoveIfNeeded()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var impossiblePositionsLimitStepper: some View {
        Stepper(
            value: impossibleSearchLimitBinding,
            in: 100_000...100_000_000,
            step: 100_000
        ) {
            HStack {
                Text("Max positions")
                Spacer()
                TextField("Positions", value: impossibleSearchLimitBinding, format: .number)
                    .mancalaNumberTextFieldStyle(width: 136)
            }
        }
    }

    private var impossibleTimeLimitStepper: some View {
        Stepper(
            value: impossibleSearchTimeLimitBinding,
            in: 1...120,
            step: 1
        ) {
            HStack {
                Text("Max time")
                Spacer()
                TextField("Seconds", value: impossibleSearchTimeLimitBinding, format: .number)
                    .mancalaNumberTextFieldStyle(width: 82)
                Text("s")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shouldShowImpossibleSearchSettings: Bool {
        switch gameMode {
        case .singlePlayer:
            difficulty == .impossible
        case .zeroPlayer:
            zeroPlayerOneDifficulty == .impossible || zeroPlayerTwoDifficulty == .impossible
        case .twoPlayer, .onlineMultiplayer:
            false
        }
    }

    private var rulesSheet: some View {
        NavigationStack {
            List {
                Section("Goal") {
                    Text("Collect more stones in your store than your opponent by the end of the game.")
                }

                Section("Taking a Turn") {
                    Text("Choose one of your pits. All stones from that pit are picked up and dropped one at a time into following pits and your own store, moving counterclockwise around the board.")
                    Text("Your opponent's store is skipped.")
                }

                Section("Extra Turns") {
                    Text("If your last stone lands in your own store, you take another turn.")
                }

                Section("Captures") {
                    Text("If your last stone lands in an empty pit on your side, and the opposite pit has stones, you capture your stone plus the opposite stones into your store.")
                }

                Section("Ending the Game") {
                    Text("The game ends when all six pits on either side are empty. Any remaining stones move to their owner's store, and the higher score wins.")
                }
            }
            .navigationTitle("Rules")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isRulesPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var gameHistorySheet: some View {
        NavigationStack {
            List {
                let history = completedGameHistory
                if history.isEmpty {
                    ContentUnavailableView(
                        "No Completed Games",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finished games will appear here.")
                    )
                } else {
                    ForEach(history) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(result.winnerText)
                                    .font(.headline.weight(.semibold))
                                Spacer()
                                Text("\(result.playerOneScore) - \(result.playerTwoScore)")
                                    .font(.headline.monospacedDigit())
                            }

                            Text("\(result.playerOneName) vs \(result.playerTwoName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Game History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isGameHistoryPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var wideBoard: some View {
        HStack(spacing: 14) {
            storeView(owner: .playerTwo, compact: false)
                .frame(width: 128)
                .recordCellFrame(id: game.storeIndex(for: .playerTwo))

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(Array(game.playerTwoPitIndices.reversed()), id: \.self) { index in
                        pitButton(index: index, minHeight: 112)
                    }
                }

                HStack(spacing: 10) {
                    ForEach(game.playerOnePitIndices, id: \.self) { index in
                        pitButton(index: index, minHeight: 112)
                    }
                }
            }

            storeView(owner: .playerOne, compact: false)
                .frame(width: 128)
                .recordCellFrame(id: game.storeIndex(for: .playerOne))
        }
        .padding(14)
        .mancalaGlassEffect(tint: boardTint, cornerRadius: 28, role: .board, interactive: true, seed: 40)
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
        .mancalaGlassEffect(tint: boardTint, cornerRadius: 28, role: .board, interactive: true, seed: 41)
    }

    private var statusPanel: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isThoughtPanelExpanded.toggle()
            }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.headline.weight(.semibold))
                        .contentTransition(.numericText())

                    if isAIMovePending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(primaryText)
                            .accessibilityLabel("AI is thinking")
                    }

                    Image(systemName: isThoughtPanelExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .opacity(aiThoughtLog.isEmpty && !isAIMovePending ? 0.35 : 0.70)
                }

                if isThoughtPanelExpanded {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 4) {
                            if isAIMovePending && currentAIDifficulty == .impossible {
                                ProgressView(value: impossibleSearchProgress)
                                    .tint(primaryText)

                                Text(impossibleSearchProgressText)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(secondaryText)
                                    .fixedSize(horizontal: true, vertical: false)
                            }

                            ForEach(displayedThoughtLog, id: \.self) { entry in
                                Text(entry)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(secondaryText)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.automatic)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .playerFacingRotation(tableRotationDegrees)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(primaryText)
        .multilineTextAlignment(.center)
        .mancalaGlassEffect(tint: storeTint, cornerRadius: 18, role: .panel)
        .accessibilityHint("Tap to show or hide AI thinking details")
    }

    private var displayedThoughtLog: [String] {
        if aiThoughtLog.isEmpty {
            return isAIMovePending ? ["Preparing move search..."] : ["No AI thinking details yet."]
        }

        return Array(aiThoughtLog.suffix(5))
    }

    private func pitButton(index: Int, minHeight: CGFloat) -> some View {
        let owner = game.owner(ofPitAt: index)
        let isPlayable = game.canPlayPit(at: index) && !isAnimatingMove && !isAIMovePending && canHumanPlayPit(at: index)
        let isHinted = hintedPitIndex == index
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
            Group {
                if visualTheme == .liquidGlass {
                    stoneCluster(count: game.pits[index])
                        .frame(height: clusterHeight)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            if shouldShowNumberLabels {
                                Text("\(game.pits[index])")
                                    .font(countFont(size: countSize * 0.78))
                                    .foregroundStyle(secondaryText)
                                    .contentTransition(.numericText())
                            }
                        }
                } else {
                    VStack(spacing: contentSpacing) {
                        stoneCluster(count: game.pits[index])
                            .frame(height: clusterHeight)

                        if shouldShowNumberLabels {
                            Text("\(game.pits[index])")
                                .font(countFont(size: countSize))
                                .foregroundStyle(primaryText)
                                .contentTransition(.numericText())
                        }
                    }
                }
            }
            .playerFacingRotation(tableRotationDegrees)
            .padding(.vertical, verticalInset)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight)
            .contentShape(pitHitShape)
            .mancalaGlassEffect(tint: isPlayable ? playableTint : pitTint, cornerRadius: 20, role: .pit, interactive: isPlayable, seed: index)
            .overlay {
                if isHinted {
                    if visualTheme == .calligraphy {
                        InkRing(seed: index &+ 9, exponent: 2.0, weightFraction: 0.030)
                            .fill(Color.black.opacity(0.9), style: FillStyle(eoFill: true))
                            .padding(-6)
                            .transition(.opacity.combined(with: .scale(scale: 1.03)))
                            .allowsHitTesting(false)
                    } else {
                        Ellipse()
                            .stroke(Color.yellow.opacity(isDarkMode ? 0.94 : 0.88), lineWidth: 3)
                            .shadow(color: Color.yellow.opacity(0.82), radius: 12, x: 0, y: 0)
                            .shadow(color: Color.orange.opacity(0.42), radius: 22, x: 0, y: 0)
                            .transition(.opacity.combined(with: .scale(scale: 1.03)))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(pitHitShape)
        .disabled(!isPlayable)
        .recordCellFrame(id: index)
        .accessibilityLabel("\(displayName(for: owner)) pit with \(game.pits[index]) stones")
    }

    private var pitHitShape: AnyShape {
        visualTheme == .liquidGlass
            ? AnyShape(Ellipse())
            : AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var canRequestHint: Bool {
        gameMode != .zeroPlayer &&
        !game.isGameOver &&
        !isAnimatingMove &&
        !isAIMovePending &&
        !isHintSearching &&
        !game.legalPits(for: game.currentPlayer).isEmpty &&
        (gameMode != .onlineMultiplayer || onlineManager.isLocalPlayersTurn)
    }

    private func requestHint() {
        guard canRequestHint else { return }

        hintedPitIndex = nil
        isHintSearching = true
        let pitsSnapshot = game.pits
        let currentPlayer = game.currentPlayer == .playerOne ? 1 : 2
        let hintBudget = min(max(impossibleSearchLimit / 10, 100_000), 1_000_000)
        let hintTimeLimit = 2.0

        Task {
            let suggestedPit = await Task.detached(priority: .userInitiated) {
                MancalaOptimalSolver.bestMove(
                    pits: pitsSnapshot,
                    currentPlayer: currentPlayer,
                    maxPositions: hintBudget,
                    timeLimit: hintTimeLimit,
                    progress: { _ in },
                    progressUpdate: { _ in }
                )
            }.value

            guard let suggestedPit,
                  game.pits == pitsSnapshot,
                  game.currentPlayer == (currentPlayer == 1 ? .playerOne : .playerTwo),
                  game.canPlayPit(at: suggestedPit) else {
                isHintSearching = false
                return
            }

            withAnimation(.easeInOut(duration: 0.45)) {
                hintedPitIndex = suggestedPit
                isHintSearching = false
                hapticTrigger += 1
            }
        }
    }

    private func canHumanPlayPit(at index: Int) -> Bool {
        switch gameMode {
        case .twoPlayer:
            return true
        case .singlePlayer:
            return game.owner(ofPitAt: index) == .playerOne
        case .zeroPlayer:
            return false
        case .onlineMultiplayer:
            return onlineManager.isLocalPlayersTurn && game.owner(ofPitAt: index) == onlineManager.localPlayerSide
        }
    }

    private func recordUndoSnapshotIfNeeded() {
        guard shouldShowUndoButton else { return }
        undoHistory.append(game)
        if undoHistory.count > 24 {
            undoHistory.removeFirst(undoHistory.count - 24)
        }
    }

    @MainActor
    private func undoLastTurn() {
        guard canUndoTurn else { return }

        let wasThinking = isAIMovePending || aiSearchTask != nil
        let restoreIndex: Int?
        switch gameMode {
        case .singlePlayer:
            restoreIndex = undoHistory.lastIndex(where: { $0.currentPlayer == .playerOne })
        case .twoPlayer:
            restoreIndex = undoHistory.indices.last
        case .zeroPlayer, .onlineMultiplayer:
            restoreIndex = nil
        }

        guard let restoreIndex else { return }

        let restoredGame = undoHistory[restoreIndex]
        cancelAIThinking(shouldLog: false)
        undoHistory.removeSubrange(restoreIndex..<undoHistory.endIndex)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            game = restoredGame
            flyingStone = nil
            isAnimatingMove = false
            isAIMovePending = false
            hasRecordedCurrentCompletedGame = false
            impossibleSearchProgress = 0
            impossibleSearchProgressText = ""
        }
        persistStableGameState()

        if gameMode == .singlePlayer {
            appendAIThought(wasThinking ? "Cancelled AI search and undid the player move." : "Undid the last player and AI moves.")
        }
    }

    private func toggleZeroPlayerPlayback() {
        guard gameMode == .zeroPlayer, !game.isGameOver else { return }

        if isZeroPlayerPaused {
            isZeroPlayerPaused = false
            appendAIThought("Autoplay resumed.")
            Task {
                await runAIMoveIfNeeded()
            }
        } else {
            isZeroPlayerPaused = true
            cancelAIThinking()
            appendAIThought("Autoplay paused.")
        }
    }

    private func playAgainFromEndGamePopup() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            endGameAnimationPulse = false
        }

        if gameMode == .onlineMultiplayer {
            onlineManager.startMatch()
        } else {
            resetCurrentGame()
        }
    }

    private func resetForSettingsChange() {
        cancelAIThinking()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            resetGame()
            flyingStone = nil
            isAnimatingMove = false
            isAIMovePending = false
            hasRecordedCurrentCompletedGame = false
        }
    }

    private func resetCurrentGame() {
        let shouldStartAIAfterReset = !isAIMovePending
        cancelAIThinking()
        if gameMode == .zeroPlayer {
            isZeroPlayerPaused = true
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            resetGame()
            flyingStone = nil
            hintedPitIndex = nil
            isAnimatingMove = false
            isAIMovePending = false
        }
        if shouldStartAIAfterReset {
            Task {
                await runAIMoveIfNeeded()
            }
        }
    }

    private func resetGame() {
        undoHistory.removeAll()
        hasRecordedCurrentCompletedGame = false
        game.reset(startingPlayer: resolvedStartingPlayer())
        persistStableGameState()
    }

    private func switchGameMode(from oldMode: GameMode, to newMode: GameMode) {
        persistStableGameState(for: oldMode)
        cancelAIThinking(shouldLog: (oldMode == .singlePlayer || oldMode == .zeroPlayer) && oldMode == newMode)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            restoreSavedGame(for: newMode)
            flyingStone = nil
            hintedPitIndex = nil
            isAnimatingMove = false
            isAIMovePending = false
            hasRecordedCurrentCompletedGame = false
            impossibleSearchProgress = 0
            impossibleSearchProgressText = ""
        }

        if newMode == .zeroPlayer {
            isZeroPlayerPaused = true
        }

        if newMode == .onlineMultiplayer {
            applyPendingOnlineMatchIfNeeded()
        }

        if newMode == .singlePlayer || (newMode == .zeroPlayer && !isZeroPlayerPaused) {
            Task {
                await runAIMoveIfNeeded()
            }
        }
    }

    private func restoreSavedGameIfNeeded() {
        migrateLegacySavedGameIfNeeded()
        restoreSavedGame(for: gameMode)
        if gameMode == .singlePlayer || (gameMode == .zeroPlayer && !isZeroPlayerPaused) {
            Task {
                await runAIMoveIfNeeded()
            }
        }
    }

    private func restoreSavedGame(for mode: GameMode) {
        guard let savedGame = savedGameState(for: mode) else {
            game.reset(startingPlayer: resolvedStartingPlayer(for: mode))
            undoHistory.removeAll()
            hasRecordedCurrentCompletedGame = false
            persistStableGameState(for: mode)
            return
        }

        let restoredGame = savedGame.game
        guard !restoredGame.isGameOver else {
            clearSavedGameState(for: mode)
            game.reset(startingPlayer: resolvedStartingPlayer(for: mode))
            undoHistory.removeAll()
            hasRecordedCurrentCompletedGame = false
            persistStableGameState(for: mode)
            return
        }

        game = restoredGame
        undoHistory.removeAll()
    }

    private func migrateLegacySavedGameIfNeeded() {
        guard !legacySavedGameState.isEmpty,
              savedGameData(for: gameMode).isEmpty else {
            return
        }

        setSavedGameData(legacySavedGameState, for: gameMode)
        legacySavedGameState = Data()
    }

    private func savedGameState(for mode: GameMode) -> SavedGameState? {
        let data = savedGameData(for: mode)
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(SavedGameState.self, from: data)
    }

    private func savedGameData(for mode: GameMode) -> Data {
        switch mode {
        case .singlePlayer:
            savedSinglePlayerGameState
        case .twoPlayer:
            savedTwoPlayerGameState
        case .zeroPlayer:
            savedZeroPlayerGameState
        case .onlineMultiplayer:
            savedOnlineGameState
        }
    }

    private func setSavedGameData(_ data: Data, for mode: GameMode) {
        switch mode {
        case .singlePlayer:
            savedSinglePlayerGameState = data
        case .twoPlayer:
            savedTwoPlayerGameState = data
        case .zeroPlayer:
            savedZeroPlayerGameState = data
        case .onlineMultiplayer:
            savedOnlineGameState = data
        }
    }

    private func clearSavedGameState(for mode: GameMode) {
        setSavedGameData(Data(), for: mode)
    }

    private func persistStableGameState(for mode: GameMode? = nil) {
        let mode = mode ?? gameMode
        if game.isGameOver {
            clearSavedGameState(for: mode)
            return
        }

        guard let data = try? JSONEncoder().encode(SavedGameState(game: game)) else { return }
        setSavedGameData(data, for: mode)
    }

    private var completedGameHistory: [CompletedGameResult] {
        guard !completedGameHistoryData.isEmpty,
              let history = try? JSONDecoder().decode([CompletedGameResult].self, from: completedGameHistoryData) else {
            return []
        }
        return history
    }

    private func recordCompletedGameIfNeeded() {
        guard game.isGameOver, !hasRecordedCurrentCompletedGame else { return }
        let result = CompletedGameResult(
            playerOneName: displayName(for: .playerOne),
            playerTwoName: displayName(for: .playerTwo),
            playerOneScore: game.storeCount(for: .playerOne),
            playerTwoScore: game.storeCount(for: .playerTwo),
            winnerName: game.winner.map { displayName(for: $0) }
        )
        var history = completedGameHistory
        history.insert(result, at: 0)
        if history.count > 10 {
            history.removeLast(history.count - 10)
        }
        if let data = try? JSONEncoder().encode(history) {
            completedGameHistoryData = data
            hasRecordedCurrentCompletedGame = true
            GameCenterAchievements.reportCompletedGame(
                game,
                gameMode: gameMode,
                difficulty: difficulty,
                localPlayerSide: onlineManager.localPlayerSide
            )
        }
    }

    private func cancelAIThinking(shouldLog: Bool = true) {
        let wasThinking = isAIMovePending || aiSearchTask != nil
        aiSearchGeneration += 1
        aiSearchTask?.cancel()
        aiSearchTask = nil
        isAIMovePending = false
        impossibleSearchProgress = 0
        impossibleSearchProgressText = ""
        if wasThinking && shouldLog {
            appendAIThought("Cancelled AI search.")
        }
    }

    @MainActor
    private func restartAIThinkingForUpdatedSettingsIfNeeded() {
        guard (gameMode == .singlePlayer || gameMode == .zeroPlayer),
              isAIControlled(game.currentPlayer),
              !(gameMode == .zeroPlayer && isZeroPlayerPaused),
              !game.isGameOver,
              !isAnimatingMove,
              (isAIMovePending || aiSearchTask != nil) else {
            return
        }

        cancelAIThinking(shouldLog: false)
        appendAIThought("Restarting AI search with updated settings.")
        Task {
            await runAIMoveIfNeeded()
        }
    }

    private func appendAIThought(_ entry: String) {
        aiThoughtLog.append(entry)
        if aiThoughtLog.count > 40 {
            aiThoughtLog.removeFirst(aiThoughtLog.count - 40)
        }
    }

    private func updateImpossibleProgress(
        searched: Int,
        maximum: Int,
        elapsed: TimeInterval,
        timeLimit: TimeInterval?,
        completedDepth: Int,
        cacheEntries: Int,
        bestMove: Int?,
        isExact: Bool
    ) {
        let bestMoveText = bestMove.map { "best \($0)" } ?? "best --"
        let solvedText = isExact ? "exact" : "depth \(completedDepth)"

        if let timeLimit {
            let remaining = max(0, timeLimit - elapsed)
            impossibleSearchProgress = min(elapsed / timeLimit, 1)
            impossibleSearchProgressText = "\(solvedText) • \(searched.formatted()) nodes • \(cacheEntries.formatted()) cached • \(bestMoveText) • \(remaining.formatted(.number.precision(.fractionLength(1))))s left"
        } else {
            let rate = elapsed > 0 ? Double(searched) / elapsed : 0
            let remainingPositions = max(0, maximum - searched)
            let eta = rate > 0 ? Double(remainingPositions) / rate : 0
            impossibleSearchProgress = min(Double(searched) / Double(maximum), 1)
            impossibleSearchProgressText = "\(solvedText) • \(searched.formatted()) / \(maximum.formatted()) nodes • \(cacheEntries.formatted()) cached • \(bestMoveText) • ETA \(eta.formatted(.number.precision(.fractionLength(1))))s"
        }
    }

    private func resolvedStartingPlayer(for mode: GameMode? = nil) -> Player {
        let mode = mode ?? gameMode
        guard mode == .singlePlayer || mode == .zeroPlayer else {
            return .playerOne
        }

        switch startingPlayer {
        case .human:
            return .playerOne
        case .ai:
            return .playerTwo
        case .random:
            return Bool.random() ? .playerOne : .playerTwo
        }
    }

    @ViewBuilder
    private func storeView(owner: Player, compact: Bool) -> some View {
        let isCurrent = owner == game.currentPlayer && !game.isGameOver
        let tint = isCurrent ? currentStoreTint : storeTint

        if compact {
            stoneCluster(count: game.storeCount(for: owner))
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 38)
                .overlay(alignment: .trailing) {
                    if shouldShowNumberLabels {
                        Text("\(game.storeCount(for: owner))")
                            .font(countFont(size: 26))
                            .foregroundStyle(visualTheme == .liquidGlass ? secondaryText : primaryText)
                            .contentTransition(.numericText())
                    }
                }
                .playerFacingRotation(tableRotationDegrees)
                .padding(.horizontal, 22)
                .mancalaGlassEffect(tint: tint, cornerRadius: 20, role: .store, interactive: isCurrent, seed: game.storeIndex(for: owner))
        } else {
            stoneCluster(count: game.storeCount(for: owner))
                .frame(height: 48)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if shouldShowNumberLabels {
                        Text("\(game.storeCount(for: owner))")
                            .font(countFont(size: 28))
                            .foregroundStyle(visualTheme == .liquidGlass ? secondaryText : primaryText)
                            .contentTransition(.numericText())
                            .padding(.bottom, 4)
                    }
                }
                .playerFacingRotation(tableRotationDegrees)
                .frame(minHeight: 148)
                .padding(10)
                .mancalaGlassEffect(tint: tint, cornerRadius: 24, role: .store, interactive: isCurrent, seed: game.storeIndex(for: owner))
        }
    }

    private func stoneView(colorIndex: Int, diameter: CGFloat) -> some View {
        Circle()
            .fill(stoneColor(for: colorIndex).gradient)
            .frame(width: diameter, height: diameter)
            .overlay {
                if visualTheme == .liquidGlass {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: diameter * 0.28, height: diameter * 0.28)
                        .offset(x: -diameter * 0.20, y: -diameter * 0.22)
                        .blur(radius: 0.4)
                }
            }
    }

    private func stoneCluster(count: Int) -> some View {
        ZStack {
            ForEach(0..<min(count, 18), id: \.self) { index in
                stoneView(colorIndex: index, diameter: 11)
                    .offset(stoneOffset(for: index))
                    .shadow(color: isDarkMode ? .black.opacity(0.30) : .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: count)
    }

    private func animatedStone(_ stone: FlyingStone) -> some View {
        stoneView(colorIndex: stone.colorIndex, diameter: 18)
            .shadow(color: isDarkMode ? .black.opacity(0.42) : .black.opacity(0.24), radius: 5, x: 0, y: 3)
            .position(stone.position)
            .allowsHitTesting(false)
    }

    @MainActor
    private func animateMove(from selectedIndex: Int) async {
        guard game.canPlayPit(at: selectedIndex), !isAnimatingMove else { return }

        recordUndoSnapshotIfNeeded()
        hintedPitIndex = nil
        let movingPlayer = game.currentPlayer
        let moveAchievementResult = moveAchievementResult(for: selectedIndex, movingPlayer: movingPlayer)
        let path = game.sowingPath(from: selectedIndex)
        let canAnimateVisually = is3DBoardActive || cellFrames[selectedIndex] != nil
        guard canAnimateVisually, !path.isEmpty else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                game.playPit(at: selectedIndex)
            }
            GameCenterAchievements.reportMove(
                moveAchievementResult,
                gameMode: gameMode,
                localPlayerSide: onlineManager.localPlayerSide
            )
            recordCompletedGameIfNeeded()
            persistStableGameState()
            handleOnlineMoveIfNeeded(from: selectedIndex, movingPlayer: movingPlayer)
            await runAIMoveIfNeeded()
            return
        }

        isAnimatingMove = true
        game.beginAnimatedMove(from: selectedIndex)

        if is3DBoardActive {
            // The whole picked-up pile travels together: lift it out of the
            // source pit as a clump, glide it over each well on the path, and
            // release one stone into each as it passes.
            activeBoardScene?.animationSpeed = stoneAnimationSpeed
            await activeBoardScene?.liftSowingCluster(from: selectedIndex, count: path.count)
            for destination in path {
                await activeBoardScene?.hopSowingCluster(to: destination)
                await activeBoardScene?.dropSowingStone(at: destination)
                withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                    game.depositStone(at: destination)
                    hapticTrigger += 1
                }
                try? await Task.sleep(for: .seconds(0.03 / stoneAnimationSpeed))
            }
        } else {
            var currentPoint = cellFrames[selectedIndex]?.center ?? .zero

            for (step, destination) in path.enumerated() {
                guard let destinationFrame = cellFrames[destination] else { continue }
                let destinationPoint = destinationFrame.center

                flyingStone = FlyingStone(position: currentPoint, colorIndex: step)
                try? await Task.sleep(for: .seconds(0.035 / stoneAnimationSpeed))

                withAnimation(.spring(response: 0.26 / stoneAnimationSpeed, dampingFraction: 0.72)) {
                    flyingStone?.position = destinationPoint
                }

                try? await Task.sleep(for: .seconds(0.15 / stoneAnimationSpeed))

                withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                    game.depositStone(at: destination)
                    hapticTrigger += 1
                    flyingStone = nil
                }

                currentPoint = destinationPoint
                try? await Task.sleep(for: .seconds(0.03 / stoneAnimationSpeed))
            }
        }

        let lastIndex = path[path.count - 1]
        let animatedCapture = await animateCaptureIfNeeded(lastIndex: lastIndex)

        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            game.finishAnimatedMove(lastIndex: lastIndex, captureAlreadyApplied: animatedCapture)
            isAnimatingMove = false
        }
        GameCenterAchievements.reportMove(
            moveAchievementResult,
            gameMode: gameMode,
            localPlayerSide: onlineManager.localPlayerSide
        )
        recordCompletedGameIfNeeded()
        persistStableGameState()
        handleOnlineMoveIfNeeded(from: selectedIndex, movingPlayer: movingPlayer)

        await runAIMoveIfNeeded()
    }

    private func moveAchievementResult(for selectedIndex: Int, movingPlayer: Player) -> MancalaMoveAchievementResult {
        var simulatedGame = game
        let path = simulatedGame.sowingPath(from: selectedIndex)
        guard let lastIndex = path.last else {
            return MancalaMoveAchievementResult(movingPlayer: movingPlayer, capturedStones: 0, earnedExtraTurn: false)
        }

        simulatedGame.beginAnimatedMove(from: selectedIndex)
        for index in path {
            simulatedGame.depositStone(at: index)
        }

        let capturedStones = simulatedGame.captureMove(afterLandingAt: lastIndex)?.capturedStones ?? 0
        simulatedGame.finishAnimatedMove(lastIndex: lastIndex)
        let earnedExtraTurn = !simulatedGame.isGameOver && simulatedGame.currentPlayer == movingPlayer

        return MancalaMoveAchievementResult(
            movingPlayer: movingPlayer,
            capturedStones: capturedStones,
            earnedExtraTurn: earnedExtraTurn
        )
    }

    private func handleOnlineMoveIfNeeded(from selectedIndex: Int, movingPlayer: Player) {
        guard gameMode == .onlineMultiplayer else { return }
        guard onlineManager.localPlayerSide == movingPlayer else { return }

        if !game.isGameOver, game.currentPlayer == movingPlayer {
            onlineManager.noteLocalExtraTurn()
            return
        }

        onlineManager.sendTurn(
            game: game,
            lastMoveIndex: selectedIndex,
            playerOneName: displayName(for: .playerOne),
            playerTwoName: displayName(for: .playerTwo)
        )
    }

    private func applyPendingOnlineMatchIfNeeded() {
        guard let payload = onlineManager.pendingPayload else {
            if gameMode == .onlineMultiplayer,
               onlineManager.currentMatchID != nil,
               game.pits.reduce(0, +) != 48 {
                game.reset(startingPlayer: .playerOne)
            }
            return
        }

        onlinePlayerOneName = payload.playerOneName
        onlinePlayerTwoName = payload.playerTwoName

        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            game = payload.game.game
            flyingStone = nil
            hintedPitIndex = nil
            isAnimatingMove = false
            isAIMovePending = false
            hasRecordedCurrentCompletedGame = false
        }
        onlineManager.clearPendingPayload()
        recordCompletedGameIfNeeded()
        persistStableGameState(for: .onlineMultiplayer)
    }

    @MainActor
    private func runAIMoveIfNeeded() async {
        guard (gameMode == .singlePlayer || gameMode == .zeroPlayer),
              isAIPlayAvailable,
              isAIControlled(game.currentPlayer),
              !(gameMode == .zeroPlayer && isZeroPlayerPaused),
              !game.isGameOver,
              !isAnimatingMove,
              !isAIMovePending else {
            return
        }

        aiSearchGeneration += 1
        let searchGeneration = aiSearchGeneration
        let aiPlayer = game.currentPlayer
        let aiDifficulty = aiDifficulty(for: aiPlayer)
        isAIMovePending = true
        aiThoughtLog = []
        impossibleSearchProgress = 0
        impossibleSearchProgressText = ""
        appendAIThought("\(displayName(for: aiPlayer)) (\(aiDifficulty.title)) is choosing a move.")
        try? await Task.sleep(for: .milliseconds(350))
        guard searchGeneration == aiSearchGeneration else { return }

        guard let selectedPit = await chooseAIPit(for: aiPlayer, difficulty: aiDifficulty) else {
            guard searchGeneration == aiSearchGeneration else { return }
            isAIMovePending = false
            aiSearchTask = nil
            appendAIThought("No move selected.")
            return
        }

        guard searchGeneration == aiSearchGeneration,
              isAIMovePending,
              (gameMode == .singlePlayer || gameMode == .zeroPlayer),
              !(gameMode == .zeroPlayer && isZeroPlayerPaused),
              game.currentPlayer == aiPlayer,
              !game.isGameOver else {
            if searchGeneration == aiSearchGeneration {
                aiSearchTask = nil
            }
            return
        }

        appendAIThought("Selected pit \(selectedPit).")
        aiSearchTask = nil
        isAIMovePending = false
        await animateMove(from: selectedPit)
    }

    private func chooseAIPit(for player: Player, difficulty: AIDifficulty) async -> Int? {
        let legalPits = game.legalPits(for: player)
        guard !legalPits.isEmpty else { return nil }

        if difficulty == .impossible {
            appendAIThought("Starting exact search over legal pits \(legalPits).")
            let pitsSnapshot = game.pits
            let currentPlayer = player == .playerOne ? 1 : 2
            let limitMode = impossibleSearchLimitMode
            let maxPositions = limitMode == .positions ? impossibleSearchLimit : 100_000_000
            let timeLimit = limitMode == .time ? TimeInterval(impossibleSearchTimeLimit) : nil
            let progress: @Sendable (String) -> Void = { entry in
                Task { @MainActor in
                    appendAIThought(entry)
                }
            }
            let progressUpdate: @Sendable (MancalaOptimalSolver.SearchProgress) -> Void = { searchProgress in
                Task { @MainActor in
                    updateImpossibleProgress(
                        searched: searchProgress.searched,
                        maximum: searchProgress.maximum,
                        elapsed: searchProgress.elapsed,
                        timeLimit: searchProgress.timeLimit,
                        completedDepth: searchProgress.completedDepth,
                        cacheEntries: searchProgress.cacheEntries,
                        bestMove: searchProgress.bestMove,
                        isExact: searchProgress.isExact
                    )
                }
            }
            let searchTask = Task.detached(priority: .userInitiated) {
                MancalaOptimalSolver.bestMove(
                    pits: pitsSnapshot,
                    currentPlayer: currentPlayer,
                    maxPositions: maxPositions,
                    timeLimit: timeLimit,
                    progress: progress,
                    progressUpdate: progressUpdate
                )
            }
            aiSearchTask = searchTask
            return await searchTask.value ?? legalPits.first
        }

        if #available(iOS 27.0, *), FoundationModelAIMoveProvider.isAvailable {
            do {
                appendAIThought("Requesting on-device model move.")
                let selectedPit = try await FoundationModelAIMoveProvider.choosePit(
                    prompt: aiPrompt(for: player, difficulty: difficulty, legalPits: legalPits)
                )

                if legalPits.contains(selectedPit) {
                    return selectedPit
                }

                appendAIThought("Model returned illegal pit \(selectedPit); using heuristic fallback.")
            } catch {
                appendAIThought("Model request failed; using heuristic fallback.")
            }
        } else {
            appendAIThought("On-device model is unavailable; using heuristic move selection.")
        }

        return heuristicAIPit(for: player, difficulty: difficulty, legalPits: legalPits)
    }

    private func heuristicAIPit(for player: Player, difficulty: AIDifficulty, legalPits: [Int]) -> Int? {
        let rankedMoves = legalPits.map { pitIndex in
            var simulatedGame = game
            let startingStore = simulatedGame.storeCount(for: player)
            let opponentStartingStore = simulatedGame.storeCount(for: player.opponent)
            let path = simulatedGame.sowingPath(from: pitIndex)
            let lastIndex = path.last
            let capturedStones = lastIndex.flatMap { simulatedGame.captureMove(afterLandingAt: $0)?.capturedStones } ?? 0
            simulatedGame.playPit(at: pitIndex)

            let storeGain = simulatedGame.storeCount(for: player) - startingStore
            let opponentStoreGain = simulatedGame.storeCount(for: player.opponent) - opponentStartingStore
            let extraTurnBonus = simulatedGame.currentPlayer == player && !simulatedGame.isGameOver ? 18 : 0
            let winBonus = simulatedGame.winner == player ? 1_000 : 0
            let drawPenalty = simulatedGame.isDraw ? 8 : 0
            let lossPenalty = simulatedGame.winner == player.opponent ? 1_000 : 0
            let captureBonus = capturedStones * 5
            let storeAdvantage = simulatedGame.storeCount(for: player) - simulatedGame.storeCount(for: player.opponent)
            let sideBalance = player == .playerOne
                ? simulatedGame.pits[0...5].reduce(0, +) - simulatedGame.pits[7...12].reduce(0, +)
                : simulatedGame.pits[7...12].reduce(0, +) - simulatedGame.pits[0...5].reduce(0, +)

            let score: Int
            switch difficulty {
            case .easy:
                score = storeGain + extraTurnBonus / 3 + captureBonus / 4
            case .medium:
                score = storeGain * 4 + extraTurnBonus + captureBonus + storeAdvantage * 2
            case .hard:
                score = storeGain * 6 + extraTurnBonus + captureBonus + storeAdvantage * 4 + sideBalance - opponentStoreGain * 3 + winBonus - drawPenalty - lossPenalty
            case .impossible:
                score = storeGain * 8 + extraTurnBonus + captureBonus + storeAdvantage * 5 + sideBalance + winBonus - drawPenalty - lossPenalty
            }

            return (pitIndex: pitIndex, score: score)
        }

        return rankedMoves.max { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.pitIndex < rhs.pitIndex
            }
            return lhs.score < rhs.score
        }?.pitIndex
    }

    private func aiPrompt(for player: Player, difficulty: AIDifficulty, legalPits: [Int]) -> String {
        """
        You are playing Mancala as \(displayName(for: player)).
        Board array indices 0...5 are \(displayName(for: .playerOne)) pits, index 6 is \(displayName(for: .playerOne)) store, indices 7...12 are \(displayName(for: .playerTwo)) pits, and index 13 is \(displayName(for: .playerTwo)) store.
        Current board: \(game.pits)
        Legal \(displayName(for: player)) pit indices: \(legalPits)
        \(displayName(for: .playerOne)) store: \(game.storeCount(for: .playerOne))
        \(displayName(for: .playerTwo)) store: \(game.storeCount(for: .playerTwo))
        Difficulty: \(difficulty.title)
        Strategy: \(difficulty.promptInstruction)
        Return one legal pit index from the legal indices list.
        """
    }

    @MainActor
    private func animateCaptureIfNeeded(lastIndex: Int) async -> Bool {
        guard let capture = game.captureMove(afterLandingAt: lastIndex) else {
            return false
        }

        if is3DBoardActive {
            activeBoardScene?.animationSpeed = stoneAnimationSpeed
            let capturedSources = [capture.landingIndex] + Array(repeating: capture.oppositeIndex, count: capture.capturedStones)
            for sourceIndex in capturedSources {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.80)) {
                    game.removeStone(at: sourceIndex)
                }
                await activeBoardScene?.flyStone(from: sourceIndex, to: capture.storeIndex)
                withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                    game.depositStone(at: capture.storeIndex)
                    hapticTrigger += 1
                }
                try? await Task.sleep(for: .seconds(0.012 / stoneAnimationSpeed))
            }
            return true
        }

        guard let storeFrame = cellFrames[capture.storeIndex] else {
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
            try? await Task.sleep(for: .seconds(0.02 / stoneAnimationSpeed))

            withAnimation(.spring(response: 0.22 / stoneAnimationSpeed, dampingFraction: 0.72)) {
                flyingStone?.position = storePoint
            }

            try? await Task.sleep(for: .seconds(0.095 / stoneAnimationSpeed))

            withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                game.depositStone(at: capture.storeIndex)
                hapticTrigger += 1
                flyingStone = nil
            }

            try? await Task.sleep(for: .seconds(0.012 / stoneAnimationSpeed))
        }

        return true
    }

    private func updateCellFrames(_ preferences: [Int: Anchor<CGRect>], proxy: GeometryProxy) {
        cellFrames = preferences.mapValues { proxy[$0] }
    }

    private func stoneColor(for index: Int) -> Color {
        if visualTheme == .calligraphy {
            let inkWash = [
                Color.black,
                Color(red: 0.12, green: 0.12, blue: 0.12),
                Color(red: 0.22, green: 0.22, blue: 0.22),
                Color(red: 0.34, green: 0.34, blue: 0.34),
                Color(red: 0.06, green: 0.06, blue: 0.06)
            ]
            return inkWash[index % inkWash.count]
        }

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

/// A closed brush-stroke ring with hand-drawn wobble and variable ink weight.
/// `exponent` shapes the ring: 2 is an ellipse, higher values approach a rounded rectangle.
private struct InkRing: Shape {
    var seed: Int
    var exponent: Double
    var weightFraction: Double
    var wobble: Double = 0.016

    func path(in rect: CGRect) -> Path {
        guard rect.width > 4, rect.height > 4 else { return Path() }

        let steps = 110
        let minDimension = min(rect.width, rect.height)
        let baseWeight = min(max(minDimension * weightFraction, 1.1), 6.5)
        let phaseOne = Double((seed &* 73) % 628) / 100
        let phaseTwo = Double((seed &* 131) % 628) / 100
        let phaseThree = Double((seed &* 197) % 628) / 100

        let inset = baseWeight * 0.9 + minDimension * wobble
        let a = rect.width / 2 - inset
        let b = rect.height / 2 - inset
        let e = 2.0 / exponent

        var outerPoints: [CGPoint] = []
        var innerPoints: [CGPoint] = []
        outerPoints.reserveCapacity(steps)
        innerPoints.reserveCapacity(steps)

        for step in 0..<steps {
            let theta = Double(step) / Double(steps) * 2 * .pi
            let cosine = cos(theta)
            let sine = sin(theta)
            let x = a * pow(abs(cosine), e) * (cosine < 0 ? -1 : 1)
            let y = b * pow(abs(sine), e) * (sine < 0 ? -1 : 1)
            let length = max(sqrt(x * x + y * y), 0.001)
            let unitX = x / length
            let unitY = y / length
            let sway = 1 + wobble * (0.62 * sin(2 * theta + phaseOne) + 0.38 * sin(5 * theta + phaseTwo))
            let halfWeight = baseWeight * max(0.30, 1 + 0.42 * sin(3 * theta + phaseThree) + 0.18 * sin(7 * theta + phaseOne)) / 2
            outerPoints.append(CGPoint(x: rect.midX + x * sway + unitX * halfWeight, y: rect.midY + y * sway + unitY * halfWeight))
            innerPoints.append(CGPoint(x: rect.midX + x * sway - unitX * halfWeight, y: rect.midY + y * sway - unitY * halfWeight))
        }

        var path = Path()
        path.addLines(outerPoints)
        path.closeSubpath()
        path.addLines(Array(innerPoints.reversed()))
        path.closeSubpath()
        return path
    }
}

/// A curved brush stroke that cups an element from below, like the base of a bowl:
/// the centerline bows downward, the body swells with a wet-ink belly, the head is
/// blunt and rounded, and the tail tapers to a lifted point. High-frequency seeded
/// texture keeps the edges from reading as clean vector lines. Odd seeds sweep the
/// opposite direction.
private struct InkBrushStroke: Shape {
    var seed: Int
    var weight: CGFloat

    func path(in rect: CGRect) -> Path {
        guard rect.width > 8, rect.height > 2 else { return Path() }

        let steps = 44
        let flip = seed % 2 == 1
        let phaseOne = Double((seed &* 73) % 628) / 100
        let phaseTwo = Double((seed &* 131) % 628) / 100

        let strokeWeight = Double(min(weight, rect.height * 0.60))
        let bow = min(Double(rect.height) - strokeWeight, Double(rect.width) * 0.10) * 0.9

        func xAt(_ t: Double) -> Double {
            let fraction = flip ? 1 - t : t
            return Double(rect.minX) + fraction * Double(rect.width)
        }

        func centerY(_ t: Double) -> Double {
            Double(rect.minY) + strokeWeight / 2
                + bow * sin(.pi * t)
                + strokeWeight * 0.06 * sin(9 * t + phaseOne)
        }

        func halfWeight(_ t: Double) -> Double {
            let body = pow(sin(.pi * (0.08 + 0.92 * pow(t, 0.9))), 0.72)
            let texture = 1 + 0.14 * sin(13 * t + phaseOne) + 0.08 * sin(29 * t + phaseTwo)
            return max(0, strokeWeight / 2 * body * texture)
        }

        var topPoints: [CGPoint] = []
        var bottomPoints: [CGPoint] = []
        topPoints.reserveCapacity(steps + 1)
        bottomPoints.reserveCapacity(steps + 1)

        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let x = xAt(t)
            let y = centerY(t)
            let half = halfWeight(t)
            topPoints.append(CGPoint(x: x, y: y - half))
            bottomPoints.append(CGPoint(x: x, y: y + half))
        }

        var path = Path()
        path.move(to: topPoints[0])
        for point in topPoints.dropFirst() {
            path.addLine(to: point)
        }
        for point in bottomPoints.reversed().dropFirst() {
            path.addLine(to: point)
        }

        let headHalfWeight = halfWeight(0)
        let headBulgeX = xAt(0) + (flip ? 1 : -1) * headHalfWeight * 1.5
        path.addQuadCurve(
            to: topPoints[0],
            control: CGPoint(x: headBulgeX, y: centerY(0))
        )
        path.closeSubpath()
        return path
    }
}

/// A single tapered horizontal brush dash, thick at the left and trailing to a point.
private struct InkDash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - rect.height * 0.05))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.30),
            control1: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.16)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.22),
            control1: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.maxY),
            control2: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY - rect.height * 0.10)
        )
        path.closeSubpath()
        return path
    }
}

/// The visible side wall of an extruded rounded-rect slab: the band between the
/// near edge of the top face and that same edge pushed down by `depth`. Corner
/// curvature is sampled so the wall silhouette wraps around the rounded corners.
private enum MancalaSurfaceRole {
    case board
    case pit
    case store
    case panel
    case control
}

private struct MancalaSurfaceModifier: ViewModifier {
    @Environment(\.mancalaVisualTheme) private var visualTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.mancalaBoardFlipped) private var isFlipped

    let role: MancalaSurfaceRole
    let tint: Color
    let cornerRadius: CGFloat
    let interactive: Bool
    let seed: Int

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        if visualTheme == .calligraphy {
            calligraphySurface(content)
        } else {
            glassSurface(content)
        }
    }

    // MARK: Calligraphy

    private var inkOpacity: Double {
        switch role {
        case .board: 0
        case .pit: interactive ? 0.92 : 0.35
        case .store: interactive ? 0.92 : 0.42
        case .panel: 0.50
        case .control: 0.80
        }
    }

    private var underlineWeight: CGFloat {
        switch role {
        case .board: 0
        case .pit: interactive ? 5.5 : 3.2
        case .store: interactive ? 6.5 : 3.8
        case .panel: 3.6
        case .control: 4.6
        }
    }

    private var underlineHeight: CGFloat {
        switch role {
        case .board: 0
        case .pit: interactive ? 14 : 11
        case .store: interactive ? 16 : 13
        case .panel: 11
        case .control: 12
        }
    }

    private var underlineInset: CGFloat {
        switch role {
        case .board: 0
        case .pit: 14
        case .store: 18
        case .panel: 28
        case .control: 24
        }
    }

    private func calligraphySurface(_ content: Content) -> some View {
        content
            .background(Color.white)
            .overlay(alignment: isFlipped ? .top : .bottom) {
                if role != .board {
                    InkBrushStroke(seed: seed, weight: underlineWeight)
                        .fill(Color.black.opacity(inkOpacity))
                        .frame(height: underlineHeight)
                        .padding(.horizontal, underlineInset)
                        .rotationEffect(.degrees(isFlipped ? 180 : 0))
                        .offset(y: isFlipped ? 2 : -2)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: Liquid glass

    private var isRecessed: Bool {
        role == .pit || role == .store
    }

    /// Pits are oval wells, stores are oblong troughs — both carved into the
    /// slab rather than sitting on it, so they render as shaded depressions in
    /// the board surface instead of separate glass elements.
    private var wellShape: AnyShape {
        role == .pit ? AnyShape(Ellipse()) : AnyShape(Capsule(style: .continuous))
    }

    private var accent: Color? {
        guard interactive else { return nil }
        switch role {
        case .pit:
            return isDark ? .cyan : .blue
        case .store:
            return .green
        case .board, .panel, .control:
            return nil
        }
    }

    private var nearEdge: UnitPoint {
        isFlipped ? .top : .bottom
    }

    private var farEdge: UnitPoint {
        isFlipped ? .bottom : .top
    }

    private var rimGradient: LinearGradient {
        LinearGradient(
            colors: role == .board
                ? [Color.white.opacity(isDark ? 0.45 : 0.90), Color.white.opacity(isDark ? 0.30 : 0.60)]
                : [Color.white.opacity(isDark ? 0.40 : 0.75), Color.black.opacity(isDark ? 0.28 : 0.09)],
            startPoint: farEdge,
            endPoint: nearEdge
        )
    }

    /// Real slab thickness: a copy of the board face offset toward the near
    /// edge, drawn behind it inside the board's 3D tilt so it foreshortens
    /// with the perspective and reads as the front edge of one solid block.
    /// A blurred ellipse grounds the block with a contact shadow.
    private var slabEdge: some View {
        let thickness: CGFloat = 24

        return ZStack {
            Ellipse()
                .fill(Color.black.opacity(isDark ? 0.50 : 0.26))
                .blur(radius: 22)
                .frame(height: 48)
                .padding(.horizontal, 4)
                .frame(maxHeight: .infinity, alignment: isFlipped ? .top : .bottom)
                .offset(y: isFlipped ? -(thickness + 18) : thickness + 18)

            ZStack {
                surfaceShape
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.14), Color.white.opacity(0.05)]
                                : [Color(red: 0.86, green: 0.86, blue: 0.88), Color(red: 0.73, green: 0.73, blue: 0.76)],
                            startPoint: farEdge,
                            endPoint: nearEdge
                        )
                    )

                surfaceShape
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.black.opacity(isDark ? 0.40 : 0.16), location: 0),
                                .init(color: .clear, location: 0.12),
                                .init(color: .clear, location: 0.88),
                                .init(color: Color.black.opacity(isDark ? 0.40 : 0.16), location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .offset(y: isFlipped ? -thickness : thickness)
        }
        .allowsHitTesting(false)
    }

    /// Shading that makes a well read as a smooth concave depression in the
    /// slab: the far wall falls into shadow, ambient occlusion hugs the whole
    /// rim, and light pools on the floor toward the near edge. Everything is
    /// blurred and clipped to the well so there is no hard boundary line.
    private var wellInterior: some View {
        ZStack {
            wellShape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(isDark ? 0.38 : 0.17), location: 0),
                            .init(color: Color.black.opacity(isDark ? 0.16 : 0.06), location: 0.42),
                            .init(color: Color.white.opacity(isDark ? 0.05 : 0.28), location: 1)
                        ],
                        startPoint: farEdge,
                        endPoint: nearEdge
                    )
                )

            wellShape
                .stroke(Color.black.opacity(isDark ? 0.40 : 0.15), lineWidth: 10)
                .blur(radius: 8)

            wellShape
                .stroke(Color.black.opacity(isDark ? 0.30 : 0.13), lineWidth: 6)
                .blur(radius: 5)
                .offset(y: isFlipped ? -5 : 5)

            wellShape
                .fill(
                    EllipticalGradient(
                        colors: [Color.white.opacity(isDark ? 0.10 : 0.42), .clear],
                        center: UnitPoint(x: 0.5, y: isFlipped ? 0.30 : 0.70),
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.55
                    )
                )

            if let accent {
                wellShape
                    .fill(
                        EllipticalGradient(
                            colors: [accent.opacity(isDark ? 0.26 : 0.13), .clear],
                            center: UnitPoint(x: 0.5, y: isFlipped ? 0.38 : 0.62),
                            startRadiusFraction: 0,
                            endRadiusFraction: 0.52
                        )
                    )
                    .blur(radius: 5)
            }
        }
        .clipShape(wellShape)
        .allowsHitTesting(false)
    }

    /// A depression carved into the board: no material of its own, just
    /// concave shading plus a soft light catch on the board surface below the
    /// near rim.
    private func recessedSurface(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    wellShape
                        .stroke(Color.white.opacity(isDark ? 0.14 : 0.65), lineWidth: 1.6)
                        .blur(radius: 1.2)
                        .offset(y: isFlipped ? -1.5 : 1.5)

                    wellInterior
                }
                .allowsHitTesting(false)
            }
    }

    private func raisedSurface(_ content: Content) -> some View {
        glassBase(content)
            .overlay {
                surfaceShape
                    .strokeBorder(rimGradient, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .background {
                if role == .board {
                    slabEdge
                }
            }
    }

    @ViewBuilder
    private func glassSurface(_ content: Content) -> some View {
        if isRecessed {
            recessedSurface(content)
        } else {
            raisedSurface(content)
        }
    }

    /// The board slab deliberately avoids `glassEffect`: on real hardware the
    /// system renders it with live lensing and near-full transparency, which
    /// washes the frosted look out against bright backgrounds (the simulator
    /// only approximates it, so the two disagree). Frosted glass is opaque
    /// enough that a material plus milky tint renders it faithfully — and
    /// identically — everywhere. Panels and controls keep the native effect.
    @ViewBuilder
    private func glassBase(_ content: Content) -> some View {
        #if os(visionOS)
        content.background {
            surfaceShape.fill(tint)
        }
        #else
        if role == .board {
            content.background {
                surfaceShape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        surfaceShape.fill(tint)
                    }
            }
        } else if #available(iOS 27.0, *) {
            content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background {
                surfaceShape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        surfaceShape.fill(tint)
                    }
            }
        }
        #endif
    }
}

private struct MancalaButtonStyleModifier: ViewModifier {
    @Environment(\.mancalaVisualTheme) private var visualTheme

    func body(content: Content) -> some View {
        if visualTheme == .calligraphy {
            content
                .buttonStyle(.plain)
                .background(.white)
                .overlay {
                    InkRing(seed: 11, exponent: 2.0, weightFraction: 0.045)
                        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                }
        } else {
            #if os(visionOS)
            content.buttonStyle(.bordered)
            #else
            if #available(iOS 27.0, *) {
                content.buttonStyle(.glass)
            } else {
                content.buttonStyle(.bordered)
            }
            #endif
        }
    }
}

private extension View {
    func mancalaGlassEffect(
        tint: Color,
        cornerRadius: CGFloat,
        role: MancalaSurfaceRole = .panel,
        interactive: Bool = false,
        seed: Int = 0
    ) -> some View {
        modifier(MancalaSurfaceModifier(role: role, tint: tint, cornerRadius: cornerRadius, interactive: interactive, seed: seed))
    }

    func mancalaGlassButtonStyle() -> some View {
        modifier(MancalaButtonStyleModifier())
    }

    @ViewBuilder
    func mancalaNameTextFieldStyle() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.words)
            .disableAutocorrection(true)
        #else
        self
        #endif
    }

    @ViewBuilder
    func mancalaNumberTextFieldStyle(width: CGFloat) -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
        #else
        self.multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
        #endif
    }
}

#Preview("Liquid Glass") {
    UserDefaults.standard.set(VisualTheme.liquidGlass.rawValue, forKey: "visualTheme")
    return ContentView()
}

#Preview("Calligraphy") {
    UserDefaults.standard.set(VisualTheme.calligraphy.rawValue, forKey: "visualTheme")
    return ContentView()
}
