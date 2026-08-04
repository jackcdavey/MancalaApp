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

    var description: String {
        switch self {
        case .walnut: "Dark, open-grained hardwood."
        case .maple: "Pale close-grained wood with a soft sheen."
        case .terracotta: "Unglazed fired clay, matte and porous."
        case .marble: "Polished stone with drifting veins."
        case .malachite: "Banded green mineral, glassy and deep."
        case .slate: "Flat grey stone with a fine cleft surface."
        case .obsidian: "Volcanic glass, near-black and reflective."
        case .brushedBrass: "Warm metal with a fine directional grain."
        case .frostedGlass: "Translucent, etched, and cool."
        }
    }

    /// The finishes Customize offers. Withdrawn ones stay in `allCases` — they
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

/// The page behind the 3D board in the Immersive theme.
///
/// Only the Immersive theme offers these — the Flat theme's whole point is the
/// pits pressed into a plain page, and a moving backdrop under it would fight
/// that. `parchment` is the warm cream the app has always used, so it stays the
/// default and nothing changes for anyone who never opens the picker.
///
/// Every style is deliberately low-contrast: the board and its stones are the
/// subject, and a backdrop that competes with them has failed. The animated
/// ones drift on a cycle measured in tens of seconds and stop entirely under
/// Reduce Motion — see `BoardBackgroundView`.
enum BoardBackgroundStyle: String, CaseIterable, Identifiable {
    case parchment
    case linen
    case mist
    case tide
    case embers
    case nightfall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parchment: "Parchment"
        case .linen: "Linen"
        case .mist: "Mist"
        case .tide: "Tide"
        case .embers: "Embers"
        case .nightfall: "Nightfall"
        }
    }

    /// Whether the style drifts. Surfaced in Settings because the still preview
    /// swatches can't show it, and it's the thing people want to know.
    var isAnimated: Bool {
        switch self {
        case .parchment, .linen: false
        case .mist, .tide, .embers, .nightfall: true
        }
    }

    var description: String {
        switch self {
        case .parchment: "The original warm page. Still."
        case .linen: "A fine woven grain over the same warm page. Still."
        case .mist: "Soft blooms that breathe in and out."
        case .tide: "Wide bands drifting like light over shallow water."
        case .embers: "Warm motes hanging and drifting in the dark."
        case .nightfall: "A deep dusk sky with one slow travelling glow."
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
