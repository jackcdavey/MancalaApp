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

    /// Roughly the finish's average colour, drawn instantly while the real
    /// texture bakes. A tile that starts the right colour and sharpens into
    /// grain reads as loading; a grey box reads as broken.
    var previewTint: Color {
        switch self {
        case .walnut: Color(red: 0.42, green: 0.27, blue: 0.16)
        case .maple: Color(red: 0.79, green: 0.68, blue: 0.50)
        case .terracotta: Color(red: 0.70, green: 0.42, blue: 0.30)
        case .marble: Color(red: 0.87, green: 0.87, blue: 0.88)
        case .malachite: Color(red: 0.10, green: 0.36, blue: 0.24)
        case .slate: Color(red: 0.34, green: 0.36, blue: 0.38)
        case .obsidian: Color(red: 0.08, green: 0.07, blue: 0.10)
        case .brushedBrass: Color(red: 0.72, green: 0.58, blue: 0.28)
        case .frostedGlass: Color(red: 0.82, green: 0.86, blue: 0.88)
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

/// One stone colour, kept as plain components so both renderers can have it
/// in the form they need — SwiftUI `Color` for the 2D board and the menu
/// pebbles, `SIMD3<Float>` for RealityKit's materials.
struct StoneTint: Hashable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

/// How a stone set's surface behaves under light. Mirrors the subset of
/// `PhysicallyBasedMaterial` that `StoneFactory` sets, so a set can read as
/// polished glass, matte river rock, or frosted sea glass without any of them
/// needing their own code path.
struct StoneFinish: Hashable {
    let roughness: Float
    let metallic: Float
    let clearcoat: Float
    let clearcoatRoughness: Float
    /// Below 1 reads as translucency. True refraction isn't available.
    let opacity: Float
}

/// The pebbles. `classic` is the set the app shipped with, down to the exact
/// components and finish values, so it stays the default and nothing changes
/// for anyone who never opens the picker.
///
/// Sets vary in *finish* as well as colour — that is most of what makes them
/// feel different, and a palette swap alone reads as a recolour rather than as
/// a different material.
enum StoneSetStyle: String, CaseIterable, Identifiable {
    case classic
    case riverStone
    case seaGlass
    case nightSky
    case autumn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .riverStone: "River Stone"
        case .seaGlass: "Sea Glass"
        case .nightSky: "Night Sky"
        case .autumn: "Autumn"
        }
    }

    var description: String {
        switch self {
        case .classic: "Bright glass gems. The original set."
        case .riverStone: "Tumbled pebbles, matte and earthy."
        case .seaGlass: "Frosted, softly translucent pastels."
        case .nightSky: "Deep jewel tones with a wet polish."
        case .autumn: "Warm ambers, russets, and olive."
        }
    }

    var tints: [StoneTint] {
        switch self {
        case .classic:
            [
                StoneTint(red: 0.13, green: 0.42, blue: 0.92),
                StoneTint(red: 0.95, green: 0.55, blue: 0.16),
                StoneTint(red: 0.14, green: 0.62, blue: 0.56),
                StoneTint(red: 0.84, green: 0.22, blue: 0.34),
                StoneTint(red: 0.55, green: 0.42, blue: 0.86),
            ]
        case .riverStone:
            [
                StoneTint(red: 0.47, green: 0.47, blue: 0.46),
                StoneTint(red: 0.62, green: 0.58, blue: 0.52),
                StoneTint(red: 0.35, green: 0.36, blue: 0.38),
                StoneTint(red: 0.71, green: 0.66, blue: 0.58),
                StoneTint(red: 0.52, green: 0.48, blue: 0.44),
            ]
        case .seaGlass:
            [
                StoneTint(red: 0.60, green: 0.82, blue: 0.78),
                StoneTint(red: 0.78, green: 0.86, blue: 0.72),
                StoneTint(red: 0.55, green: 0.72, blue: 0.80),
                StoneTint(red: 0.86, green: 0.82, blue: 0.68),
                StoneTint(red: 0.70, green: 0.76, blue: 0.84),
            ]
        case .nightSky:
            [
                StoneTint(red: 0.16, green: 0.20, blue: 0.42),
                StoneTint(red: 0.32, green: 0.16, blue: 0.42),
                StoneTint(red: 0.10, green: 0.28, blue: 0.34),
                StoneTint(red: 0.42, green: 0.18, blue: 0.30),
                StoneTint(red: 0.12, green: 0.14, blue: 0.24),
            ]
        case .autumn:
            [
                StoneTint(red: 0.78, green: 0.44, blue: 0.14),
                StoneTint(red: 0.60, green: 0.22, blue: 0.16),
                StoneTint(red: 0.86, green: 0.66, blue: 0.28),
                StoneTint(red: 0.42, green: 0.44, blue: 0.22),
                StoneTint(red: 0.70, green: 0.34, blue: 0.20),
            ]
        }
    }

    var finish: StoneFinish {
        switch self {
        case .classic:
            StoneFinish(roughness: 0.06, metallic: 0, clearcoat: 1.0, clearcoatRoughness: 0.08, opacity: 0.94)
        case .riverStone:
            StoneFinish(roughness: 0.62, metallic: 0, clearcoat: 0.20, clearcoatRoughness: 0.45, opacity: 1.0)
        case .seaGlass:
            StoneFinish(roughness: 0.34, metallic: 0, clearcoat: 0.55, clearcoatRoughness: 0.30, opacity: 0.82)
        case .nightSky:
            StoneFinish(roughness: 0.04, metallic: 0.15, clearcoat: 1.0, clearcoatRoughness: 0.05, opacity: 0.97)
        case .autumn:
            StoneFinish(roughness: 0.20, metallic: 0, clearcoat: 0.80, clearcoatRoughness: 0.16, opacity: 0.95)
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
