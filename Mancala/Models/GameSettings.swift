import SwiftUI

enum GameMode: String, CaseIterable, Identifiable {
    case twoPlayer
    case singlePlayer
    case zeroPlayer
    case onlineMultiplayer

    var id: String { rawValue }
}

enum StartingPlayer: String, CaseIterable, Identifiable {
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

enum ImpossibleSearchLimitMode: String, CaseIterable, Identifiable {
    case positions
    case time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .positions: "Positions"
        case .time: "Time"
        }
    }

    var description: String {
        switch self {
        case .positions:
            "Search stops after the selected number of positions. The progress bar estimates time remaining."
        case .time:
            "Search stops after the selected time. A hard safety cap of 100,000,000 positions still applies."
        }
    }
}

enum AIDifficulty: String, CaseIterable, Identifiable {
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
            "Uses deterministic search with pruning, exact endgame solving, and the selected search budget."
        }
    }

    var tint: Color {
        switch self {
        case .easy:
            Color.green
        case .medium:
            Color.blue
        case .hard:
            Color.orange
        case .impossible:
            Color.pink
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
