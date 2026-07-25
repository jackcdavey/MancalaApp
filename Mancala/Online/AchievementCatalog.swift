import Foundation

/// The catalog of every Game Center achievement the app can award: its
/// identifier, reference display name, and the trigger that unlocks it —
/// all in one place so they can be reviewed and changed without digging
/// through the reporting logic.
///
/// The raw value is the achievement ID and must match App Store Connect
/// exactly; the display name and description shown to players also live in
/// App Store Connect — the `title`/`trigger` strings here are the reference
/// copy of that configuration. The numeric thresholds in
/// `AchievementThresholds` below are what the reporting code actually uses,
/// so editing them changes behavior immediately.
///
/// Who can earn achievements (enforced by `GameCenterAchievements`):
/// single player — only the human (player one); pass-and-play — either seat;
/// online — only the local player's side; zero-player (AI vs AI) — no one.
enum MancalaAchievement: String, CaseIterable {
    /// Win a game of Mancala for the first time (any mode where the local
    /// player wins).
    case firstWin = "mancala.first_win"
    /// Land the last stone in your own store, earning another turn.
    case extraTurn = "mancala.extra_turn"
    /// Capture opposite-pit stones by landing in an empty pit on your side.
    case capture = "mancala.capture"
    /// Make a single capture of at least
    /// `AchievementThresholds.bigCaptureStones` stones.
    case bigCapture = "mancala.big_capture"
    /// Win by no more than `AchievementThresholds.closeWinMargin` stones.
    case closeWin = "mancala.close_win"
    /// Win by at least `AchievementThresholds.dominantWinMargin` stones.
    case dominantWin = "mancala.dominant_win"
    /// Win an online multiplayer match.
    case onlineWin = "mancala.online_win"
    /// Beat the computer at any difficulty (single player).
    case beatAI = "mancala.beat_ai"
    /// Beat the computer on Hard or Impossible difficulty.
    case beatHardAI = "mancala.beat_hard_ai"
    /// Beat the computer on Impossible difficulty.
    case beatImpossibleAI = "mancala.beat_impossible_ai"

    /// Reference display name, mirroring the App Store Connect configuration.
    var title: String {
        switch self {
        case .firstWin: "First Victory"
        case .extraTurn: "Go Again"
        case .capture: "Captured"
        case .bigCapture: "Grand Heist"
        case .closeWin: "Photo Finish"
        case .dominantWin: "Landslide"
        case .onlineWin: "Worldly Winner"
        case .beatAI: "Machine Beater"
        case .beatHardAI: "Hard Mode Hero"
        case .beatImpossibleAI: "The Impossible"
        }
    }

    /// Human-readable unlock condition, kept in sync with the logic in
    /// `GameCenterAchievements` and the thresholds below.
    var trigger: String {
        switch self {
        case .firstWin:
            "Win a game"
        case .extraTurn:
            "Land your last stone in your own store to earn an extra turn"
        case .capture:
            "Capture your opponent's stones"
        case .bigCapture:
            "Capture \(AchievementThresholds.bigCaptureStones)+ stones in a single move"
        case .closeWin:
            "Win by \(AchievementThresholds.closeWinMargin) stones or fewer"
        case .dominantWin:
            "Win by \(AchievementThresholds.dominantWinMargin) stones or more"
        case .onlineWin:
            "Win an online multiplayer match"
        case .beatAI:
            "Beat the computer at any difficulty"
        case .beatHardAI:
            "Beat the computer on Hard or Impossible"
        case .beatImpossibleAI:
            "Beat the computer on Impossible"
        }
    }
}

/// The tunable numbers behind the triggers above. `GameCenterAchievements`
/// reads these directly, so a change here changes when achievements unlock.
enum AchievementThresholds {
    /// Minimum stones captured in one move for `bigCapture`.
    static let bigCaptureStones = 6
    /// Maximum winning margin (winner store minus loser store) for `closeWin`.
    static let closeWinMargin = 2
    /// Minimum winning margin for `dominantWin`.
    static let dominantWinMargin = 20
}
