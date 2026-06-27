import SwiftUI
import Playgrounds
import FoundationModels

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
    @State private var gameMode = GameMode.twoPlayer
    @State private var difficulty = AIDifficulty.medium
    @State private var startingPlayer = StartingPlayer.human
    @State private var isSettingsPresented = false
    @State private var isAIMovePending = false
    @State private var aiSearchTask: Task<Int?, Never>?
    @State private var isThoughtPanelExpanded = false
    @State private var aiThoughtLog: [String] = []

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

    private var isSinglePlayerAvailable: Bool {
        if case .available = model.availability {
            return true
        }
        return false
    }

    private var modelAvailabilityMessage: String? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "Single player requires a device that supports Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use single player."
        case .unavailable(.modelNotReady):
            return "The on-device model is still getting ready. Try again later."
        case .unavailable:
            return "Single player is unavailable on this device right now."
        }
    }

    private func gameContent(isPortrait: Bool, availableHeight: CGFloat) -> some View {
        let contentSpacing: CGFloat = isPortrait ? 10 : 18
        let headerHeight: CGFloat = isPortrait ? 76 : (isThoughtPanelExpanded ? 148 : 64)
        let statusHeight: CGFloat = isPortrait ? (isThoughtPanelExpanded ? 148 : 46) : 0
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
                    .frame(maxWidth: isThoughtPanelExpanded ? 360 : 260)

                Spacer()
            }

            Button {
                let shouldStartAIAfterReset = !isAIMovePending
                cancelAIThinking()
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
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .disabled(isAnimatingMove)
            .accessibilityLabel("Reset game")

            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .disabled(isAnimatingMove || isAIMovePending)
            .accessibilityLabel("Settings")
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Players") {
                    Picker("Mode", selection: $gameMode) {
                        Text("2 Players").tag(GameMode.twoPlayer)
                        Text("1 Player").tag(GameMode.singlePlayer)
                            .disabled(!isSinglePlayerAvailable)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: gameMode) { _, newMode in
                        if newMode == .singlePlayer, !isSinglePlayerAvailable {
                            gameMode = .twoPlayer
                        }

                        resetForSettingsChange()
                    }

                    if let modelAvailabilityMessage {
                        Text(modelAvailabilityMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if gameMode == .singlePlayer {
                    Section("First Move") {
                        Picker("Starts", selection: $startingPlayer) {
                            ForEach(StartingPlayer.allCases) { startingPlayer in
                                Text(startingPlayer.title).tag(startingPlayer)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: startingPlayer) { _, _ in
                            resetForSettingsChange()
                        }

                        Text(startingPlayer.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Difficulty") {
                        Picker("Skill", selection: $difficulty) {
                            ForEach(AIDifficulty.allCases) { difficulty in
                                Text(difficulty.title).tag(difficulty)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(difficulty.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
                    Text(game.statusText)
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
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(displayedThoughtLog, id: \.self) { entry in
                            Text(entry)
                                .font(.caption2.monospaced())
                                .foregroundStyle(secondaryText)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
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

    private func canHumanPlayPit(at index: Int) -> Bool {
        gameMode == .twoPlayer || game.owner(ofPitAt: index) == .playerOne
    }

    private func resetForSettingsChange() {
        cancelAIThinking()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            resetGame()
            flyingStone = nil
            isAnimatingMove = false
            isAIMovePending = false
        }
    }

    private func resetGame() {
        game.reset(startingPlayer: resolvedStartingPlayer())
    }

    private func cancelAIThinking() {
        let wasThinking = isAIMovePending || aiSearchTask != nil
        aiSearchTask?.cancel()
        aiSearchTask = nil
        isAIMovePending = false
        if wasThinking {
            appendAIThought("Cancelled AI search.")
        }
    }

    private func appendAIThought(_ entry: String) {
        aiThoughtLog.append(entry)
        if aiThoughtLog.count > 40 {
            aiThoughtLog.removeFirst(aiThoughtLog.count - 40)
        }
    }

    private func resolvedStartingPlayer() -> Player {
        guard gameMode == .singlePlayer else {
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

        await runAIMoveIfNeeded()
    }

    @MainActor
    private func runAIMoveIfNeeded() async {
        guard gameMode == .singlePlayer,
              isSinglePlayerAvailable,
              game.currentPlayer == .playerTwo,
              !game.isGameOver,
              !isAnimatingMove,
              !isAIMovePending else {
            return
        }

        isAIMovePending = true
        aiThoughtLog = []
        appendAIThought("\(difficulty.title) AI is choosing a move.")
        try? await Task.sleep(for: .milliseconds(350))

        guard let selectedPit = await chooseAIPit() else {
            isAIMovePending = false
            aiSearchTask = nil
            appendAIThought("No move selected.")
            return
        }

        guard isAIMovePending,
              gameMode == .singlePlayer,
              game.currentPlayer == .playerTwo,
              !game.isGameOver else {
            aiSearchTask = nil
            return
        }

        appendAIThought("Selected pit \(selectedPit).")
        aiSearchTask = nil
        isAIMovePending = false
        await animateMove(from: selectedPit)
    }

    private func chooseAIPit() async -> Int? {
        let legalPits = game.legalPits(for: .playerTwo)
        guard !legalPits.isEmpty else { return nil }

        if difficulty == .impossible {
            appendAIThought("Starting exact search over legal pits \(legalPits).")
            let pitsSnapshot = game.pits
            let progress: @Sendable (String) -> Void = { entry in
                Task { @MainActor in
                    appendAIThought(entry)
                }
            }
            let searchTask = Task.detached(priority: .userInitiated) {
                MancalaOptimalSolver.bestMove(pits: pitsSnapshot, currentPlayer: 2, progress: progress)
            }
            aiSearchTask = searchTask
            return await searchTask.value ?? legalPits.first
        }

        do {
            appendAIThought("Requesting on-device model move.")
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: aiPrompt(legalPits: legalPits),
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

    private func aiPrompt(legalPits: [Int]) -> String {
        """
        You are playing Mancala as Player 2.
        Board array indices 0...5 are Player 1 pits, index 6 is Player 1 store, indices 7...12 are Player 2 pits, and index 13 is Player 2 store.
        Current board: \(game.pits)
        Legal Player 2 pit indices: \(legalPits)
        Player 1 store: \(game.storeCount(for: .playerOne))
        Player 2 store: \(game.storeCount(for: .playerTwo))
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

private enum GameMode: String, CaseIterable, Identifiable {
    case twoPlayer
    case singlePlayer

    var id: String { rawValue }
}

private enum StartingPlayer: String, CaseIterable, Identifiable {
    case human
    case ai
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .human: "Player"
        case .ai: "AI"
        case .random: "Random"
        }
    }

    var description: String {
        switch self {
        case .human:
            "Player 1 makes the first move."
        case .ai:
            "The AI opens as Player 2."
        case .random:
            "A starting side is chosen each time the game resets."
        }
    }
}

private enum AIDifficulty: String, CaseIterable, Identifiable {
    case easy
    case medium
    case hard
    case impossible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .impossible: "Impossible"
        }
    }

    var description: String {
        switch self {
        case .easy:
            "Makes legal casual moves without deep planning."
        case .medium:
            "Looks for extra turns, captures, and obvious risks."
        case .hard:
            "Plays more carefully for store advantage and safer positions."
        case .impossible:
            "Solves the position and always chooses an optimal move."
        }
    }

    var promptInstruction: String {
        switch self {
        case .easy:
            "Choose a legal casual move. Do not deeply optimize."
        case .medium:
            "Prefer moves that earn an extra turn, capture stones, or avoid an obvious immediate loss."
        case .hard:
            "Evaluate all legal moves. Prioritize extra turns, captures, store advantage, and positions that reduce Player 1 capture opportunities."
        case .impossible:
            "This difficulty uses a deterministic solver instead of the language model."
        }
    }
}

@Generable
private struct AIMancalaMove {
    @Guide(description: "One legal Player 2 pit index from the provided legal pit list", .range(7...12))
    var pitIndex: Int
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

private struct MancalaOptimalSolver {
    private struct SearchStats {
        var nodes = 0
        var memoHits = 0
        var lastReportedNodeCount = 0

        nonisolated init() {}
    }

    private struct State {
        var pits: [Int]
        var currentPlayer: Int

        nonisolated init(pits: [Int], currentPlayer: Int) {
            self.pits = pits
            self.currentPlayer = currentPlayer
        }

        nonisolated var cacheKey: String {
            "\(currentPlayer):" + pits.map(String.init).joined(separator: ",")
        }
    }

    private struct Result {
        var score: Int
        var move: Int?
    }

    nonisolated static func bestMove(pits: [Int], currentPlayer: Int, progress: @escaping @Sendable (String) -> Void) -> Int? {
        var memo: [String: Result] = [:]
        var stats = SearchStats()
        let state = State(pits: pits, currentPlayer: currentPlayer)
        progress("Checking \(legalMoves(for: state.currentPlayer, pits: state.pits).count) legal root moves.")
        let result = solve(state, memo: &memo, stats: &stats, progress: progress)
        if Task.isCancelled {
            progress("Search cancelled after \(stats.nodes) positions.")
            return nil
        }

        progress("Search complete: \(stats.nodes) positions, \(memo.count) cached states.")
        return result?.move
    }

    nonisolated private static func solve(
        _ state: State,
        memo: inout [String: Result],
        stats: inout SearchStats,
        progress: @escaping @Sendable (String) -> Void
    ) -> Result? {
        if Task.isCancelled {
            return nil
        }

        stats.nodes += 1
        if stats.nodes - stats.lastReportedNodeCount >= 10_000 {
            stats.lastReportedNodeCount = stats.nodes
            progress("Searched \(stats.nodes) positions, cached \(memo.count).")
        }

        let cacheKey = state.cacheKey
        if let cached = memo[cacheKey] {
            stats.memoHits += 1
            return cached
        }

        if isGameOver(state.pits) {
            let result = Result(score: state.pits[13] - state.pits[6], move: nil)
            memo[cacheKey] = result
            return result
        }

        let moves = legalMoves(for: state.currentPlayer, pits: state.pits)
        guard !moves.isEmpty else {
            let result = Result(score: state.pits[13] - state.pits[6], move: nil)
            memo[cacheKey] = result
            return result
        }

        var bestMove: Int?
        var bestScore = state.currentPlayer == 2 ? Int.min : Int.max

        for move in moves {
            let nextState = play(move, in: state)
            guard let childResult = solve(nextState, memo: &memo, stats: &stats, progress: progress) else {
                return nil
            }
            let score = childResult.score

            if state.currentPlayer == 2 {
                if score > bestScore {
                    bestScore = score
                    bestMove = move
                }
            } else if score < bestScore {
                bestScore = score
                bestMove = move
            }
        }

        let result = Result(score: bestScore, move: bestMove)
        memo[cacheKey] = result
        return result
    }

    nonisolated private static func play(_ selectedIndex: Int, in state: State) -> State {
        var pits = state.pits
        let currentPlayer = state.currentPlayer
        let opponentStore = storeIndex(for: opponent(of: currentPlayer))
        let ownStore = storeIndex(for: currentPlayer)
        var stones = pits[selectedIndex]
        pits[selectedIndex] = 0
        var index = selectedIndex

        while stones > 0 {
            index = (index + 1) % pits.count
            if index == opponentStore {
                continue
            }

            pits[index] += 1
            stones -= 1
        }

        let ownPits = playablePits(for: currentPlayer)
        if ownPits.contains(index), pits[index] == 1 {
            let oppositeIndex = 12 - index
            let capturedStones = pits[oppositeIndex]
            if capturedStones > 0 {
                pits[oppositeIndex] = 0
                pits[index] = 0
                pits[ownStore] += capturedStones + 1
            }
        }

        if sideIsEmpty(1, pits: pits) || sideIsEmpty(2, pits: pits) {
            collectRemainingStones(in: &pits)
            return State(pits: pits, currentPlayer: currentPlayer)
        }

        let nextPlayer = index == ownStore ? currentPlayer : opponent(of: currentPlayer)
        return State(pits: pits, currentPlayer: nextPlayer)
    }

    nonisolated private static func legalMoves(for player: Int, pits: [Int]) -> [Int] {
        playablePits(for: player).filter { pits[$0] > 0 }
    }

    nonisolated private static func playablePits(for player: Int) -> [Int] {
        switch player {
        case 1: Array(0...5)
        default: Array(7...12)
        }
    }

    nonisolated private static func storeIndex(for player: Int) -> Int {
        switch player {
        case 1: 6
        default: 13
        }
    }

    nonisolated private static func isGameOver(_ pits: [Int]) -> Bool {
        sideIsEmpty(1, pits: pits) || sideIsEmpty(2, pits: pits)
    }

    nonisolated private static func sideIsEmpty(_ player: Int, pits: [Int]) -> Bool {
        playablePits(for: player).allSatisfy { pits[$0] == 0 }
    }

    nonisolated private static func collectRemainingStones(in pits: inout [Int]) {
        for player in [1, 2] {
            let remaining = playablePits(for: player).reduce(0) { $0 + pits[$1] }
            pits[storeIndex(for: player)] += remaining
            for index in playablePits(for: player) {
                pits[index] = 0
            }
        }
    }

    nonisolated private static func opponent(of player: Int) -> Int {
        player == 1 ? 2 : 1
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
