import SwiftUI

enum VisualTheme: String, CaseIterable, Identifiable {
    case liquidGlass
    case flat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass: "Immersive"
        case .flat: "Flat"
        }
    }
}

/// Surface finish for the 3D board slab. Each style maps to a procedurally
/// generated base-color texture and a set of PBR parameters in `BoardScene`.
///
/// Ordered by family — woods, clay, stones, metal, glass — because `allCases`
/// is what fills the Material picker. The setting persists by `rawValue`, so
/// the order is free to change.
enum BoardMaterialStyle: String, CaseIterable, Identifiable {
    case walnut
    case maple
    case terracotta
    case marble
    case malachite
    case slate
    case obsidian
    case brushedBrass
    case frostedGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walnut: "Walnut"
        case .maple: "Maple"
        case .terracotta: "Terracotta"
        case .marble: "Marble"
        case .malachite: "Malachite"
        case .slate: "Slate"
        case .obsidian: "Obsidian"
        case .brushedBrass: "Brushed Brass"
        case .frostedGlass: "Frosted Glass"
        }
    }

    /// The finishes Settings offers. Withdrawn ones stay in `allCases` — they
    /// still render, and anyone who already had one selected keeps it — this is
    /// only what's on the menu now.
    static var offered: [BoardMaterialStyle] {
        allCases.filter(\.isOffered)
    }

    private var isOffered: Bool {
        switch self {
        case .slate, .frostedGlass: false
        default: true
        }
    }
}

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

// `AIDifficulty` itself lives in `Models/AIDifficulty.swift` so the headless
// tools in `Scripts/` can compile it without SwiftUI. Only the colour is here.
extension AIDifficulty {
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
}
