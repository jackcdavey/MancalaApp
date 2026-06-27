import SwiftUI
import FoundationModels

struct ContentView: View {
    private static let defaultImpossibleSearchLimit = 10_000_000
    private static let defaultImpossibleTimeLimit = 10

    @Environment(\.colorScheme) private var colorScheme
    @State private var game = MancalaGame()
    @State private var cellFrames: [Int: CGRect] = [:]
    @State private var flyingStone: FlyingStone?
    @State private var isAnimatingMove = false
    @State private var hapticTrigger = 0
    @AppStorage("gameMode") private var gameMode = GameMode.twoPlayer
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
    @AppStorage("playerOneName") private var playerOneName = "Player 1"
    @AppStorage("playerTwoName") private var playerTwoName = "Player 2"
    @State private var isSettingsPresented = false
    @State private var isGameHistoryPresented = false
    @State private var hasRecordedCurrentCompletedGame = false
    @State private var undoHistory: [MancalaGame] = []
    @State private var isAIMovePending = false
    @State private var aiSearchGeneration = 0
    @State private var aiSearchTask: Task<Int?, Never>?
    @State private var isThoughtPanelExpanded = false
    @State private var aiThoughtLog: [String] = []
    @State private var isZeroPlayerPaused = true
    @AppStorage("impossibleSearchLimitMode") private var impossibleSearchLimitMode = ImpossibleSearchLimitMode.positions
    @AppStorage("impossibleSearchLimit") private var impossibleSearchLimit = ContentView.defaultImpossibleSearchLimit
    @AppStorage("impossibleSearchTimeLimit") private var impossibleSearchTimeLimit = ContentView.defaultImpossibleTimeLimit
    @State private var impossibleSearchProgress = 0.0
    @State private var impossibleSearchProgressText = ""
    @AppStorage("savedSinglePlayerGameState") private var savedSinglePlayerGameState = Data()
    @AppStorage("savedTwoPlayerGameState") private var savedTwoPlayerGameState = Data()
    @AppStorage("savedZeroPlayerGameState") private var savedZeroPlayerGameState = Data()
    @AppStorage("completedGameHistory") private var completedGameHistoryData = Data()
    @AppStorage("savedGameState") private var legacySavedGameState = Data()

    private let model = SystemLanguageModel.default

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
        .sheet(isPresented: $isSettingsPresented) {
            settingsSheet
        }
        .sheet(isPresented: $isGameHistoryPresented) {
            gameHistorySheet
        }
        .onAppear {
            restoreSavedGameIfNeeded()
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

    private var isAIPlayAvailable: Bool {
        if case .available = model.availability {
            return true
        }
        return false
    }

    private var shouldShowStatusPanel: Bool {
        gameMode == .singlePlayer || gameMode == .zeroPlayer
    }

    private var shouldShowUndoButton: Bool {
        switch gameMode {
        case .singlePlayer:
            isSinglePlayerUndoButtonEnabled
        case .twoPlayer:
            isTwoPlayerUndoButtonEnabled
        case .zeroPlayer:
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
        case .zeroPlayer:
            return false
        }
    }

    private var tableRotationDegrees: Double {
        gameMode == .twoPlayer && flipScreenForTwoPlayerTurns && game.currentPlayer == .playerTwo && !game.isGameOver ? 180 : 0
    }

    private var shouldShowNumberLabels: Bool {
        switch gameMode {
        case .singlePlayer:
            singlePlayerShowNumberLabels
        case .twoPlayer:
            twoPlayerShowNumberLabels
        case .zeroPlayer:
            zeroPlayerShowNumberLabels
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

    private func displayName(for player: Player) -> String {
        switch player {
        case .playerOne:
            let trimmedName = playerOneName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? "Player 1" : trimmedName
        case .playerTwo:
            let trimmedName = playerTwoName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? "Player 2" : trimmedName
        }
    }

    private func aiDifficulty(for player: Player) -> AIDifficulty {
        switch gameMode {
        case .singlePlayer:
            difficulty
        case .zeroPlayer:
            player == .playerOne ? zeroPlayerOneDifficulty : zeroPlayerTwoDifficulty
        case .twoPlayer:
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
        case .twoPlayer:
            false
        }
    }

    private var statusText: String {
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
        switch model.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "AI play requires a device that supports Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use AI play."
        case .unavailable(.modelNotReady):
            return "The on-device model is still getting ready. Try again later."
        case .unavailable:
            return "AI play is unavailable on this device right now."
        }
    }

    private func gameContent(isPortrait: Bool, availableHeight: CGFloat) -> some View {
        let contentSpacing: CGFloat = isPortrait ? 10 : 18
        let headerHeight: CGFloat = isPortrait ? 76 : (shouldShowStatusPanel && isThoughtPanelExpanded ? 172 : 64)
        let statusHeight: CGFloat = isPortrait && shouldShowStatusPanel ? (isThoughtPanelExpanded ? 172 : 46) : 0
        let visibleStatusSpacing = isPortrait && shouldShowStatusPanel ? contentSpacing : 0
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

            if isPortrait && shouldShowStatusPanel {
                statusPanel
                    .frame(height: statusHeight)
            }
        }
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
        }

        return Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(isDarkMode ? 0.24 : 0.18))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(isDarkMode ? 0.72 : 0.58), lineWidth: 1)
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private func header(isPortrait: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Mancala")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

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
                .buttonStyle(.glass)
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
                .buttonStyle(.glass)
                .disabled(isAnimatingMove || game.isGameOver)
                .accessibilityLabel(isZeroPlayerPaused ? "Play zero player game" : "Pause zero player game")
            }

            Menu {
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
                .disabled(isAnimatingMove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .frame(width: 44, height: 44)
                    .playerFacingRotation(tableRotationDegrees)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("More options")
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Players") {
                    Picker("Mode", selection: $gameMode) {
                        Text("2 Players").tag(GameMode.twoPlayer)
                        Text("1 Player").tag(GameMode.singlePlayer)
                            .disabled(!isAIPlayAvailable)
                        Text("0 Player").tag(GameMode.zeroPlayer)
                            .disabled(!isAIPlayAvailable)
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
                    TextField("Player 1", text: $playerOneName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

                    TextField("Player 2", text: $playerTwoName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

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
                                    Stepper(
                                        value: impossibleSearchLimitBinding,
                                        in: 100_000...100_000_000,
                                        step: 100_000
                                    ) {
                                        HStack {
                                            Text("Max positions")
                                            Spacer()
                                            TextField("Positions", value: impossibleSearchLimitBinding, format: .number)
                                                .keyboardType(.numberPad)
                                                .multilineTextAlignment(.trailing)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 136)
                                        }
                                    }
                                } else {
                                    Stepper(
                                        value: impossibleSearchTimeLimitBinding,
                                        in: 1...120,
                                        step: 1
                                    ) {
                                        HStack {
                                            Text("Max time")
                                            Spacer()
                                            TextField("Seconds", value: impossibleSearchTimeLimitBinding, format: .number)
                                                .keyboardType(.numberPad)
                                                .multilineTextAlignment(.trailing)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 82)
                                            Text("s")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
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

    private var shouldShowImpossibleSearchSettings: Bool {
        switch gameMode {
        case .singlePlayer:
            difficulty == .impossible
        case .zeroPlayer:
            zeroPlayerOneDifficulty == .impossible || zeroPlayerTwoDifficulty == .impossible
        case .twoPlayer:
            false
        }
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
        .glassEffect(.regular.tint(storeTint), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(quietStroke, lineWidth: 1)
        }
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
                stoneCluster(count: game.pits[index])
                    .frame(height: clusterHeight)

                if shouldShowNumberLabels {
                    Text("\(game.pits[index])")
                        .font(.system(size: countSize, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(primaryText)
                        .contentTransition(.numericText())
                }
            }
            .playerFacingRotation(tableRotationDegrees)
            .padding(.vertical, verticalInset)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .glassEffect(.regular.tint(isPlayable ? playableTint : pitTint).interactive(isPlayable), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isPlayable ? strongStroke : quietStroke, lineWidth: isPlayable ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .disabled(!isPlayable)
        .recordCellFrame(id: index)
        .accessibilityLabel("\(displayName(for: owner)) pit with \(game.pits[index]) stones")
    }

    private func canHumanPlayPit(at index: Int) -> Bool {
        switch gameMode {
        case .twoPlayer:
            return true
        case .singlePlayer:
            return game.owner(ofPitAt: index) == .playerOne
        case .zeroPlayer:
            return false
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
        case .zeroPlayer:
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
            isAnimatingMove = false
            isAIMovePending = false
            hasRecordedCurrentCompletedGame = false
            impossibleSearchProgress = 0
            impossibleSearchProgressText = ""
        }

        if newMode == .zeroPlayer {
            isZeroPlayerPaused = true
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
        let stroke = isCurrent ? Color.green.opacity(isDarkMode ? 0.60 : 0.54) : quietStroke

        if compact {
            HStack(spacing: 12) {
                stoneCluster(count: game.storeCount(for: owner))
                    .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 38)

                if shouldShowNumberLabels {
                    Text("\(game.storeCount(for: owner))")
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(primaryText)
                        .frame(width: 48)
                        .contentTransition(.numericText())
                }
            }
            .playerFacingRotation(tableRotationDegrees)
            .padding(.horizontal, 14)
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(stroke, lineWidth: isCurrent ? 1.5 : 1)
            }
        } else {
            VStack(spacing: 7) {
                stoneCluster(count: game.storeCount(for: owner))
                    .frame(height: 48)

                if shouldShowNumberLabels {
                    Text("\(game.storeCount(for: owner))")
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(primaryText)
                        .contentTransition(.numericText())
                }
            }
            .playerFacingRotation(tableRotationDegrees)
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

        recordUndoSnapshotIfNeeded()
        let path = game.sowingPath(from: selectedIndex)
        guard let sourceFrame = cellFrames[selectedIndex], !path.isEmpty else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                game.playPit(at: selectedIndex)
            }
            recordCompletedGameIfNeeded()
            persistStableGameState()
            await runAIMoveIfNeeded()
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
        recordCompletedGameIfNeeded()
        persistStableGameState()

        await runAIMoveIfNeeded()
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

        do {
            appendAIThought("Requesting on-device model move.")
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: aiPrompt(for: player, difficulty: difficulty, legalPits: legalPits),
                generating: AIMancalaMove.self
            )
            let selectedPit = response.content.pitIndex

            if legalPits.contains(selectedPit) {
                return selectedPit
            }

            appendAIThought("Model returned illegal pit \(selectedPit); using fallback.")
        } catch {
            appendAIThought("Model request failed; using fallback.")
            return legalPits.first
        }

        return legalPits.first
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

#Preview {
    ContentView()
}
