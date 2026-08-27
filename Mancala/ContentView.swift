import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var game = MancalaGame()
    @State private var cellFrames: [Int: CGRect] = [:]
    @State private var flyingStone: FlyingStone?
    @State private var isAnimatingMove = false
    @State private var hapticTrigger = 0
    @State private var endGameAnimationPulse = false
    @AppStorage("gameMode") private var gameMode = AppDefaults.gameMode
    @AppStorage("visualTheme") private var visualTheme = AppDefaults.visualTheme
    @AppStorage("boardMaterialStyle") private var boardMaterialStyle = AppDefaults.boardMaterialStyle
    @AppStorage("boardBackgroundStyle") private var boardBackgroundStyle = AppDefaults.boardBackgroundStyle
    @AppStorage("stoneSetStyle") private var stoneSetStyle = AppDefaults.stoneSetStyle
    @AppStorage("gyroMotionEnabled") private var gyroMotionEnabled = AppDefaults.gyroMotionEnabled
    @AppStorage("stoneAnimationSpeed") private var stoneAnimationSpeed = AppDefaults.stoneAnimationSpeed
    @AppStorage("flipScreenForTwoPlayerTurns") private var flipScreenForTwoPlayerTurns = AppDefaults.flipScreenForTwoPlayerTurns
    @AppStorage("difficulty") private var difficulty = AppDefaults.difficulty
    @AppStorage("zeroPlayerOneDifficulty") private var zeroPlayerOneDifficulty = AppDefaults.zeroPlayerOneDifficulty
    @AppStorage("zeroPlayerTwoDifficulty") private var zeroPlayerTwoDifficulty = AppDefaults.zeroPlayerTwoDifficulty
    @AppStorage("startingPlayer") private var startingPlayer = AppDefaults.startingPlayer
    @AppStorage("singlePlayerUndoButtonEnabled") private var isSinglePlayerUndoButtonEnabled = AppDefaults.singlePlayerUndoButtonEnabled
    @AppStorage("twoPlayerUndoButtonEnabled") private var isTwoPlayerUndoButtonEnabled = AppDefaults.twoPlayerUndoButtonEnabled
    @AppStorage("singlePlayerShowNumberLabels") private var singlePlayerShowNumberLabels = AppDefaults.singlePlayerShowNumberLabels
    @AppStorage("twoPlayerShowNumberLabels") private var twoPlayerShowNumberLabels = AppDefaults.twoPlayerShowNumberLabels
    @AppStorage("zeroPlayerShowNumberLabels") private var zeroPlayerShowNumberLabels = AppDefaults.zeroPlayerShowNumberLabels
    @AppStorage("onlineShowNumberLabels") private var onlineShowNumberLabels = AppDefaults.onlineShowNumberLabels
    @AppStorage("singlePlayerOneName") private var singlePlayerOneName = AppDefaults.playerOneName
    @AppStorage("singlePlayerTwoName") private var singlePlayerTwoName = AppDefaults.playerTwoName
    @AppStorage("twoPlayerOneName") private var twoPlayerOneName = AppDefaults.playerOneName
    @AppStorage("twoPlayerTwoName") private var twoPlayerTwoName = AppDefaults.playerTwoName
    @AppStorage("zeroPlayerOneName") private var zeroPlayerOneName = AppDefaults.playerOneName
    @AppStorage("zeroPlayerTwoName") private var zeroPlayerTwoName = AppDefaults.playerTwoName
    @AppStorage("onlinePlayerOneName") private var onlinePlayerOneName = AppDefaults.playerOneName
    @AppStorage("onlinePlayerTwoName") private var onlinePlayerTwoName = AppDefaults.playerTwoName
    @AppStorage("playerOneName") private var legacyPlayerOneName = AppDefaults.playerOneName
    @AppStorage("playerTwoName") private var legacyPlayerTwoName = AppDefaults.playerTwoName
    @AppStorage("modeSpecificPlayerNamesMigrated") private var modeSpecificPlayerNamesMigrated = false
    @State private var isSettingsPresented = false
    @State private var isGameHistoryPresented = false
    @State private var isRulesPresented = false
    @State private var isCustomizePresented = false
    @State private var isMainMenuPresented = true
    @State private var isMainMenuShowingChallenges = false
    @State private var activeChallenge: MancalaChallenge?
    @State private var challengeMovesUsed = 0
    @State private var challengeFailed = false
    @AppStorage("completedChallengeIDs") private var completedChallengeIDsStorage = ""
    @State private var hasRecordedCurrentCompletedGame = false
    @State private var undoHistory: [MancalaGame] = []
    @State private var isAIMovePending = false
    @State private var aiSearchGeneration = 0
    @State private var aiSearchTask: Task<Int?, Never>?
    @State private var isThoughtPanelExpanded = false
    @State private var aiThoughtLog: [String] = []
    @State private var isZeroPlayerPaused = true
    @State private var onlineManager = GameCenterMultiplayerManager()
    /// Every pit the local player has sowed since the last handoff. A turn can
    /// run to several sows when stones keep landing in the player's own store,
    /// and the far device replays the whole run so the opponent's stones are
    /// seen travelling rather than appearing where they stopped.
    @State private var pendingOnlineMoveIndices: [Int] = []
    /// True while the board is playing back the opponent's sows; taps are
    /// already refused (it isn't the local player's turn), but the replay also
    /// must not be cut short by another inbound update.
    @State private var isReplayingOnlineMove = false
    /// The match the board on screen belongs to. An update from any other one
    /// means a new session, and a new session always opens on a fresh board.
    @State private var appliedOnlineMatchID: String?
    @State private var isConfirmingOnlineExit = false
    @State private var onlineEndingNotice: OnlineMatchEnding?
    /// Set when Online was picked from the menu before Game Center had
    /// finished signing in: matchmaking opens as soon as it does, so the
    /// player isn't left on a board with nothing to tap.
    @State private var isAwaitingOnlineMatchmaking = false
    @AppStorage("impossibleSearchLimitMode") private var impossibleSearchLimitMode = AppDefaults.impossibleSearchLimitMode
    @AppStorage("impossibleSearchLimit") private var impossibleSearchLimit = AppDefaults.impossibleSearchLimit
    @AppStorage("impossibleSearchTimeLimit") private var impossibleSearchTimeLimit = AppDefaults.impossibleSearchTimeLimit
    @State private var impossibleSearchProgress = 0.0
    @State private var impossibleSearchProgressText = ""
    @State private var hintedPitIndex: Int?
    @State private var isHintSearching = false
    @AppStorage("savedSinglePlayerGameState") private var savedSinglePlayerGameState = Data()
    @AppStorage("savedTwoPlayerGameState") private var savedTwoPlayerGameState = Data()
    @AppStorage("savedZeroPlayerGameState") private var savedZeroPlayerGameState = Data()
    @AppStorage("completedGameHistory") private var completedGameHistoryData = Data()
    @AppStorage("savedGameState") private var legacySavedGameState = Data()
    /// The board drawn inside the window. On visionOS the volume keeps a scene
    /// of its own: a built RealityKit graph can't be handed from one
    /// `RealityView` to another, so each host needs its own.
    @State private var boardScene = BoardScene()
    /// Read on every platform: the parallax controller wants it, and so does
    /// the online session, which treats the app going away as the player
    /// leaving the match.
    @Environment(\.scenePhase) private var scenePhase
    #if os(visionOS)
    @Environment(SpatialBoardModel.self) private var spatialBoard
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    /// Where the player last left the board. Defaults to the window, so a first
    /// launch is one window and nothing else in the room.
    @AppStorage("prefersBoardInSpace") private var prefersBoardInSpace = false
    /// How much light the app adds to the 3D board on top of the room's own —
    /// the room is the board's only light source here, and it runs out early.
    /// See `BoardBrightness`.
    @AppStorage("boardBrightness") private var boardBrightness = AppDefaults.boardBrightness
    @State private var isHeaderMenuPresented = false
    #else
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

                // A single call site kept stable across orientation changes —
                // not an `if isPortrait {...} else {...}` branch — so the 3D
                // board's RealityView (nested inside `gameContent`) is never
                // torn down and recreated on rotation. Recreating it loses the
                // RealityKit scene the persisted `BoardScene` entity graph was
                // attached to, leaving the board invisible (same failure mode
                // as switching visual themes; see the ZStack in `gameContent`).
                gameContent(isPortrait: isPortrait, availableHeight: availableHeight)
                    .padding(.horizontal, isPortrait ? 16 : 0)
                    .padding(.vertical, verticalPadding)
                    .frame(maxWidth: isPortrait ? 520 : 980)
                    .frame(maxWidth: .infinity, maxHeight: isPortrait ? .infinity : nil, alignment: isPortrait ? .top : .center)
                    .opacity(gameContentOpacity)
                    .accessibilityHidden(isMainMenuPresented)

                // These two are stacked by declaration order, not by `zIndex`.
                // The window's content has depth now that it holds a board, and
                // in a container with depth a raised `zIndex` lifts a view
                // forward in space — out through the glass, past the rounded
                // corners the window clips its contents to, and in front of the
                // window bar and corner resize grips below.
                if isGameFinished && !isMainMenuPresented && !isEndGameShownOnBoard {
                    endGamePopup
                        .padding(.horizontal, 24)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                }

                // Layered above the game rather than replacing it, so the 3D
                // board's RealityView stays mounted (and warms up) behind the
                // menu; see the ZStack in `gameContent` for why that matters.
                // Mounted, but faded out rather than covered over — see
                // `gameContentOpacity` — so `background` above is the page the
                // menu sits on, and the menu carries no backdrop of its own.
                if isMainMenuPresented {
                    mainMenu
                        .transition(.opacity)
                        .windowDepthOffset(menuDepthOffset)
                }
            }
        }
        .environment(\.mancalaVisualTheme, visualTheme)
        .environment(\.mancalaBoardFlipped, tableRotationDegrees == 180)
        .animation(.spring(response: 0.44, dampingFraction: 0.78), value: game.isGameOver)
        .animation(.spring(response: 0.44, dampingFraction: 0.78), value: challengeFailed)
        .animation(.easeInOut(duration: 0.3), value: isMainMenuPresented)
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
        .sheet(isPresented: $isCustomizePresented) {
            customizeSheet
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
            spatialBoard.onEndGameAction = { action in
                switch action {
                case .primary:
                    if let activeChallenge {
                        startChallenge(activeChallenge)
                    } else {
                        playAgainFromEndGamePopup()
                    }
                case .secondary:
                    returnToChallengeList()
                }
            }
        }
        .onChange(of: spatialSyncState, initial: true) { _, _ in
            syncSpatialBoard()
        }
        .onChange(of: shouldPlaceBoardInSpace, initial: true) { _, wanted in
            setSpatialBoard(open: wanted)
        }
        .onChange(of: spatialBoard.isOpen) { _, isOpen in
            // The volume can also be closed from its own window bar. That's
            // the player putting the board away, same as the button in here,
            // so it's remembered the same way — but only when the board was
            // meant to be out: this also fires when the menu or a theme change
            // is what closed it.
            if !isOpen, shouldPlaceBoardInSpace {
                prefersBoardInSpace = false
            }
        }
        .onChange(of: spatialEndGameBanner, initial: true) { _, banner in
            spatialBoard.endGame = banner
        }
        // Both boards, not just the one in the room: the window's board is lit
        // by the room too. Pushed here rather than through either board's sync
        // so neither view needs a parameter the other platform hasn't got, and
        // so a scene that isn't built yet still gets the level (it keeps it).
        .onChange(of: boardBrightness, initial: true) { _, level in
            boardScene.setBrightness(level)
            spatialBoard.scene.setBrightness(level)
        }
        #endif
        // Watched through a version counter rather than the payload itself:
        // an opponent who plays the same pit twice running sends two updates
        // that compare equal field for field, and the second would be missed.
        .onChange(of: onlineManager.updateVersion) { _, _ in
            Task { await applyPendingOnlineMatchIfNeeded() }
        }
        // Online was picked while Game Center was still signing in. Open
        // matchmaking the moment it lands, and give up on it if sign-in
        // fails or the player has moved on somewhere else in the meantime.
        .onChange(of: onlineManager.state) { _, state in
            guard isAwaitingOnlineMatchmaking else { return }

            guard gameMode == .onlineMultiplayer, !isMainMenuPresented else {
                isAwaitingOnlineMatchmaking = false
                return
            }

            switch state {
            case .ready:
                beginOnlineMatchmaking()
            case .signedOut, .unavailable, .error:
                isAwaitingOnlineMatchmaking = false
            case .matching, .inMatch:
                break
            }
        }
        .onChange(of: onlineManager.matchEnding) { _, ending in
            guard let ending else { return }
            onlineEndingNotice = ending
            onlineManager.clearMatchEnding()
        }
        // An online session is live — there is a minute on the clock — so
        // putting the app away leaves the match rather than parking it, and
        // the opponent hears about it instead of waiting out the timer.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, onlineManager.isInActiveMatch else { return }
            onlineManager.handleAppDidEnterBackground()
            startFreshOnlineSession()
        }
        .confirmationDialog(
            "Leave this online match?",
            isPresented: $isConfirmingOnlineExit,
            titleVisibility: .visible
        ) {
            Button("Leave Match", role: .destructive) {
                onlineManager.leaveCurrentMatch()
                startFreshOnlineSession()
                isMainMenuPresented = true
            }
            Button("Keep Playing", role: .cancel) { }
        } message: {
            Text("\(onlineManager.opponentName) will be told you left, and the match will be forfeited.")
        }
        .alert(
            onlineEndingNotice?.title ?? "",
            isPresented: Binding(
                get: { onlineEndingNotice != nil },
                set: { if !$0 { onlineEndingNotice = nil } }
            ),
            presenting: onlineEndingNotice
        ) { _ in
            Button("New Match") {
                onlineEndingNotice = nil
                startFreshOnlineSession()
                onlineManager.startMatch()
            }
            Button("Main Menu", role: .cancel) {
                onlineEndingNotice = nil
                startFreshOnlineSession()
                isMainMenuPresented = true
            }
        } message: { ending in
            Text(ending.message)
        }
        .perfProbe("ContentView")
        .onChange(of: game.isGameOver || challengeFailed) { _, isFinished in
            guard isFinished else {
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

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: isDarkMode ? darkBackgroundColors : lightBackgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The page behind everything. The Immersive theme gets the chosen
    /// `BoardBackgroundStyle`; the Flat theme keeps the plain warm gradient,
    /// because its whole idea is pits pressed into an undisturbed page.
    @ViewBuilder
    private var background: some View {
        if visualTheme == .liquidGlass {
            BoardBackgroundView(style: boardBackgroundStyle, isDarkMode: isDarkMode)
                .ignoresSafeArea()
        } else {
            backgroundGradient
                .ignoresSafeArea()
        }
    }

    /// How far to hold the main menu back toward the window's glass. The
    /// window's content is as deep as the board asks for, and the menu, being
    /// the last thing in the stack, is laid out at the front of that depth — a
    /// good six inches proud of the window, which is more float than the effect
    /// wants. Nothing to hold back anywhere else: only visionOS has depth.
    private var menuDepthOffset: CGFloat {
        #if os(visionOS)
        return -Board3DView.windowDepth / 2
        #else
        return 0
        #endif
    }

    /// The game stays mounted under the main menu — that's what keeps the 3D
    /// board's RealityView alive and warm — but it's hidden rather than painted
    /// over, so the menu needs no backdrop of its own and `background` above is
    /// the only copy of the page anywhere in the stack.
    ///
    /// visionOS needed this first, for looks: the window's content has depth now
    /// that it holds a board, and a second opaque layer covering the whole
    /// window inside that depth is what stopped the menu reading as a window at
    /// all — square corners where the glass should round them off, and the
    /// window bar and resize grips buried behind it.
    ///
    /// Everywhere else it's about power. Covering the game meant a second
    /// `BoardBackgroundView` behind the menu's copy, and both run their own
    /// `repeatForever` drift; for the busier styles that's two sets of blooms
    /// redrawn every frame with one set permanently out of sight. Hiding the
    /// game instead leaves one.
    private var gameContentOpacity: Double {
        isMainMenuPresented ? 0 : 1
    }

    private var lightBackgroundColors: [Color] {
        [
            Color(red: 0.958, green: 0.945, blue: 0.915),
            Color(red: 0.942, green: 0.926, blue: 0.891),
            Color(red: 0.918, green: 0.898, blue: 0.860)
        ]
    }

    private var darkBackgroundColors: [Color] {
        [
            Color(red: 0.10, green: 0.09, blue: 0.08),
            Color(red: 0.13, green: 0.12, blue: 0.105),
            Color(red: 0.16, green: 0.15, blue: 0.13)
        ]
    }

    private var primaryText: Color {
        isDarkMode ? Color(red: 0.93, green: 0.91, blue: 0.87) : Color(red: 0.26, green: 0.24, blue: 0.21)
    }

    private var secondaryText: Color {
        primaryText.opacity(isDarkMode ? 0.72 : 0.64)
    }

    // Tints feed the liquid-glass surfaces only; the flat theme's soft
    // wells derive their own tones from the page background.
    private var boardTint: Color {
        isDarkMode ? Color.white.opacity(0.09) : Color.white.opacity(0.62)
    }

    private var pitTint: Color {
        isDarkMode ? Color.white.opacity(0.07) : Color.white.opacity(0.22)
    }

    private var playableTint: Color {
        isDarkMode ? Color.cyan.opacity(0.14) : Color.blue.opacity(0.10)
    }

    private var storeTint: Color {
        isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.24)
    }

    private var currentStoreTint: Color {
        isDarkMode ? Color.green.opacity(0.16) : Color.green.opacity(0.10)
    }

    private func displayFont(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    private func countFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        displayFont(size: size, weight: weight).monospacedDigit()
    }

    private var isAIPlayAvailable: Bool {
        true
    }

    /// The finishes the Material picker lists — plus whichever one is in use,
    /// if it's since been withdrawn. Without that, a player who had a withdrawn
    /// finish selected would face a picker with no row matching their setting,
    /// showing blank and giving them nothing to change away from.
    private var shouldShowStatusPanel: Bool {
        gameMode == .singlePlayer || gameMode == .zeroPlayer || gameMode == .onlineMultiplayer
    }

    private var shouldShowUndoButton: Bool {
        // Undo would let the player replay sows without spending challenge
        // moves, so challenges always hide it.
        guard activeChallenge == nil else { return false }

        return switch gameMode {
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

    /// The default theme renders as a real RealityKit board on every platform.
    /// On visionOS it can additionally be lifted out of the window and placed
    /// in the room — the same board either way, so this stays true throughout.
    private var is3DBoardActive: Bool {
        visualTheme == .liquidGlass
    }

    /// True while the board is out in the room rather than in the window, so
    /// the window gives its board slot over to the placement panel.
    private var isBoardPlacedInSpace: Bool {
        #if os(visionOS)
        return is3DBoardActive && spatialBoard.isOpen
        #else
        return false
        #endif
    }

    #if os(visionOS)
    /// Whether the board volume should be open right now. The board starts in
    /// the window and goes out into the room only if that's where the player
    /// last left it — and it comes back in for the main menu, which is a
    /// window's worth of UI on its own and has no board to show.
    private var shouldPlaceBoardInSpace: Bool {
        is3DBoardActive && prefersBoardInSpace && !isMainMenuPresented
    }
    #endif

    /// True while the window is the one drawing the board.
    private var isWindowBoardShown: Bool {
        is3DBoardActive && !isBoardPlacedInSpace && !isBoardSlotObscured
    }

    /// Whether the window board's pixels are actually wanted on screen.
    ///
    /// Distinct from `isWindowBoardShown` only in also standing down for the
    /// main menu, which on iOS hides the board with opacity rather than taking
    /// its slot away. `BoardScene.setRendering` explains why opacity isn't
    /// enough: it hides the board from the player, not from RealityKit, which
    /// keeps shading and lighting it at 60 Hz regardless. This covers the flat
    /// theme too — a player who never chose the 3D board was still paying to
    /// render one.
    private var isBoardRenderingNeeded: Bool {
        isWindowBoardShown && !isMainMenuPresented
    }

    /// True while a sheet or the main menu covers the window.
    ///
    /// The window's content stands in front of the plane those are presented
    /// on, the board most of all, so a board left in its slot comes out in
    /// front of them rather than behind. It clears for the duration instead:
    /// there's no putting it behind a sheet.
    ///
    /// The header's menu isn't in this list — it opens clear of the window
    /// entirely, so there's nothing for the board to be in front of.
    private var isBoardSlotObscured: Bool {
        #if os(visionOS)
        return isSettingsPresented
            || isGameHistoryPresented
            || isRulesPresented
            || isCustomizePresented
            || isMainMenuPresented
        #else
        return false
        #endif
    }

    /// The scene that stone-flight animations should target, when one is live.
    private var activeBoardScene: BoardScene? {
        guard is3DBoardActive else { return nil }
        return isBoardPlacedInSpace ? spatialBoardScene : boardScene
    }

    /// The volume's scene on visionOS; never reached elsewhere.
    private var spatialBoardScene: BoardScene {
        #if os(visionOS)
        return spatialBoard.scene
        #else
        return boardScene
        #endif
    }

    /// Pits the local player may tap right now; mirrors `pitButton`'s
    /// enablement predicate for the 3D board's highlight rings.
    private var playablePitSet: Set<Int> {
        guard !isAnimatingMove, !isAIMovePending, !challengeFailed else { return [] }
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
        if let activeChallenge {
            return activeChallenge.aiDifficulty
        }

        return switch gameMode {
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

    /// The player beat the active challenge: won the game without exceeding
    /// the sow budget.
    private var isChallengeWon: Bool {
        guard let activeChallenge else { return false }
        return game.winner == .playerOne && challengeMovesUsed <= activeChallenge.moveLimit
    }

    /// The game reached an end state worth reporting — either finished, or a
    /// challenge that ran out of moves before it could finish.
    private var isGameFinished: Bool {
        game.isGameOver || challengeFailed
    }

    /// True while the result belongs on the board itself rather than in a panel
    /// over the window. Out in the room, a window popup would be behind the
    /// player rather than where they're looking; in the window, a flat panel
    /// gets run through by a board that leans out toward the viewer. Either
    /// way the board is the place for it, and it's carried there by
    /// `spatialEndGameBanner`.
    private var isEndGameShownOnBoard: Bool {
        #if os(visionOS)
        return is3DBoardActive
        #else
        return false
        #endif
    }

    private var endGameTitle: String {
        if activeChallenge != nil {
            if isChallengeWon {
                return "Challenge Complete"
            }
            return challengeFailed && !game.isGameOver ? "Out of Moves" : "Challenge Failed"
        }

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
        if let activeChallenge {
            if isChallengeWon {
                return "Solved in \(challengeMovesUsed) of \(activeChallenge.moveLimit) moves"
            }
            if challengeFailed && !game.isGameOver {
                return "All \(activeChallenge.moveLimit) moves spent"
            }
        }

        return "\(game.storeCount(for: .playerOne)) - \(game.storeCount(for: .playerTwo))"
    }

    /// Label for the "start over" button, shared by the window popup and the
    /// board's floating banner so the two never drift apart.
    private var endGamePrimaryActionTitle: String {
        if activeChallenge != nil {
            return isChallengeWon ? "Play Again" : "Try Again"
        }
        return gameMode == .onlineMultiplayer ? "Play Again Online" : "Play Again"
    }

    private var endGameSymbolColor: Color {
        if activeChallenge != nil, !isChallengeWon {
            return Color.secondary
        }
        if game.isDraw {
            return Color.secondary
        }
        return visualTheme == .flat ? Color.black : Color.yellow
    }

    private var endGameSymbolName: String {
        if activeChallenge != nil {
            return isChallengeWon ? "checkmark.seal.fill" : "xmark.seal.fill"
        }

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
        if let activeChallenge, !game.isGameOver {
            if challengeFailed {
                return "Out of moves"
            }
            if game.currentPlayer == .playerOne {
                let remaining = max(0, activeChallenge.moveLimit - challengeMovesUsed)
                return remaining == 1 ? "1 move left" : "\(remaining) moves left"
            }
            return "\(displayName(for: .playerTwo))'s turn"
        }

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
        let scoreRowHeight: CGFloat = isPortrait ? 70 : 0
        let scoreRowSpacing = isPortrait ? contentSpacing : 0
        let boardHeight = max(260, availableHeight - headerHeight - statusHeight - contentSpacing - visibleStatusSpacing - scoreRowHeight - scoreRowSpacing)
        let portraitStoreHeight = min(54, max(38, boardHeight * 0.10))
        let portraitPitHeight = max(34, (boardHeight - 24 - 20 - (portraitStoreHeight * 2) - 40) / 6)

        return VStack(spacing: contentSpacing) {
            header(isPortrait: isPortrait)
                .frame(height: headerHeight)

            ZStack {
                // Kept mounted at all times, even when another theme or the
                // placed board is what's on screen: tearing down and recreating
                // the RealityView loses the RealityKit scene the persisted
                // `BoardScene` entity graph was attached to, so reusing that
                // graph in a freshly recreated RealityView renders nothing.
                // Hiding it in place avoids ever destroying it — and means the
                // board is warm the moment it's called for.
                board3DSection(isPortrait: isPortrait, boardHeight: boardHeight)
                    .padding(.horizontal, windowBoardInset(isPortrait: isPortrait))
                    .opacity(isWindowBoardShown ? 1 : 0)
                    .allowsHitTesting(isWindowBoardShown)
                    .accessibilityHidden(!isWindowBoardShown)

                #if os(visionOS)
                if isBoardPlacedInSpace {
                    // Clears for sheets and the main menu, the same as the
                    // board it stands in for: the window's content is in front
                    // of the plane they're presented on, so it reads through
                    // them rather than behind. Not for the header's menu, which
                    // opens clear of the window and has nothing to collide
                    // with.
                    spatialBoardPlaceholder(boardHeight: boardHeight)
                        .opacity(isBoardSlotObscured ? 0 : 1)
                }
                #endif

                if !is3DBoardActive {
                    twoDimensionalBoard(isPortrait: isPortrait, boardHeight: boardHeight, portraitPitHeight: portraitPitHeight, portraitStoreHeight: portraitStoreHeight)
                }
            }

            if isPortrait {
                scoreRow
                    .frame(height: scoreRowHeight)
            }

            if isPortrait && shouldShowStatusPanel {
                statusPanel
                    .frame(height: statusHeight)
            }
        }
    }

    private func twoDimensionalBoard(isPortrait: Bool, boardHeight: CGFloat, portraitPitHeight: CGFloat, portraitStoreHeight: CGFloat) -> some View {
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

    #if os(visionOS)
    /// Fills the window's board slot while the real board sits anchored out in
    /// the room; the window keeps score, status, and controls.
    private func spatialBoardPlaceholder(boardHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            if spatialBoard.scene.isBuilt {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)

                Text("The board is placed in your space")
                    .font(.headline)
                    .foregroundStyle(primaryText)

                Text("Touch a pit — or look at it and pinch — to sow. Use the handle below the board to move it or snap it onto a surface. Pinch the wood and swing or twist your hand to turn the board, or pinch it with both hands to resize it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)

                boardPlacementControls
            } else {
                // Mesh/texture generation can take a visible moment, especially
                // on first launch — say so instead of leaving an empty room.
                ProgressView()
                    .controlSize(.large)

                Text("Preparing board…")
                    .font(.headline)
                    .foregroundStyle(primaryText)
            }

            Button {
                prefersBoardInSpace = false
            } label: {
                Label("Return Board to Window", systemImage: "arrow.down.forward.and.arrow.up.backward")
            }
            .buttonStyle(.bordered)
        }
        .animation(.easeInOut(duration: 0.28), value: spatialBoard.scene.isBuilt)
        .frame(maxWidth: .infinity)
        .frame(height: boardHeight)
    }

    /// Quarter-turn and size buttons for players who'd rather not reach out and
    /// handle the board — and the discoverable half of both gestures, since
    /// neither a twist nor a two-handed pinch is something you'd think to try
    /// unprompted.
    private var boardPlacementControls: some View {
        HStack(spacing: 10) {
            Button {
                spatialBoard.rotateBoard(by: .pi / 2)
                hapticTrigger += 1
            } label: {
                Label("Turn Left", systemImage: "rotate.left")
            }

            Button {
                spatialBoard.rotateBoard(by: -.pi / 2)
                hapticTrigger += 1
            } label: {
                Label("Turn Right", systemImage: "rotate.right")
            }

            Divider()
                .frame(height: 22)

            Button {
                spatialBoard.scaleBoard(by: 1 / 1.15)
                hapticTrigger += 1
            } label: {
                Label("Smaller", systemImage: "minus.magnifyingglass")
            }
            .disabled(spatialBoard.boardScale <= SpatialBoardModel.BoardScaleRange.minimum)

            Button {
                spatialBoard.scaleBoard(by: 1.15)
                hapticTrigger += 1
            } label: {
                Label("Bigger", systemImage: "plus.magnifyingglass")
            }
            .disabled(spatialBoard.boardScale >= SpatialBoardModel.BoardScaleRange.maximum)
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Turn and resize the board")
    }

    /// The result panel the board carries — floating above it out in the room,
    /// standing in front of it in the window. `nil` while the game is still
    /// running, while the menu is up, or when there's no 3D board to carry it.
    private var spatialEndGameBanner: SpatialBoardModel.EndGameBanner? {
        guard is3DBoardActive, isGameFinished, !isMainMenuPresented else { return nil }

        return SpatialBoardModel.EndGameBanner(
            title: endGameTitle,
            subtitle: endGameSubtitle,
            symbolName: endGameSymbolName,
            symbolColor: endGameSymbolColor,
            primaryTitle: endGamePrimaryActionTitle,
            secondaryTitle: activeChallenge != nil ? "Challenges" : nil
        )
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
            material: boardMaterialStyle,
            stoneSet: stoneSetStyle
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
            material: state.material,
            stoneSet: state.stoneSet
        )
    }

    private func setSpatialBoard(open: Bool) {
        if open, !spatialBoard.isOpen {
            openWindow(id: SpatialBoardModel.windowID)
        } else if !open, spatialBoard.isOpen {
            dismissWindow(id: SpatialBoardModel.windowID)
        }
    }
    #endif

    /// How far the window's board reaches past `gameContent`'s horizontal
    /// inset. Negative on iOS, so the board spans the full screen width and can
    /// travel to the real edges when parallax tilts it while the header and
    /// status stay inset — and only while it's actually shown, so the hidden
    /// layer doesn't widen the ZStack when the 2D board is up.
    ///
    /// Zero on visionOS, where the board is 3D content standing in front of the
    /// glass and keeps its own clearance from the edges of its slot (see
    /// `Board3DView.fitBoard`). Insetting the slot there would make it taller
    /// than the height the layout budgeted, pushing the score row and status
    /// panel off the bottom of the window.
    private func windowBoardInset(isPortrait: Bool) -> CGFloat {
        #if os(visionOS)
        return 0
        #else
        return isWindowBoardShown ? (isPortrait ? -16 : -10) : 0
        #endif
    }

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
            stoneSet: stoneSetStyle,
            scene: boardScene
        )
        .frame(height: isPortrait ? boardHeight : nil)
        .frame(maxHeight: isPortrait ? nil : .infinity)
        .overlay {
            if !boardScene.isBuilt {
                boardLoadingOverlay
            } else if boardScene.isSwitchingMaterial {
                materialSwitchOverlay
            }
        }
        .animation(.easeInOut(duration: 0.28), value: boardScene.isBuilt)
        .animation(.easeInOut(duration: 0.2), value: boardScene.isSwitchingMaterial)
        .onAppear {
            boardScene.onPitTapped = { index in
                Task { await animateMove(from: index) }
            }
            boardScene.setRendering(isBoardRenderingNeeded)
            #if !os(visionOS)
            updateMotionParallax()
            #endif
        }
        .onChange(of: isBoardRenderingNeeded) { _, needed in
            boardScene.setRendering(needed)
        }
        #if !os(visionOS)
        // Parallax leans the board with the device; there's no device to lean
        // on visionOS, where moving your head does the same job for real.
        .onDisappear {
            motionParallax.stop()
        }
        .onChange(of: shouldRunMotionParallax) { _, _ in
            updateMotionParallax()
        }
        #endif
    }

    /// Shown over the board area while `BoardScene` is still building its
    /// entity graph — mesh generation, texture baking, and (on first launch
    /// in particular) the RealityKit engine's own render-graph warm-up can
    /// take long enough that an unlabeled blank board reads as a freeze.
    private var boardLoadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text("Preparing 3D board…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryText)
        }
        .padding(24)
        .frame(minWidth: 220)
        .mancalaGlassEffect(tint: storeTint, cornerRadius: 20, role: .panel)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing 3D board")
    }

    /// Safety net for the rare case a material is selected before
    /// `BoardScene.prewarmRemainingMaterials()` has cached it — normally every
    /// finish is baked shortly after launch, so switching in Settings is an
    /// instant cache hit and this never appears.
    private var materialSwitchOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()

            Text("Applying material…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(primaryText)
        }
        .padding(16)
        .mancalaGlassEffect(tint: storeTint, cornerRadius: 16, role: .panel)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Applying material")
    }

    #if !os(visionOS)
    /// Device motion is only worth running while the board is actually on
    /// screen and the app is in front.
    ///
    /// The board deliberately stays mounted under the main menu — that's what
    /// keeps its `RealityView` warm — so `onDisappear` never fires while the
    /// menu is up. Left ungated, the gyro streams at 60 Hz for as long as the
    /// player sits on the menu, and every sample writes a camera transform into
    /// a RealityKit scene nobody can see, which keeps the renderer from ever
    /// going idle. Sensor power plus a pinned render loop, all for a hidden
    /// board.
    private var shouldRunMotionParallax: Bool {
        gyroMotionEnabled && !isMainMenuPresented && scenePhase == .active
    }

    private func updateMotionParallax() {
        guard shouldRunMotionParallax else {
            motionParallax.stop()
            // Only neutralize the camera when the player turned parallax off.
            // Pausing for the menu or a trip to the background leaves the pose
            // alone, so the board doesn't visibly snap upright as it fades out;
            // the first sample after resuming re-zeroes it anyway.
            if !gyroMotionEnabled {
                boardScene.setParallax(yaw: 0, pitch: 0)
            }
            return
        }

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
                    .foregroundStyle(endGameSymbolColor)
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

            if let activeChallenge {
                VStack(spacing: 10) {
                    Button {
                        startChallenge(activeChallenge)
                    } label: {
                        Label(endGamePrimaryActionTitle, systemImage: "arrow.counterclockwise")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .mancalaGlassEffect(tint: playableTint, cornerRadius: 18, role: .control, interactive: true)

                    Button {
                        returnToChallengeList()
                    } label: {
                        Label("Challenges", systemImage: "list.bullet")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .mancalaGlassEffect(tint: storeTint, cornerRadius: 18, role: .control, interactive: true)
                }
            } else {
                Button {
                    playAgainFromEndGamePopup()
                } label: {
                    Label(endGamePrimaryActionTitle, systemImage: "arrow.counterclockwise")
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

    // MARK: Main menu

    /// The screen shown on launch (and via the header menu): the game keeps
    /// running—and the 3D board keeps warming up—underneath, faded out rather
    /// than covered over (see `gameContentOpacity`), so the page background
    /// behind everything shows through and the menu needs no backdrop of its
    /// own.
    private var mainMenu: some View {
        Group {
            if isMainMenuShowingChallenges {
                challengeListPage
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainMenuPage
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isMainMenuShowingChallenges)
        .accessibilityElement(children: .contain)
    }

    /// Fixed (never scrolling) landing page—the mode list is short enough to
    /// always fit, and a bouncing title reads as a bug rather than a feature.
    private var mainMenuPage: some View {
        VStack(spacing: 30) {
            mainMenuHeader

            VStack(spacing: 12) {
                ForEach(GameMode.allCases) { mode in
                    mainMenuModeButton(for: mode)
                }

                mainMenuChallengesButton
            }

            mainMenuUtilityRow
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
    }

    private var mainMenuHeader: some View {
        // Tight spacing: the pebble stage carries its own vertical breathing
        // room so the pebbles have somewhere to roam. The negative padding
        // gives back layout height the roaming rarely uses—pebbles still draw
        // into the surrounding whitespace, they just stop reserving it, which
        // matters on a page that never scrolls.
        VStack(spacing: 2) {
            MenuPebbleStage(color: { stoneColor(for: $0) }, isDarkMode: isDarkMode)
                .padding(.vertical, -6)

            VStack(spacing: 6) {
                Text(AppInfo.name)
                    .font(displayFont(size: 52, weight: .medium))
                    .foregroundStyle(primaryText)

                Text("A GAME OF SOWING AND CAPTURE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(secondaryText.opacity(0.9))
            }
        }
    }

    private func mainMenuModeButton(for mode: GameMode) -> some View {
        let isCurrent = mode == gameMode

        return Button {
            startGameFromMenu(mode)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: menuSymbolName(for: mode))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(primaryText)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(menuTitle(for: mode))
                        .font(displayFont(size: 19, weight: .semibold))
                        .foregroundStyle(primaryText)

                    Text(menuSubtitle(for: mode))
                        .font(.footnote)
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryText.opacity(0.7))
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .mancalaGlassEffect(tint: isCurrent ? playableTint : pitTint, cornerRadius: 18, role: .control, interactive: true)
        .accessibilityLabel("\(menuTitle(for: mode)). \(menuSubtitle(for: mode))")
    }

    private var mainMenuChallengesButton: some View {
        let completedCount = ChallengeCatalog.all.count { completedChallengeIDs.contains($0.id) }

        return Button {
            isMainMenuShowingChallenges = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(primaryText)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Challenges")
                        .font(displayFont(size: 19, weight: .semibold))
                        .foregroundStyle(primaryText)

                    Text(completedCount == 0
                         ? "Puzzle boards with move limits"
                         : "\(completedCount) of \(ChallengeCatalog.all.count) complete")
                        .font(.footnote)
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryText.opacity(0.7))
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .mancalaGlassEffect(tint: activeChallenge != nil ? playableTint : pitTint, cornerRadius: 18, role: .control, interactive: true)
        .accessibilityLabel("Challenges. \(completedCount) of \(ChallengeCatalog.all.count) complete")
    }

    /// Only the challenge rows scroll—the catalog grows over time, but the
    /// title and the way back out stay pinned.
    private var challengeListPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Challenges")
                    .font(displayFont(size: 40, weight: .medium))
                    .foregroundStyle(primaryText)

                Text("WIN WITHIN THE MOVE LIMIT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(secondaryText.opacity(0.9))
            }
            .padding(.horizontal, 28)
            .padding(.top, 32)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(Array(ChallengeCatalog.all.enumerated()), id: \.element.id) { index, challenge in
                        challengeRow(challenge, number: index + 1)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                isMainMenuShowingChallenges = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))

                    Text("MENU")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                }
                .foregroundStyle(secondaryText)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .hoverShape(cornerRadius: 14)
            .accessibilityLabel("Back to menu")
            .padding(.bottom, 32)
        }
    }

    private func challengeRow(_ challenge: MancalaChallenge, number: Int) -> some View {
        let isCompleted = completedChallengeIDs.contains(challenge.id)

        return Button {
            startChallenge(challenge)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isCompleted ? "checkmark.seal.fill" : "\(number).circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isCompleted ? Color.green.opacity(isDarkMode ? 0.85 : 0.75) : primaryText)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .font(displayFont(size: 18, weight: .semibold))
                        .foregroundStyle(primaryText)

                    Text(challenge.subtitle)
                        .font(.footnote)
                        .foregroundStyle(secondaryText)

                    Text("\(challenge.moveLimit) \(challenge.moveLimit == 1 ? "move" : "moves") • \(challenge.aiDifficulty.title) AI\(isCompleted ? " • Completed" : "")")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(secondaryText.opacity(0.85))
                        .padding(.top, 2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryText.opacity(0.7))
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .mancalaGlassEffect(tint: isCompleted ? currentStoreTint : pitTint, cornerRadius: 18, role: .control, interactive: true)
        .accessibilityLabel("\(challenge.title). \(challenge.subtitle). \(challenge.moveLimit) moves against \(challenge.aiDifficulty.title) AI.\(isCompleted ? " Completed." : "")")
    }

    /// Four across now, so the buttons share the row's width rather than each
    /// claiming a fixed 72pt — four fixed slots plus their spacing overflows an
    /// SE-class screen, and this row has no scroll to fall back on.
    private var mainMenuUtilityRow: some View {
        HStack(spacing: 6) {
            mainMenuUtilityButton("Rules", systemImage: "book.closed") {
                isRulesPresented = true
            }

            mainMenuUtilityButton("History", systemImage: "clock.arrow.circlepath") {
                isGameHistoryPresented = true
            }

            mainMenuUtilityButton("Customize", systemImage: "paintpalette") {
                isCustomizePresented = true
            }

            mainMenuUtilityButton("Settings", systemImage: "gearshape") {
                isSettingsPresented = true
            }
        }
    }

    private func mainMenuUtilityButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .medium))

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    // "CUSTOMIZE" is the widest label by some way; let it shrink
                    // on narrow screens instead of truncating to "CUSTOMIZ…".
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverShape(cornerRadius: 16)
        .accessibilityLabel(title)
    }

    private func menuTitle(for mode: GameMode) -> String {
        switch mode {
        case .twoPlayer:
            "2 Players"
        case .singlePlayer:
            "1 Player"
        case .zeroPlayer:
            "0 Player"
        case .onlineMultiplayer:
            "Online"
        }
    }

    private func menuSubtitle(for mode: GameMode) -> String {
        if hasResumableGame(for: mode) {
            return "Continue your game"
        }

        switch mode {
        case .twoPlayer:
            return "Pass and play with a friend"
        case .singlePlayer:
            return "Face the AI opponent"
        case .zeroPlayer:
            return "Watch two AIs battle"
        case .onlineMultiplayer:
            return "A Game Center match"
        }
    }

    private func menuSymbolName(for mode: GameMode) -> String {
        switch mode {
        case .twoPlayer:
            "person.2"
        case .singlePlayer:
            "person"
        case .zeroPlayer:
            "cpu"
        case .onlineMultiplayer:
            "globe"
        }
    }

    /// A saved game worth advertising as "continue": in progress and not still
    /// on the untouched opening layout (fresh boards are persisted too).
    private func hasResumableGame(for mode: GameMode) -> Bool {
        guard let saved = savedGameState(for: mode), !saved.game.isGameOver else {
            return false
        }
        return saved.game.pits != MancalaGame().pits
    }

    private func openMainMenu() {
        if gameMode == .zeroPlayer {
            isZeroPlayerPaused = true
        }

        // Leaving a live online match forfeits it and drops the opponent, so
        // it takes a deliberate second tap.
        if gameMode == .onlineMultiplayer, onlineManager.isInActiveMatch, !game.isGameOver {
            isConfirmingOnlineExit = true
            return
        }

        isMainMenuPresented = true
    }

    /// Puts the online board back to the opening layout. Every online session
    /// starts here: a match nobody has moved in yet carries no board of its
    /// own, and whatever the last session left behind belongs to that session,
    /// not this one.
    private func startFreshOnlineSession() {
        pendingOnlineMoveIndices.removeAll()
        isReplayingOnlineMove = false
        appliedOnlineMatchID = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            game.reset(startingPlayer: .playerOne)
            undoHistory.removeAll()
            flyingStone = nil
            hintedPitIndex = nil
            isAnimatingMove = false
            isAIMovePending = false
            hasRecordedCurrentCompletedGame = false
            endGameAnimationPulse = false
        }
    }

    private func startGameFromMenu(_ mode: GameMode) {
        isMainMenuPresented = false
        isMainMenuShowingChallenges = false

        if activeChallenge != nil {
            // The challenge board was never persisted, so restoring the chosen
            // mode's save discards it. Ordering matters: `switchGameMode`
            // persists the outgoing game, and the active challenge is what
            // suppresses saving the puzzle board over the mode's own save.
            let oldMode = gameMode
            gameMode = mode
            switchGameMode(from: oldMode, to: mode)
            clearChallengeState()

            if mode == .onlineMultiplayer {
                beginOnlineMatchmaking()
            }
            return
        }

        if mode != gameMode {
            let oldMode = gameMode
            gameMode = mode
            switchGameMode(from: oldMode, to: mode)
        } else {
            Task {
                await runAIMoveIfNeeded()
            }
        }

        if mode == .onlineMultiplayer {
            beginOnlineMatchmaking()
        }
    }

    /// Picking Online goes straight to Game Center matchmaking. The board on
    /// its own offers nothing to tap, and an opponent is the one thing an
    /// online session can't start without.
    private func beginOnlineMatchmaking() {
        // A live match is what the player is coming back to; don't reset the
        // board out from under it to go looking for another opponent.
        guard !onlineManager.isInActiveMatch else {
            isAwaitingOnlineMatchmaking = false
            return
        }

        guard onlineManager.isReadyToPlayOnline else {
            // Sign-in is kicked off at launch and may still be in flight, so
            // wait for it rather than sending the player to find the way in.
            isAwaitingOnlineMatchmaking = true
            onlineManager.authenticateLocalPlayer()
            return
        }

        isAwaitingOnlineMatchmaking = false
        startFreshOnlineSession()
        onlineManager.startMatch()
    }

    // MARK: Challenges

    private var completedChallengeIDs: Set<String> {
        Set(completedChallengeIDsStorage.split(separator: ",").map(String.init))
    }

    private func markChallengeCompleted(_ id: String) {
        var ids = completedChallengeIDs
        ids.insert(id)
        completedChallengeIDsStorage = ids.sorted().joined(separator: ",")
    }

    private var challengeMovesRemaining: Int {
        guard let activeChallenge else { return 0 }
        return max(0, activeChallenge.moveLimit - challengeMovesUsed)
    }

    private func clearChallengeState() {
        activeChallenge = nil
        challengeMovesUsed = 0
        challengeFailed = false
    }

    private func startChallenge(_ challenge: MancalaChallenge) {
        // Keep the save of whatever regular game is being left behind; a
        // restart mid-challenge must not write the puzzle board anywhere.
        if activeChallenge == nil {
            persistStableGameState()
        }
        cancelAIThinking(shouldLog: false)
        isMainMenuPresented = false
        // Challenges ride the single-player machinery: the AI owns the far
        // side and per-challenge difficulty overrides the settings value.
        gameMode = .singlePlayer

        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            activeChallenge = challenge
            challengeMovesUsed = 0
            challengeFailed = false
            endGameAnimationPulse = false
            game = challenge.freshGame
            undoHistory.removeAll()
            flyingStone = nil
            hintedPitIndex = nil
            isAnimatingMove = false
            isAIMovePending = false
            hasRecordedCurrentCompletedGame = false
        }
    }

    /// Reopens the menu directly on the challenge page. The finished (or
    /// stranded) challenge board stays behind the menu; picking anything from
    /// the menu replaces it.
    private func returnToChallengeList() {
        cancelAIThinking(shouldLog: false)
        isMainMenuShowingChallenges = true
        isMainMenuPresented = true
    }

    /// Called after every completed sow — the player's and the AI's response
    /// alike — once the board has settled.
    private func evaluateChallengeAfterMove() {
        guard let activeChallenge else { return }

        if game.isGameOver {
            if isChallengeWon {
                markChallengeCompleted(activeChallenge.id)
            }
            return
        }

        if challengeMovesUsed >= activeChallenge.moveLimit,
           game.currentPlayer == .playerOne,
           !isAIMovePending,
           !isAnimatingMove {
            challengeFailed = true
        }
    }

    private var difficultyPill: some View {
        var title: String
        var accessibilityLabel: String

        switch gameMode {
        case .singlePlayer:
            title = difficulty.title
            accessibilityLabel = "Difficulty: \(difficulty.title)"
        case .zeroPlayer:
            title = "\(zeroPlayerOneDifficulty.title) vs \(zeroPlayerTwoDifficulty.title)"
            accessibilityLabel = "Zero player mode. Player 1 \(zeroPlayerOneDifficulty.title), Player 2 \(zeroPlayerTwoDifficulty.title)"
        case .twoPlayer:
            title = "2 Players"
            accessibilityLabel = "Two player mode"
        case .onlineMultiplayer:
            title = "Online"
            accessibilityLabel = "Online multiplayer mode"
        }

        if let activeChallenge {
            title = "Challenge • \(activeChallenge.title)"
            accessibilityLabel = "Challenge: \(activeChallenge.title)"
        }

        // The design keeps chrome quiet: the mode reads as a small
        // letterspaced caption under the title, not a bordered pill.
        return Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(2.4)
            .foregroundStyle(secondaryText.opacity(0.9))
            .accessibilityLabel(accessibilityLabel)
    }

    /// The overflow menu behind the header's gear.
    ///
    /// A plain `Menu` everywhere but visionOS. There, the window's content
    /// stands in front of the plane the system presents menus on — the board
    /// most of all — so the menu comes out from behind the board and the panel
    /// beneath it. Nothing reports when a `Menu` opens, so there's no moment to
    /// clear the way; a popover driven by state gives us one.
    @ViewBuilder
    private var headerOverflowMenu: some View {
        #if os(visionOS)
        Button {
            isHeaderMenuPresented = true
        } label: {
            headerIcon("gearshape")
        }
        .buttonStyle(.plain)
        .hoverShape(Circle())
        .accessibilityLabel("More options")
        .popover(isPresented: $isHeaderMenuPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                headerMenuItems
            }
            .buttonStyle(.plain)
            .labelStyle(HeaderMenuLabelStyle())
            .padding(.vertical, 10)
            .frame(width: 260)
        }
        #else
        Menu {
            headerMenuItems
        } label: {
            headerIcon("gearshape")
        }
        .buttonStyle(.plain)
        .hoverShape(Circle())
        .accessibilityLabel("More options")
        #endif
    }

    /// Shared by both presentations, so the two can't drift apart.
    @ViewBuilder
    private var headerMenuItems: some View {
        Button {
            dismissHeaderMenu()
            openMainMenu()
        } label: {
            Label("Main Menu", systemImage: "house")
        }

        Button {
            dismissHeaderMenu()
            isRulesPresented = true
        } label: {
            Label("Rules", systemImage: "book.closed")
        }

        Button {
            dismissHeaderMenu()
            requestHint()
        } label: {
            Label(isHintSearching ? "Finding Hint" : "Hint", systemImage: "lightbulb")
        }
        .disabled(!canRequestHint)

        Button {
            dismissHeaderMenu()
            isGameHistoryPresented = true
        } label: {
            Label("Game History", systemImage: "clock.arrow.circlepath")
        }

        Button {
            dismissHeaderMenu()
            isCustomizePresented = true
        } label: {
            Label("Customize", systemImage: "paintpalette")
        }

        Button {
            dismissHeaderMenu()
            isSettingsPresented = true
        } label: {
            Label("Settings", systemImage: "gearshape")
        }

        Button(role: .destructive) {
            dismissHeaderMenu()
            resetCurrentGame()
        } label: {
            Label("Reset Game", systemImage: "arrow.counterclockwise")
        }
        .disabled(isAnimatingMove || gameMode == .onlineMultiplayer)
    }

    /// A `Menu` closes itself when an item is chosen; the popover doesn't.
    private func dismissHeaderMenu() {
        #if os(visionOS)
        isHeaderMenuPresented = false
        #endif
    }

    private func headerIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(primaryText)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .playerFacingRotation(tableRotationDegrees)
    }

    private func headerTitle(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(AppInfo.name)
                .font(displayFont(size: 32, weight: .medium))
                .foregroundStyle(primaryText)

            difficultyPill
        }
        .playerFacingRotation(tableRotationDegrees)
    }

    private func header(isPortrait: Bool) -> some View {
        ZStack {
            // Portrait centers the title in the safe area like the design;
            // landscape keeps it leading so the status panel can sit centered.
            if isPortrait {
                headerTitle(alignment: .center)
            }

            HStack(alignment: .center, spacing: 2) {
                if !isPortrait {
                    headerTitle(alignment: .leading)
                }

                if shouldShowUndoButton {
                    Button {
                        undoLastTurn()
                    } label: {
                        headerIcon("arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .hoverShape(Circle())
                    .opacity(canUndoTurn ? 1 : 0.35)
                    .disabled(!canUndoTurn)
                    .accessibilityLabel("Undo last turn")
                }

                if gameMode == .zeroPlayer {
                    Button {
                        toggleZeroPlayerPlayback()
                    } label: {
                        headerIcon(isZeroPlayerPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.plain)
                    .hoverShape(Circle())
                    .opacity(isAnimatingMove || game.isGameOver ? 0.35 : 1)
                    .disabled(isAnimatingMove || game.isGameOver)
                    .accessibilityLabel(isZeroPlayerPaused ? "Play zero player game" : "Pause zero player game")
                }

                Spacer()

                if !isPortrait && shouldShowStatusPanel {
                    statusPanel
                        .frame(maxWidth: isThoughtPanelExpanded ? 360 : 260)

                    Spacer()
                }

                #if os(visionOS)
                if visualTheme == .liquidGlass {
                    Button {
                        prefersBoardInSpace.toggle()
                    } label: {
                        // Follows the preference rather than the volume, so the
                        // button answers the tap that set it instead of waiting
                        // a frame for the window to come and go.
                        headerIcon(prefersBoardInSpace ? "arrow.down.forward.and.arrow.up.backward" : "cube")
                    }
                    .buttonStyle(.plain)
                    .hoverShape(Circle())
                    .accessibilityLabel(prefersBoardInSpace ? "Return board to window" : "Place board in your space")
                }
                #endif

                headerOverflowMenu
            }
        }
    }

    /// Shared by both entry points — the main menu's utility row and the
    /// in-game header menu. Deliberately not in Settings: this is a place you go
    /// to look at things, not a preference you set in passing.
    private var customizeSheet: some View {
        NavigationStack {
            CustomizeView()
                .navigationTitle("Customize")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isCustomizePresented = false
                        }
                    }
                }
        }
    }

    /// Whether the settings sheet is speaking for a game in progress.
    ///
    /// Opened from the main menu there is no chosen mode: `gameMode` still
    /// holds whichever mode was played last, so its sections read as settings
    /// for a mode the player hasn't picked (two difficulty pickers after a
    /// 0 Player game). The menu's Settings therefore shows only what applies
    /// to every mode; per-mode settings live in that mode's own Settings.
    private var showsModeSpecificSettings: Bool {
        !isMainMenuPresented
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                if showsModeSpecificSettings {
                    difficultySettingsSections
                }

                appearanceSettingsSection

                if showsModeSpecificSettings {
                    nameSettingsSection
                    twoPlayerSettingsSections
                }

                gameCenterSettingsSection

                if showsModeSpecificSettings {
                    onlineSettingsSections
                    computerOpponentSettingsSections
                }

                developerSettingsSection
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
        // The dev menu is a list to scroll and a preview to watch, neither of
        // which fits in half a sheet.
        .presentationDetents(PebbleDevMenu.isEnabled || OnlineDevMenu.isEnabled ? [.medium, .large] : [.medium])
    }

    /// Present only while `PebbleDevMenu.isEnabled`; see that flag for what it
    /// costs when it's off, which is nothing.
    @ViewBuilder
    private var developerSettingsSection: some View {
        if PebbleDevMenu.isEnabled || OnlineDevMenu.isEnabled {
            Section("Developer") {
                if PebbleDevMenu.isEnabled {
                    NavigationLink("Pebble Animations") {
                        MenuPebbleDevMenuView(color: { stoneColor(for: $0) }, isDarkMode: isDarkMode)
                    }

                    Text("Preview each of the main menu's pebble animations on its own, and take any of them out of the loop.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if OnlineDevMenu.isEnabled {
                    NavigationLink("Online Match Simulator") {
                        OnlineMatchSimulatorView(settings: OnlineDevMenu.settings, manager: onlineManager)
                    }

                    Text("Play an online session through on one device, against a local stand-in for the far phone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var difficultySettingsSections: some View {
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

                if let modelAvailabilityMessage {
                    Text(modelAvailabilityMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else if gameMode == .zeroPlayer {
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

                if let modelAvailabilityMessage {
                    Text(modelAvailabilityMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var appearanceSettingsSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $visualTheme) {
                ForEach(VisualTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)

            Text(visualTheme == .flat ? "Soft and minimal — pits pressed right into the page, no board." : "A 3D board with several textures to choose from.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if visualTheme == .liquidGlass {
                #if os(visionOS)
                Picker("Board Brightness", selection: $boardBrightness) {
                    ForEach(BoardBrightness.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Text(boardBrightness.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #else
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
    }

    /// Names are stored per mode, so this belongs with the rest of the
    /// mode-specific settings rather than on the menu's global sheet.
    private var nameSettingsSection: some View {
        Section("Names") {
            TextField("Player 1", text: currentPlayerOneNameBinding)
                .mancalaNameTextFieldStyle()

            TextField("Player 2", text: currentPlayerTwoNameBinding)
                .mancalaNameTextFieldStyle()

            Text("Leave a field blank to use its default name.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var twoPlayerSettingsSections: some View {
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
    }

    private var gameCenterSettingsSection: some View {
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

            // No "Start Online Match" here: matchmaking opens on its own when
            // Online is picked from the menu, and again from the end-of-match
            // notice, so a copy buried in Settings is one the player would
            // never need to find.
            if showsModeSpecificSettings, gameMode == .onlineMultiplayer, onlineManager.isInActiveMatch {
                Button("Forfeit Online Match", role: .destructive) {
                    onlineManager.leaveCurrentMatch()
                    startFreshOnlineSession()
                }
            }
        }
    }

    @ViewBuilder
    private var onlineSettingsSections: some View {
        if gameMode == .onlineMultiplayer {
            Section("Display") {
                Toggle("Show Numbers", isOn: $onlineShowNumberLabels)

                Text("Shows the stone counts in each pit and store.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Match Rules") {
                Text("Each player has \(Int(GameCenterMultiplayerManager.turnTimeLimit)) seconds to make a move. Running out of time forfeits the match.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Online matches are live. Leaving the game or closing the app forfeits the match and ends it for your opponent.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var computerOpponentSettingsSections: some View {
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

                Section("Online Matches") {
                    Text("An online match is live. Every session starts from a fresh board, and each player has \(Int(GameCenterMultiplayerManager.turnTimeLimit)) seconds to make a move.")
                    Text("Running out of time, leaving the match, or closing the app forfeits the game — and tells your opponent you've gone.")
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
                    ForEach(game.playerOnePitIndices, id: \.self) { index in
                        pitButton(index: index, minHeight: pitHeight)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(Array(game.playerTwoPitIndices.reversed()), id: \.self) { index in
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

    /// The design's score strip: each player's marker dot with their store
    /// count beneath it, and the turn text centered between them. When the
    /// status panel is visible directly below, it already carries the turn
    /// text, so the center stays empty rather than repeating it.
    private var scoreRow: some View {
        HStack(alignment: .top) {
            scoreMarker(for: .playerOne)

            Spacer()

            if !shouldShowStatusPanel {
                Text(statusText)
                    .font(displayFont(size: 22, weight: .regular))
                    .foregroundStyle(primaryText)
                    .contentTransition(.numericText())
                    .multilineTextAlignment(.center)
                    .frame(height: 30)
            }

            Spacer()

            scoreMarker(for: .playerTwo)
        }
        .padding(.horizontal, 34)
        .playerFacingRotation(tableRotationDegrees)
    }

    private func scoreMarker(for player: Player) -> some View {
        let isCurrent = player == game.currentPlayer && !game.isGameOver

        return VStack(spacing: 9) {
            Circle()
                .fill(scoreMarkerColor(for: player))
                .frame(width: 26, height: 26)
                .overlay {
                    Circle()
                        .strokeBorder(scoreMarkerStroke(for: player), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isDarkMode ? 0.30 : 0.10), radius: 3, x: 0, y: 2)
                .scaleEffect(isCurrent ? 1.0 : 0.82)

            Text("\(game.storeCount(for: player))")
                .font(countFont(size: 24, weight: .regular))
                .foregroundStyle(primaryText)
                .contentTransition(.numericText())
        }
        .animation(.easeInOut(duration: 0.22), value: isCurrent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName(for: player)): \(game.storeCount(for: player)) stones")
    }

    private func scoreMarkerColor(for player: Player) -> Color {
        player == .playerOne
            ? Color(red: 0.93, green: 0.90, blue: 0.84)
            : Color(red: 0.30, green: 0.29, blue: 0.27)
    }

    private func scoreMarkerStroke(for player: Player) -> Color {
        if player == .playerOne {
            return .black.opacity(isDarkMode ? 0 : 0.12)
        }
        return .white.opacity(isDarkMode ? 0.28 : 0)
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
                        .font(displayFont(size: 17, weight: .semibold))
                        .contentTransition(.numericText())

                    onlineTurnClock

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
            // Matches the panel's own surface. Without a shape to go on, the
            // gaze highlight falls back to the whole frame with a radius of the
            // system's choosing, which is neither this panel's size nor its
            // corners.
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(primaryText)
        .multilineTextAlignment(.center)
        .mancalaGlassEffect(tint: storeTint, cornerRadius: 18, role: .panel)
        .accessibilityHint("Tap to show or hide AI thinking details")
    }

    /// The minute each side gets to sow, counting down while an online
    /// session is live — the local player's own clock, or the opponent's while
    /// this side waits. Kept inside a `TimelineView` so the twice-a-second
    /// redraw stays in this label instead of invalidating everything that
    /// reads the game state, and built at all only during a match, so nothing
    /// is ticking behind the menu.
    @ViewBuilder
    private var onlineTurnClock: some View {
        if gameMode == .onlineMultiplayer,
           !game.isGameOver,
           let deadline = onlineManager.turnDeadline {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let remaining = max(0, deadline.timeIntervalSince(context.date))
                let seconds = Int(remaining.rounded(.up))
                let isUrgent = remaining <= 10

                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption2.weight(.bold))

                    Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText(countsDown: true))
                }
                .foregroundStyle(isUrgent ? Color.red : secondaryText)
                .animation(.easeInOut(duration: 0.2), value: isUrgent)
                .accessibilityLabel(
                    onlineManager.isLocalTurnClock
                        ? "\(seconds) seconds left to make your move"
                        : "\(seconds) seconds left for \(onlineManager.opponentName)"
                )
            }
        }
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
                    if visualTheme == .flat {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(red: 0.73, green: 0.47, blue: 0.10).opacity(0.9), lineWidth: 2.5)
                            .padding(-4)
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
        // The pit's own surface is painted inside the label, so the shape it
        // names there isn't the one the button style highlights; this is.
        .hoverShape(pitHitShape)
        .disabled(!isPlayable)
        .recordCellFrame(id: index)
        .accessibilityLabel("\(displayName(for: owner)) pit with \(game.pits[index]) stones")
    }

    private var pitHitShape: AnyShape {
        visualTheme == .flat
            ? AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            : AnyShape(Ellipse())
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
        guard !challengeFailed else { return false }

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
            startFreshOnlineSession()
            onlineManager.startMatch()
        } else {
            resetCurrentGame()
        }
    }

    private func resetForSettingsChange() {
        // A challenge board is a fixed puzzle; settings tweaks made mid-run
        // must not swap it for a standard opening.
        guard activeChallenge == nil else { return }

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
        if let activeChallenge {
            startChallenge(activeChallenge)
            return
        }

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
            Task { await applyPendingOnlineMatchIfNeeded() }
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
        // Online sessions always open on a fresh board. A match doesn't
        // outlive the app being closed (see `handleAppDidEnterBackground`), so
        // there is never an online board worth resuming — and the menu's
        // "Continue your game" subtitle reads this too, which is right.
        guard mode != .onlineMultiplayer else { return nil }

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
            Data()
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
            break
        }
    }

    private func clearSavedGameState(for mode: GameMode) {
        setSavedGameData(Data(), for: mode)
    }

    private func persistStableGameState(for mode: GameMode? = nil) {
        // Challenge boards are one-shot puzzles: never write them over a
        // mode's saved game.
        guard activeChallenge == nil else { return }

        let mode = mode ?? gameMode
        guard mode != .onlineMultiplayer else { return }

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
        // Challenge results live in the challenge list, not the game history,
        // and puzzle boards must not feed Game Center stats.
        guard activeChallenge == nil else { return }
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
            // Flat stones are plain matte dots; the glass theme keeps a
            // gradient sheen.
            .fill(visualTheme == .flat
                ? AnyShapeStyle(stoneColor(for: colorIndex))
                : AnyShapeStyle(stoneColor(for: colorIndex).gradient))
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
        // Bounds of the stones actually shown (offsets plus stone radius and a
        // hair of margin). The cluster is recentered on those bounds and scaled
        // down when its frame is smaller, so stones never spill past the well
        // or store that contains them — while small clusters keep full size.
        let shown = min(count, 18)
        let reach: CGFloat = 6.5
        var minX: CGFloat = 0, maxX: CGFloat = 0, minY: CGFloat = 0, maxY: CGFloat = 0
        for index in 0..<shown {
            let offset = stoneOffset(for: index)
            minX = min(minX, offset.width - reach)
            maxX = max(maxX, offset.width + reach)
            minY = min(minY, offset.height - reach)
            maxY = max(maxY, offset.height + reach)
        }
        let bounds = CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))

        return GeometryReader { proxy in
            let scale = min(1, proxy.size.width / bounds.width, proxy.size.height / bounds.height)

            ZStack {
                ForEach(0..<shown, id: \.self) { index in
                    stoneView(colorIndex: index, diameter: 11)
                        .offset(stoneOffset(for: index))
                        .shadow(color: visualTheme == .flat ? .clear : (isDarkMode ? .black.opacity(0.30) : .black.opacity(0.18)), radius: 1.5, x: 0, y: 1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(scale)
            .offset(x: -bounds.midX * scale, y: -bounds.midY * scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
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
        if activeChallenge != nil, movingPlayer == .playerOne {
            challengeMovesUsed += 1
        }
        let moveAchievementResult = moveAchievementResult(for: selectedIndex, movingPlayer: movingPlayer)
        let path = game.sowingPath(from: selectedIndex)
        let canAnimateVisually = is3DBoardActive || cellFrames[selectedIndex] != nil
        guard canAnimateVisually, !path.isEmpty else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                game.playPit(at: selectedIndex)
            }
            if activeChallenge == nil {
                GameCenterAchievements.reportMove(
                    moveAchievementResult,
                    gameMode: gameMode,
                    localPlayerSide: onlineManager.localPlayerSide
                )
            }
            recordCompletedGameIfNeeded()
            persistStableGameState()
            handleOnlineMoveIfNeeded(from: selectedIndex, movingPlayer: movingPlayer)
            await runAIMoveIfNeeded()
            evaluateChallengeAfterMove()
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
        if activeChallenge == nil {
            GameCenterAchievements.reportMove(
                moveAchievementResult,
                gameMode: gameMode,
                localPlayerSide: onlineManager.localPlayerSide
            )
        }
        recordCompletedGameIfNeeded()
        persistStableGameState()
        handleOnlineMoveIfNeeded(from: selectedIndex, movingPlayer: movingPlayer)

        await runAIMoveIfNeeded()
        evaluateChallengeAfterMove()
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

        pendingOnlineMoveIndices.append(selectedIndex)

        if !game.isGameOver, game.currentPlayer == movingPlayer {
            onlineManager.noteLocalExtraTurn()
            return
        }

        // Handed over as a run, not a single index: an extra turn keeps the
        // board here for another sow, and the far device needs all of them to
        // animate the turn rather than jump to its result.
        let moves = pendingOnlineMoveIndices
        pendingOnlineMoveIndices.removeAll()

        onlineManager.sendTurn(
            game: game,
            moveIndices: moves,
            playerOneName: displayName(for: .playerOne),
            playerTwoName: displayName(for: .playerTwo)
        )
    }

    @MainActor
    private func applyPendingOnlineMatchIfNeeded() async {
        // A replay already running owns the board; it picks up anything that
        // arrives behind it once the stones have settled.
        guard !isReplayingOnlineMove else { return }
        guard let update = onlineManager.pendingUpdate else { return }
        onlineManager.clearPendingUpdate()

        // Anything from a match this board doesn't belong to is a new session,
        // and a session always opens on the standard layout — whatever the
        // last one left behind was that one's, not this one's. Doing it here
        // rather than only when the payload is empty also means the opponent's
        // opening move has a fresh board to animate onto.
        if appliedOnlineMatchID != update.matchID {
            startFreshOnlineSession()
            appliedOnlineMatchID = update.matchID
        }

        // Nobody has moved yet: the fresh board above is the whole update.
        guard !update.isNewMatch, let payload = update.payload else { return }

        onlinePlayerOneName = payload.playerOneName
        onlinePlayerTwoName = payload.playerTwoName

        let arrived = payload.game.game
        if await replayOpponentMoves(payload.moves, arrivingAt: arrived) {
            // Anything that landed while the stones were in flight.
            if onlineManager.pendingUpdate != nil {
                await applyPendingOnlineMatchIfNeeded()
            }
            return
        }

        // No replay was possible — a board that had drifted out of step, a
        // match joined partway, or a payload from a build that only sent its
        // last move. Take the state that arrived as it stands.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            game = arrived
            flyingStone = nil
            hintedPitIndex = nil
            isAnimatingMove = false
            isAIMovePending = false
            hasRecordedCurrentCompletedGame = false
        }
        recordCompletedGameIfNeeded()
    }

    /// Plays the opponent's turn out on this device — every sow of it, stone
    /// by stone, through the same animation a local move uses.
    ///
    /// Rehearsed on a copy first, and abandoned before the board moves at all
    /// unless the whole run is legal from where this device stands *and* ends
    /// on exactly the board that arrived. That keeps a drifted board from
    /// animating its way somewhere plausible but wrong; the caller snaps to
    /// the received state instead.
    @MainActor
    private func replayOpponentMoves(_ moves: [Int], arrivingAt arrived: MancalaGame) async -> Bool {
        guard let localSide = onlineManager.localPlayerSide,
              game.canReplay(moves, as: localSide.opponent, arrivingAt: arrived) else {
            return false
        }

        isReplayingOnlineMove = true
        for move in moves {
            await animateMove(from: move)
        }
        isReplayingOnlineMove = false

        // Insurance. The rehearsal says these already agree, but a board the
        // far device doesn't share is the one failure worth never risking.
        if !game.matches(arrived) {
            game = arrived
        }

        // The clock only starts once the board has settled, so the seconds
        // spent watching the opponent's stones travel don't come out of the
        // local player's own minute.
        onlineManager.restartLocalTurnClock()
        return true
    }

    @MainActor
    private func runAIMoveIfNeeded() async {
        guard (gameMode == .singlePlayer || gameMode == .zeroPlayer),
              isAIPlayAvailable,
              isAIControlled(game.currentPlayer),
              !(gameMode == .zeroPlayer && isZeroPlayerPaused),
              !isMainMenuPresented,
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

    /// The solver budget for Impossible, which comes from user settings rather
    /// than the difficulty profile.
    private var impossibleSearchOptions: MancalaOptimalSolver.Options {
        MancalaOptimalSolver.Options(
            maxPositions: impossibleSearchLimitMode == .positions ? impossibleSearchLimit : 100_000_000,
            timeLimit: impossibleSearchLimitMode == .time ? TimeInterval(impossibleSearchTimeLimit) : nil
        )
    }

    @MainActor
    private func chooseAIPit(for player: Player, difficulty: AIDifficulty) async -> Int? {
        let legalPits = game.legalPits(for: player)
        guard !legalPits.isEmpty else { return nil }

        var rng = SplitMix64(seed: UInt64.random(in: UInt64.min...UInt64.max))
        let profile = difficulty.profile

        if profile.usesSearch {
            appendAIThought("Searching legal pits \(legalPits).")
            let pitsSnapshot = game.pits
            let solverOptions = difficulty == .impossible
                ? impossibleSearchOptions
                : AIMoveSelector.options(for: profile)
            // The solver reports about a hundred times a second for as long as
            // it runs. Delivered one main-actor hop at a time that re-rendered
            // the game view on every frame of an Impossible search and the
            // whole app stopped taking input; the relay coalesces them into a
            // bounded trickle. Progress that belongs to a search this view has
            // already moved on from is dropped rather than logged out of order.
            let searchGeneration = aiSearchGeneration
            let relay = AISearchProgressRelay { entries, searchProgress in
                guard searchGeneration == aiSearchGeneration else { return }
                for entry in entries {
                    appendAIThought(entry)
                }
                guard let searchProgress else { return }
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
            let progress = relay.progressHandler
            let progressUpdate = relay.progressUpdateHandler
            let seed = rng.next()
            // Every type this closure touches — `SplitMix64`, `MancalaGame`,
            // `AIMoveSelector` and the solver behind it — must stay declared
            // `nonisolated`, and that is not a tidiness point.
            //
            // The target defaults to main-actor isolation, and `Task.detached`
            // takes an `@isolated(any)` closure: it runs the body on whatever
            // actor the closure is isolated to. Calling one main-actor-isolated
            // function from in here is enough to infer the whole closure
            // `@MainActor`, at which point this "detached" search runs on the
            // main thread and the app stops responding for as long as
            // Impossible thinks. It read as correct for a long time and wasn't.
            // Reading the code cannot tell you which way it went — `sample` the
            // process during a search and look at which thread the alpha-beta
            // frames sit on.
            let searchTask = Task.detached(priority: .userInitiated) { () -> Int? in
                var searchRNG = SplitMix64(seed: seed)
                let snapshot = MancalaGame(pits: pitsSnapshot, currentPlayer: player)
                return AIMoveSelector.selectPit(
                    in: snapshot,
                    for: player,
                    difficulty: difficulty,
                    optionsOverride: solverOptions,
                    rng: &searchRNG,
                    progress: progress,
                    progressUpdate: progressUpdate
                )
            }
            aiSearchTask = searchTask
            let selectedPit = await searchTask.value
            // The closing lines say which depth completed and why the search
            // stopped, so they have to land before "Selected pit N."
            relay.finish()
            return selectedPit ?? legalPits.first
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

        return AIMoveSelector.selectPit(in: game, for: player, difficulty: difficulty, rng: &rng)
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
        if visualTheme == .flat {
            // Alternating charcoal and ochre dots, matching the soft theme's
            // two-tone stone palette.
            let flatStones = [
                Color(red: 0.25, green: 0.26, blue: 0.27),
                Color(red: 0.73, green: 0.47, blue: 0.10),
                Color(red: 0.31, green: 0.32, blue: 0.33),
                Color(red: 0.64, green: 0.40, blue: 0.08)
            ]
            return flatStones[index % flatStones.count]
        }

        // Same set the 3D board builds its materials from, so the 2D board and
        // the menu pebbles never disagree with the stones on the table.
        let tints = stoneSetStyle.tints
        return tints[index % tints.count].color
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

/// The visible side wall of an extruded rounded-rect slab: the band between the
/// near edge of the top face and that same edge pushed down by `depth`. Corner
/// curvature is sampled so the wall silhouette wraps around the rounded corners.
/// Lays a menu item out the way a system menu row does: icon in a fixed
/// gutter, title beside it, the row filling the popover's width so the whole
/// strip is the target.
private struct HeaderMenuLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .font(.system(size: 17))
                .frame(width: 24)

            configuration.title

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 16)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hoverShape(cornerRadius: 12)
    }
}

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

    /// The board is a frame around the pit buttons rather than a control in its
    /// own right, and the pits shape their own highlights.
    private var isControlSurface: Bool {
        if case .board = role {
            return false
        }
        return true
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        // The gaze highlight is drawn around whatever carries the surface, so
        // this is the level that gets to name its shape — a shape declared
        // further in, on a button's label, isn't the one the button style
        // reaches for, and the highlight falls back to a system pill that fits
        // nothing it's over.
        if visualTheme == .flat {
            flatSurface(content)
                .hoverShape(surfaceShape, isEnabled: isControlSurface)
        } else {
            glassSurface(content)
                .hoverShape(surfaceShape, isEnabled: isControlSurface)
        }
    }

    // MARK: Flat (soft indents)

    /// Interior tone of a pressed-in well: a touch brighter than the page in
    /// light mode (the dish catches light), a touch deeper in dark mode.
    private var flatWellTone: Color {
        isDark
            ? Color(red: 0.105, green: 0.097, blue: 0.085)
            : Color(red: 0.965, green: 0.953, blue: 0.928)
    }

    /// Raised elements (panels, controls) sit just proud of the page in the
    /// same near-page tone.
    private var flatRaisedTone: Color {
        isDark
            ? Color(red: 0.155, green: 0.145, blue: 0.128)
            : Color(red: 0.962, green: 0.948, blue: 0.920)
    }

    /// Flat pits are soft rounded rectangles (stores stay capsules), matching
    /// the pressed-into-the-page look without the oval silhouette.
    private var flatWellShape: AnyShape {
        role == .pit
            ? AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            : AnyShape(Capsule(style: .continuous))
    }

    /// Inner-shadow tone of a flat well. Wells the current player can use
    /// deepen and warm toward umber instead of gaining a hard outline, so the
    /// turn reads as a change in lighting rather than a drawn border.
    private var flatWellShadowColor: Color {
        if interactive {
            // In dark mode the well tone is near-black, so a warm rim reads as
            // a faint glow rather than a shadow — keep it gentle.
            return isDark
                ? Color(red: 0.80, green: 0.52, blue: 0.18).opacity(0.30)
                : Color(red: 0.42, green: 0.27, blue: 0.07).opacity(0.40)
        }
        return Color.black.opacity(isDark ? 0.60 : 0.15)
    }

    /// No board slab at all: pits and stores are indents pressed straight
    /// into the page background. Shading assumes light from above — a soft
    /// dark inner shadow along the top rim and a bright catch along the
    /// bottom rim — and flips with the table.
    private func flatWell(_ content: Content) -> some View {
        let lightDirection: CGFloat = isFlipped ? -1 : 1

        return content
            .background {
                ZStack {
                    flatWellShape
                        .fill(flatWellTone)

                    flatWellShape
                        .stroke(flatWellShadowColor, lineWidth: interactive ? 7 : 6)
                        .blur(radius: 5)
                        .offset(y: 4 * lightDirection)
                        .mask(flatWellShape)

                    flatWellShape
                        .stroke(Color.white.opacity(isDark ? 0.06 : 0.90), lineWidth: 5)
                        .blur(radius: 4)
                        .offset(y: -3 * lightDirection)
                        .mask(flatWellShape)
                }
                .compositingGroup()
                .shadow(color: Color.white.opacity(isDark ? 0 : 0.7), radius: 1, x: 0, y: 1.5 * lightDirection)
                .allowsHitTesting(false)
            }
    }

    private func flatRaised(_ content: Content) -> some View {
        content
            .background {
                surfaceShape
                    .fill(flatRaisedTone)
                    .shadow(color: .black.opacity(isDark ? 0.45 : 0.10), radius: 9, x: 0, y: 5)
                    .shadow(color: .white.opacity(isDark ? 0.03 : 0.85), radius: 6, x: 0, y: -3)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private func flatSurface(_ content: Content) -> some View {
        switch role {
        case .board:
            content
        case .pit, .store:
            flatWell(content)
        case .panel, .control:
            flatRaised(content)
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

private extension View {
    /// Shapes the gaze highlight to match the thing being looked at.
    ///
    /// Belongs outside the button, not inside its label: the button style draws
    /// the highlight around the button as a whole, and only a shape declared at
    /// that level is the one it uses.
    @ViewBuilder
    func hoverShape(_ shape: some Shape, isEnabled: Bool = true) -> some View {
        if isEnabled {
            contentShape(.hoverEffect, shape)
        } else {
            self
        }
    }

    func hoverShape(cornerRadius: CGFloat) -> some View {
        hoverShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Moves a view toward or away from the viewer, in points. Only visionOS
    /// has anywhere to move it to; everywhere else this is the view itself.
    @ViewBuilder
    func windowDepthOffset(_ points: CGFloat) -> some View {
        #if os(visionOS)
        offset(z: points)
        #else
        self
        #endif
    }

    func mancalaGlassEffect(
        tint: Color,
        cornerRadius: CGFloat,
        role: MancalaSurfaceRole = .panel,
        interactive: Bool = false,
        seed: Int = 0
    ) -> some View {
        modifier(MancalaSurfaceModifier(role: role, tint: tint, cornerRadius: cornerRadius, interactive: interactive, seed: seed))
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

#Preview("Flat") {
    UserDefaults.standard.set(VisualTheme.flat.rawValue, forKey: "visualTheme")
    return ContentView()
}
