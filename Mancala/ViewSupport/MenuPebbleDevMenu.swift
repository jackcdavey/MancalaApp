import SwiftUI

/// The development-only door onto the main menu's pebble animations: a list of
/// every shape, mood and set piece the idle loop can play, each previewable on
/// its own and switchable in or out of the deck while it's being worked on.
///
/// Off by default. Flip `isEnabled` to `true` and a "Pebble Animations" button
/// appears in Settings (from the menu and mid-game alike); flip it back and
/// every trace of this goes with it—`MenuPebbleStage` reads the switches only
/// when the flag is on, so the shipping menu behaves exactly as it did before
/// any of this existed.
///
/// The switches themselves survive a relaunch, which is the point: the loop is
/// slow enough that reviewing one routine means waiting several cycles for it
/// unless everything else is out of the way.
enum PebbleDevMenu {
    /// The switch. `false` for anything that ships.
    static let isEnabled = false

    static let settings = PebbleAnimationSettings()

    /// Drops anything switched off from a deck the idle loop is about to draw
    /// from. A no-op—not even a copy—while the dev menu is off.
    static func enabled<T: PebbleAnimationSwitchable>(_ deck: [T]) -> [T] {
        guard isEnabled else { return deck }
        return deck.filter { settings.isEnabled($0.animationID) }
    }
}

/// Anything the dev menu can switch off. The stage's types already carry a
/// stable `animationID`; this just lets one deck-filtering function serve all
/// three of them.
protocol PebbleAnimationSwitchable {
    var animationID: String { get }
}

extension MenuPebbleStage.Formation: PebbleAnimationSwitchable {}
extension MenuPebbleStage.Mood: PebbleAnimationSwitchable {}
extension MenuPebbleStage.Routine: PebbleAnimationSwitchable {}

// MARK: - Storage

/// Which animations are currently switched off, remembered across launches.
///
/// Stored as the disabled set rather than the enabled one so that an animation
/// added to the catalog later starts out on, the way a new animation should.
@Observable
final class PebbleAnimationSettings {
    private static let storageKey = "dev.disabledPebbleAnimations"

    private(set) var disabledIDs: Set<String>

    init() {
        disabledIDs = Set(UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? [])
    }

    func isEnabled(_ id: String) -> Bool {
        !disabledIDs.contains(id)
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        if enabled {
            disabledIDs.remove(id)
        } else {
            disabledIDs.insert(id)
        }
        persist()
    }

    /// Switches a whole section on or off at once—the quick way to get down to
    /// the one routine you're actually looking at.
    func setEnabled(_ enabled: Bool, for items: [MenuPebbleStage.AnimationItem]) {
        for item in items {
            if enabled {
                disabledIDs.remove(item.id)
            } else {
                disabledIDs.insert(item.id)
            }
        }
        persist()
    }

    func enableAll() {
        disabledIDs.removeAll()
        persist()
    }

    /// Folded into the stage's `.task` id: the idle loop reads its decks once
    /// at the top, so it has to be restarted for a switch to take effect.
    var loopKeyFragment: String {
        disabledIDs.sorted().joined(separator: ",")
    }

    private func persist() {
        UserDefaults.standard.set(Array(disabledIDs), forKey: Self.storageKey)
    }
}

// MARK: - Catalog list

/// The list behind Settings › Pebble Animations. Rows push a preview; the
/// toggles decide what the real menu is allowed to play.
struct MenuPebbleDevMenuView: View {
    /// Passed through to the preview stages so they're tinted like the menu's
    /// own pebbles rather than guessing at the theme.
    let color: (Int) -> Color
    let isDarkMode: Bool

    private var settings: PebbleAnimationSettings { PebbleDevMenu.settings }

    var body: some View {
        List {
            ForEach(MenuPebbleStage.AnimationItem.Kind.allCases, id: \.self) { kind in
                section(for: kind)
            }

            Section {
                Button("Enable All") {
                    settings.enableAll()
                }
                .disabled(settings.disabledIDs.isEmpty)
            } footer: {
                Text("Switches are remembered between launches, so anything left off here stays off next time you run the app.")
            }
        }
        .navigationTitle("Pebble Animations")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func section(for kind: MenuPebbleStage.AnimationItem.Kind) -> some View {
        let items = MenuPebbleStage.animationItems(of: kind)
        let allOff = items.allSatisfy { !settings.isEnabled($0.id) }

        return Section {
            ForEach(items) { item in
                row(for: item)
            }

            Button(allOff ? "Enable All \(kind.title)" : "Disable All \(kind.title)") {
                settings.setEnabled(allOff, for: items)
            }
            .font(.footnote)
        } header: {
            Text(kind.title)
        } footer: {
            Text(kind.footer)
        }
    }

    private func row(for item: MenuPebbleStage.AnimationItem) -> some View {
        let enabled = settings.isEnabled(item.id)

        return NavigationLink {
            MenuPebbleAnimationPreview(item: item, color: color, isDarkMode: isDarkMode)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)

                    Text(item.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if !enabled {
                    Text("OFF")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(enabled ? 1 : 0.5)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(enabled ? "Disable" : "Enable") {
                settings.setEnabled(!enabled, for: item.id)
            }
            .tint(enabled ? .orange : .green)
        }
    }
}

// MARK: - Preview screen

/// One animation, on a loop, with nothing else on screen competing with it.
/// The stage is the real one, so the pebbles are still pushable here.
struct MenuPebbleAnimationPreview: View {
    let item: MenuPebbleStage.AnimationItem
    let color: (Int) -> Color
    let isDarkMode: Bool

    /// Bumped to remount the stage, which is how a run is restarted: the drive
    /// loop is a `.task`, so a fresh identity is a fresh run from the top.
    @State private var runID = 0

    private var settings: PebbleAnimationSettings { PebbleDevMenu.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stage

                Text(item.detail)
                    .font(.callout)

                Text(item.previewNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Include in the Menu Loop", isOn: Binding(
                    get: { settings.isEnabled(item.id) },
                    set: { settings.setEnabled($0, for: item.id) }
                ))

                Button("Restart") {
                    runID += 1
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(item.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Generous height and no clipping: the wheel routine deliberately rolls
    /// clean off the side, and a preview that cropped it would be lying about
    /// what the menu does.
    private var stage: some View {
        MenuPebbleStage(color: color, isDarkMode: isDarkMode, preview: item)
            .id(runID)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(isDarkMode ? 0.08 : 0.04))
            }
    }
}
