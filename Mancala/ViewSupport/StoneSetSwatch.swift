import SwiftUI

/// A pinch of pebbles from a `StoneSetStyle`, for the Customize picker.
///
/// Drawn in SwiftUI rather than rendered from RealityKit: the tiles are 62pt
/// and static, so a real render would cost a scene and an offscreen pass to
/// land in roughly the same place. What it does borrow is the *finish* — a
/// matte set gets a duller fill and a weaker highlight than a polished one, so
/// the swatches differ the way the sets actually differ rather than looking
/// like five palettes of the same bead.
struct StoneSetSwatch: View {
    let style: StoneSetStyle
    let isDarkMode: Bool

    /// Sizes and offsets as fractions of the tile, so the cluster scales with
    /// whatever frame it is given.
    private static let layout: [(x: CGFloat, y: CGFloat, diameter: CGFloat)] = [
        (0.30, 0.30, 0.30),
        (0.68, 0.24, 0.24),
        (0.50, 0.56, 0.34),
        (0.24, 0.72, 0.26),
        (0.74, 0.70, 0.22),
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                backdrop

                ForEach(Array(style.tints.enumerated()), id: \.offset) { index, tint in
                    let spot = Self.layout[index % Self.layout.count]
                    pebble(tint: tint, diameter: side * spot.diameter)
                        .position(x: proxy.size.width * spot.x, y: proxy.size.height * spot.y)
                }
            }
        }
    }

    /// A neutral tray so the pebbles read as objects sitting on something
    /// rather than as floating dots. Deliberately low contrast — the pebbles
    /// are the subject.
    private var backdrop: some View {
        LinearGradient(
            colors: isDarkMode
                ? [Color(white: 0.17), Color(white: 0.11)]
                : [Color(white: 0.93), Color(white: 0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func pebble(tint: StoneTint, diameter: CGFloat) -> some View {
        let finish = style.finish
        // Roughness drives how much of the sheen survives: a tumbled river
        // stone keeps almost none, polished glass keeps all of it.
        let gloss = Double(max(0, 1 - finish.roughness))

        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        tint.color.opacity(Double(finish.opacity)),
                        tint.color.opacity(Double(finish.opacity) * 0.88),
                    ],
                    center: UnitPoint(x: 0.35, y: 0.32),
                    startRadius: 0,
                    endRadius: diameter * 0.8
                )
            )
            .overlay {
                Circle()
                    .fill(Color.white.opacity(0.10 + 0.55 * gloss * Double(finish.clearcoat)))
                    .frame(width: diameter * 0.30, height: diameter * 0.30)
                    .offset(x: -diameter * 0.18, y: -diameter * 0.20)
                    .blur(radius: diameter * 0.03 + diameter * 0.10 * (1 - gloss))
            }
            .overlay {
                // A darker lower edge; without it the matte sets read flat.
                Circle()
                    .strokeBorder(Color.black.opacity(0.16), lineWidth: diameter * 0.05)
                    .blur(radius: diameter * 0.04)
                    .mask(Circle())
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(isDarkMode ? 0.42 : 0.24),
                    radius: diameter * 0.06,
                    y: diameter * 0.05)
    }
}

#Preview {
    HStack(spacing: 10) {
        ForEach(StoneSetStyle.allCases) { style in
            VStack {
                StoneSetSwatch(style: style, isDarkMode: false)
                    .frame(width: 62, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                StoneSetSwatch(style: style, isDarkMode: true)
                    .frame(width: 62, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(style.title).font(.caption2)
            }
        }
    }
    .padding()
}
