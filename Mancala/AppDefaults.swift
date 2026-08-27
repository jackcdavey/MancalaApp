import Foundation

/// The app's first-launch settings, gathered in one place so they can be
/// reviewed and changed without hunting through `@AppStorage` declarations.
///
/// Each value here seeds its setting the first time the app runs (or any time
/// the user has never touched that setting); once the user changes a setting
/// in-app, the stored value wins and the default is ignored. Persistence
/// blobs (saved games, history, migration flags) are not settings and stay
/// with their `@AppStorage` declarations in `ContentView`.
enum AppDefaults {
    // MARK: Game setup

    /// Mode the app opens in before the user ever picks one.
    static let gameMode = GameMode.twoPlayer
    /// Who takes the first turn in a fresh game.
    static let startingPlayer = StartingPlayer.human

    // MARK: Appearance

    /// Board style: `.liquidGlass` is the 3D board, `.flat` the minimal 2D one.
    static let visualTheme = VisualTheme.liquidGlass
    /// Finish of the 3D board's slab.
    static let boardMaterialStyle = BoardMaterialStyle.marble
    /// Page behind the board in the Immersive theme. `parchment` is the warm
    /// cream the app shipped with, so the default look is unchanged.
    static let boardBackgroundStyle = BoardBackgroundStyle.parchment
    /// Stone colours and finish. `classic` is the original set.
    static let stoneSetStyle = StoneSetStyle.classic
    /// Tilt-to-parallax on the 3D board.
    static let gyroMotionEnabled = false
    #if os(visionOS)
    /// Light the app adds to the 3D board on top of the room's own. `low`
    /// rather than `room` because the room's light alone takes the board down
    /// with it far too early; this is the gentlest step that still puts a floor
    /// under how dark the board can get.
    static let boardBrightness = BoardBrightness.low
    #endif
    /// Multiplier applied to every stone animation (0.25...4).
    static let stoneAnimationSpeed = 1.0
    /// Rotate the whole table 180° between turns in pass-and-play.
    static let flipScreenForTwoPlayerTurns = false
    /// Per-mode stone-count labels on the pits.
    static let singlePlayerShowNumberLabels = true
    static let twoPlayerShowNumberLabels = true
    static let zeroPlayerShowNumberLabels = true
    static let onlineShowNumberLabels = true

    // MARK: AI

    /// Single-player opponent difficulty.
    static let difficulty = AIDifficulty.medium
    /// Zero-player (AI vs AI) difficulties, per seat.
    static let zeroPlayerOneDifficulty = AIDifficulty.medium
    static let zeroPlayerTwoDifficulty = AIDifficulty.medium
    /// How the Impossible search is budgeted: by positions or by time.
    static let impossibleSearchLimitMode = ImpossibleSearchLimitMode.positions
    /// Position budget when limited by positions.
    static let impossibleSearchLimit = 10_000_000
    /// Seconds budget when limited by time.
    static let impossibleSearchTimeLimit = 10

    // MARK: Undo

    static let singlePlayerUndoButtonEnabled = false
    static let twoPlayerUndoButtonEnabled = false

    // MARK: Player names

    /// Seed names for every mode's two seats (single, two-player, zero-player,
    /// online, and the legacy pre-migration keys).
    static let playerOneName = "Player 1"
    static let playerTwoName = "Player 2"
}
