import SwiftUI

/// Everything that changes how the game *looks* rather than how it *plays*.
///
/// Split out of Settings so that sheet can stay about rules, opponents, and
/// names. This one is expected to grow — stone colours, board finishes, wordmark
/// treatments — so it is written as a list of independent sections that can be
/// added to without any of them knowing about the others.
///
/// It owns its own `@AppStorage` rather than taking bindings, which is what lets
/// it be presented from two places (the main menu as a sheet, Settings as a
/// pushed page) without either caller having to hold state on its behalf. The
/// defaults come from `AppDefaults`, same as `ContentView`'s copies, so the two
/// never disagree about what "unset" means.
struct CustomizeView: View {
    @AppStorage("visualTheme") private var visualTheme = AppDefaults.visualTheme
    @AppStorage("boardBackgroundStyle") private var boardBackgroundStyle = AppDefaults.boardBackgroundStyle
    @AppStorage("boardMaterialStyle") private var boardMaterialStyle = AppDefaults.boardMaterialStyle
    @AppStorage("stoneSetStyle") private var stoneSetStyle = AppDefaults.stoneSetStyle

    @Environment(\.colorScheme) private var colorScheme

    /// Baked lazily so the sheet opens immediately and the tiles fill in.
    /// Seeded from `BoardMaterialSwatch`'s process-wide cache, so this is only
    /// ever empty the first time Customize is opened in a session.
    @State private var materialImages: [BoardMaterialStyle: CGImage] = [:]

    private var isDarkMode: Bool { colorScheme == .dark }

    /// The current finish is always listed, even if it has been withdrawn from
    /// the menu — otherwise the picker would show nothing selected.
    private var offeredMaterials: [BoardMaterialStyle] {
        var styles = BoardMaterialStyle.offered
        if !styles.contains(boardMaterialStyle) {
            styles.append(boardMaterialStyle)
        }
        return styles
    }

    var body: some View {
        Form {
            stoneSection
            materialSection
            backgroundSection
        }
        .task {
            for style in offeredMaterials where materialImages[style] == nil {
                materialImages[style] = await BoardMaterialSwatch.image(for: style)
            }
        }
    }

    // MARK: - Stones

    /// No Flat-theme caveat here, unlike the two below: the flat board draws
    /// its own two-tone dots and ignores this, but the menu pebbles use it in
    /// either theme, so the picker is always doing something.
    private var stoneSection: some View {
        Section {
            swatchRow(StoneSetStyle.allCases) { style in
                stoneSwatch(for: style)
            }

            Text(stoneSetStyle.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Pebbles")
        }
    }

    private func stoneSwatch(for style: StoneSetStyle) -> some View {
        swatchTile(
            title: style.title,
            isSelected: style == stoneSetStyle,
            accessibilityLabel: "\(style.title) pebbles"
        ) {
            stoneSetStyle = style
        } content: {
            StoneSetSwatch(style: style, isDarkMode: isDarkMode)
        }
    }

    // MARK: - Material

    @ViewBuilder
    private var materialSection: some View {
        Section {
            if visualTheme == .liquidGlass {
                swatchRow(offeredMaterials) { style in
                    materialSwatch(for: style)
                }

                Text(boardMaterialStyle.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("The Flat theme draws no board, so there is no surface to finish. Switch to Immersive in Settings to choose a material.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Board Material")
        }
    }

    private func materialSwatch(for style: BoardMaterialStyle) -> some View {
        swatchTile(
            title: style.title,
            isSelected: style == boardMaterialStyle,
            accessibilityLabel: "\(style.title) board material"
        ) {
            boardMaterialStyle = style
        } content: {
            if let image = materialImages[style] {
                // The texture is the board's top face, so filling the portrait
                // tile crops to a close-up of the surface — which is what a
                // material sample should be.
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundSection: some View {
        Section {
            if visualTheme == .liquidGlass {
                backgroundSwatchRow

                Text(boardBackgroundStyle.isAnimated
                     ? "\(boardBackgroundStyle.description) Drifts slowly; holds still when Reduce Motion is on."
                     : boardBackgroundStyle.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                // Rather than hiding the section outright, which reads as a bug
                // when you know you saw it a moment ago.
                Text("The Flat theme keeps a plain page — its pits are pressed straight into it, and a backdrop behind them would fight that. Switch to Immersive in Settings to choose a background.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Board Background")
        }
    }

    /// Swatches rather than a list of names: "Tide" and "Malachite" mean nothing
    /// until you see them, and each swatch is the real thing — the actual
    /// `BoardBackgroundView`, the actual baked texture — so what you pick is
    /// what you get. Backgrounds are rendered still (a picker running six drift
    /// loops isn't a trade worth making), so their caption carries the one thing
    /// a still can't show.
    private var backgroundSwatchRow: some View {
        swatchRow(BoardBackgroundStyle.allCases) { style in
            backgroundSwatch(for: style)
        }
    }

    private func backgroundSwatch(for style: BoardBackgroundStyle) -> some View {
        swatchTile(
            title: style.title,
            isSelected: style == boardBackgroundStyle,
            accessibilityLabel: "\(style.title) background\(style.isAnimated ? ", animated" : "")"
        ) {
            boardBackgroundStyle = style
        } content: {
            BoardBackgroundView(style: style, isDarkMode: isDarkMode, isAnimated: false)
        }
    }

    // MARK: - Shared swatch chrome

    /// One horizontal strip of tiles, full-bleed within its section.
    ///
    /// `listRowInsets` is stripped and the padding re-applied inside, because a
    /// scroll view left on the section's own inset clips at that inset — which
    /// cuts the last tile in half and reads as a layout bug rather than as
    /// "there is more to scroll to".
    private func swatchRow<Item: Identifiable, Tile: View>(
        _ items: [Item],
        @ViewBuilder tile: @escaping (Item) -> Tile
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    tile(item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .listRowInsets(EdgeInsets())
    }

    private static let tileWidth: CGFloat = 62
    private static let tileHeight: CGFloat = 84
    /// Two lines' worth, reserved on every tile so a wrapped label ("Brushed
    /// Brass") doesn't stand its neighbours up taller than itself.
    private static let labelHeight: CGFloat = 26

    private func swatchTile<Content: View>(
        title: String,
        isSelected: Bool,
        accessibilityLabel: String,
        select: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                select()
            }
        } label: {
            VStack(spacing: 6) {
                content()
                    .frame(width: Self.tileWidth, height: Self.tileHeight)
                    // `clipped` as well as `clipShape`: the material swatches
                    // are 2:1 textures shown `.scaledToFill`, so they render
                    // ~168pt wide inside a 62pt frame. `clipShape` hides the
                    // overflow but leaves it live for hit testing, which made
                    // every tile's touch area swallow both its neighbours —
                    // and since later HStack siblings hit-test in front, the
                    // tile to the right won every tap.
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.14),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    }

                Text(title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: Self.tileWidth, height: Self.labelHeight, alignment: .top)
            }
            // Pin the whole tile to the swatch's width. Left to itself the
            // VStack takes the width of its widest child — the label — so long
            // names grew the tappable area past the picture they belong to.
            .frame(width: Self.tileWidth)
            // The last word on where this button starts and stops, whatever
            // its contents do.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    NavigationStack {
        CustomizeView()
            .navigationTitle("Customize")
    }
}
