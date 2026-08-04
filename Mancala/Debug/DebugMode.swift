import SwiftUI

/// The one switch that turns the debug affordance on and off.
///
/// When `isEnabled` is false nothing is built, nothing is drawn, and the app
/// behaves exactly as it does in a shipping build — every debug entry point in
/// `ContentView` is behind this flag.
///
/// It is a plain `Bool` on purpose so it can be flipped without touching build
/// settings, which means **it is also possible to ship it on by accident**. If
/// you would rather it could never reach the App Store, change the declaration
/// to read:
///
///     #if DEBUG
///     static let isEnabled = true
///     #else
///     static let isEnabled = false
///     #endif
enum DebugMode {
    static let isEnabled = false
}

/// A game result the debug menu can force without playing the position out.
enum DebugOutcome: String, CaseIterable, Identifiable {
    case playerOneWins
    case playerTwoWins
    case draw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playerOneWins: "Player 1 Wins"
        case .playerTwoWins: "Player 2 Wins"
        case .draw: "Draw"
        }
    }

    /// Final store counts. They add up to the standard 48 stones so the
    /// scoreboard, history entry, and end-game copy all read as a real game.
    var stores: (playerOne: Int, playerTwo: Int) {
        switch self {
        case .playerOneWins: (30, 18)
        case .playerTwoWins: (18, 30)
        case .draw: (24, 24)
        }
    }
}

/// What the debug menu is allowed to ask the app to do.
///
/// The menu holds closures rather than a reference to `ContentView` so it stays
/// a plain view with no knowledge of how any of this is implemented.
struct DebugCommands {
    var playPebbleAction: (MenuPebbleStage.DebugAction) -> Void
    var forceOutcome: (DebugOutcome) -> Void
    var failChallenge: () -> Void
    var loadEndgameBoard: () -> Void
    var requestHint: () -> Void
    var clearGameHistory: () -> Void
    var clearCompletedChallenges: () -> Void
    var clearSavedGames: () -> Void
}

/// The small draggable button that opens the debug menu. It floats above
/// everything, so it is deliberately dull-looking and movable — a fixed corner
/// would eventually sit on top of whatever is being tested.
struct DebugOverlayButton: View {
    @Binding var isMenuPresented: Bool
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    var body: some View {
        Button {
            isMenuPresented = true
        } label: {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.red.opacity(0.78)))
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { offset = CGSize(width: dragStart.width + $0.translation.width,
                                             height: dragStart.height + $0.translation.height) }
                .onEnded { _ in dragStart = offset }
        )
        .padding(.trailing, 18)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .accessibilityLabel("Open debug menu")
    }
}

/// The menu itself. Every row is a one-tap action; anything that needs the main
/// menu on screen to be visible says so rather than silently doing nothing.
struct DebugMenuView: View {
    let commands: DebugCommands
    let isMainMenuVisible: Bool
    @Binding var isPresented: Bool

    @State private var mood: MenuPebbleStage.MoodKind = .tumble
    @State private var confirmingDestructive: String?

    var body: some View {
        NavigationStack {
            Form {
                pebbleSection
                outcomeSection
                boardSection
                storageSection
            }
            .navigationTitle("Debug")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // Half height by default, and the app stays live behind it: the
            // pebble stage sits at the top of the menu, so triggering an
            // animation and watching it has to be possible without dismissing.
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }

    // MARK: Pebbles

    @ViewBuilder
    private var pebbleSection: some View {
        Section {
            Picker("Mood", selection: $mood) {
                ForEach(MenuPebbleStage.MoodKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            ForEach(MenuPebbleStage.Formation.roaming, id: \.self) { formation in
                debugRow(formation.title) {
                    commands.playPebbleAction(.formation(formation, mood: mood))
                }
            }
            debugRow("Rest to Home Row") { commands.playPebbleAction(.home) }
        } header: {
            Text("Menu Pebbles — Formations")
        } footer: {
            Text(isMainMenuVisible
                 ? "Plays the formation out, holds, and returns home using the selected mood."
                 : "The main menu isn't on screen — these run, but you won't see them. Close the game to the menu first.")
        }

        Section("Menu Pebbles — Routines") {
            ForEach(MenuPebbleStage.RoutineKind.allCases) { kind in
                debugRow(kind.title) { commands.playPebbleAction(.routine(kind)) }
            }
        }

        Section("Menu Pebbles — Touch") {
            ForEach(MenuPebbleStage.ShoveOrigin.allCases) { origin in
                debugRow("Shove from \(origin.title)") { commands.playPebbleAction(.shove(origin)) }
            }
        }
    }

    // MARK: Outcomes

    private var outcomeSection: some View {
        Section {
            ForEach(DebugOutcome.allCases) { outcome in
                debugRow(outcome.title) {
                    commands.forceOutcome(outcome)
                    isPresented = false
                }
            }
            debugRow("Fail Active Challenge") {
                commands.failChallenge()
                isPresented = false
            }
        } header: {
            Text("Force Result")
        } footer: {
            Text("Ends the current game immediately with the stores set to a final 48-stone score, running the same end-game, history, and achievement path a real finish does.")
        }
    }

    // MARK: Board

    private var boardSection: some View {
        Section {
            debugRow("Load One-Move-From-Over Board") {
                commands.loadEndgameBoard()
                isPresented = false
            }
            debugRow("Request Hint") {
                commands.requestHint()
                isPresented = false
            }
        } header: {
            Text("Board")
        } footer: {
            Text("The endgame board leaves a single stone on each side, so the sweep-up animation and the result popup are one move away.")
        }
    }

    // MARK: Storage

    private var storageSection: some View {
        Section {
            destructiveRow("Clear Game History", id: "history", action: commands.clearGameHistory)
            destructiveRow("Clear Completed Challenges", id: "challenges", action: commands.clearCompletedChallenges)
            destructiveRow("Clear Saved Games", id: "saves", action: commands.clearSavedGames)
        } header: {
            Text("Stored Data")
        } footer: {
            Text("Tap once to arm, again to confirm. Useful for retesting first-run and challenge-unlock states.")
        }
    }

    // MARK: Rows

    private func debugRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// Two-tap confirmation, because these wipe real stored state and the menu
    /// is a list of small targets.
    private func destructiveRow(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        let isArmed = confirmingDestructive == id
        return Button(isArmed ? "Tap again to confirm" : title) {
            if isArmed {
                action()
                confirmingDestructive = nil
            } else {
                confirmingDestructive = id
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isArmed ? Color.red : Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
