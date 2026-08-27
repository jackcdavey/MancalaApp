import SwiftUI

/// Draws the page behind the 3D board for a `BoardBackgroundStyle`.
///
/// Three rules shape everything here:
///
/// * **The board is the subject.** Every palette is low-contrast and stays out
///   of the middle of the value range, so stones and pit shadows keep their
///   separation. Nothing here should ever read as foreground.
/// * **Drift, don't animate.** The moving styles run one `drift` value from 0
///   to 1 and back on a cycle of 20–34 seconds. That is slow enough that the
///   motion is felt rather than watched, and cheap enough to leave running for
///   a whole game — it is a handful of gradient fills, no per-frame redraw and
///   no `TimelineView`.
/// * **Reduce Motion means still.** The drift simply never starts, and the
///   layout is composed at the midpoint of its travel so the still version is
///   the same picture, not a corner case.
struct BoardBackgroundView: View {
    let style: BoardBackgroundStyle
    let isDarkMode: Bool
    /// Settings shows every style at once. Six independent repeating animations
    /// for decoration is not a trade worth making, so the swatches are stills.
    var isAnimated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0...1, eased and auto-reversing. Every moving layer derives its position
    /// from this one value, which is what keeps the styles feeling coherent
    /// rather than like several things happening at once.
    @State private var drift: Double = 0.5

    private var shouldDrift: Bool {
        isAnimated && style.isAnimated && !reduceMotion
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: palette.base,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                layers(in: proxy.size)
            }
            // Blooms and bands are deliberately drawn larger than the frame so
            // their soft edges fall outside it; without this they'd show a hard
            // cut where the gradient's own falloff hasn't finished.
            .clipped()
        }
        .perfProbe("BoardBackground")
        .onAppear(perform: restartDrift)
        .onChange(of: reduceMotion) { _, _ in restartDrift() }
        .onChange(of: style) { _, _ in restartDrift() }
    }

    private func restartDrift() {
        guard shouldDrift else {
            // Mid-travel, so a still style is the same composition the moving
            // one passes through rather than one end of its swing.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { drift = 0.5 }
            return
        }

        drift = 0
        withAnimation(.easeInOut(duration: cycleDuration).repeatForever(autoreverses: true)) {
            drift = 1
        }
    }

    private var cycleDuration: Double {
        switch style {
        case .parchment, .linen: 1
        case .mist: 26
        case .tide: 22
        case .embers: 30
        case .nightfall: 34
        }
    }

    // MARK: - Style layers

    @ViewBuilder
    private func layers(in size: CGSize) -> some View {
        switch style {
        case .parchment:
            EmptyView()
        case .linen:
            weave(in: size)
        case .mist:
            blooms(in: size)
        case .tide:
            bands(in: size)
        case .embers:
            motes(in: size)
        case .nightfall:
            travellingGlow(in: size)
        }
    }

    /// A woven grain. Drawn as lines rather than sampled noise so it stays crisp
    /// at any scale and costs one static `Canvas` pass.
    private func weave(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let spacing: CGFloat = 3
            let thread = palette.accents[0]

            var x: CGFloat = 0
            while x < canvasSize.width {
                context.fill(
                    Path(CGRect(x: x, y: 0, width: 0.5, height: canvasSize.height)),
                    with: .color(thread)
                )
                x += spacing
            }

            var y: CGFloat = 0
            while y < canvasSize.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: canvasSize.width, height: 0.5)),
                    with: .color(thread.opacity(0.6))
                )
                y += spacing
            }
        }
        .frame(width: size.width, height: size.height)
        .blendMode(isDarkMode ? .plusLighter : .multiply)
    }

    /// Three overlapping soft blooms that breathe. They move on different axes
    /// and at different amounts so the group never reads as one sliding object.
    private func blooms(in size: CGSize) -> some View {
        let span = max(size.width, size.height)

        return ZStack {
            bloom(colour: palette.accents[0], diameter: span * 1.05)
                .offset(x: -span * (0.20 - 0.06 * drift), y: -span * (0.24 - 0.05 * drift))
                .scaleEffect(0.94 + 0.10 * drift)

            bloom(colour: palette.accents[1], diameter: span * 0.86)
                .offset(x: span * (0.24 - 0.05 * drift), y: span * (0.10 + 0.06 * drift))
                .scaleEffect(1.04 - 0.09 * drift)

            bloom(colour: palette.accents[2], diameter: span * 0.70)
                .offset(x: span * (0.05 - 0.10 * drift), y: span * (0.30 - 0.04 * drift))
                .scaleEffect(0.98 + 0.06 * drift)
        }
        .frame(width: size.width, height: size.height)
    }

    private func bloom(colour: Color, diameter: CGFloat) -> some View {
        // A radial gradient that fades fully to clear is its own blur, and far
        // cheaper than putting a real `.blur` on something this large.
        Circle()
            .fill(
                RadialGradient(
                    colors: [colour, colour.opacity(0.45), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
    }

    /// Wide horizontal bands sliding at different rates, like light moving over
    /// shallow water. Rotated slightly so they don't read as a striped flag.
    private func bands(in size: CGSize) -> some View {
        let span = max(size.width, size.height) * 1.6

        return ZStack {
            band(colour: palette.accents[0], width: span, height: size.height * 0.30)
                .offset(x: -span * (0.10 - 0.14 * drift), y: -size.height * 0.24)

            band(colour: palette.accents[1], width: span, height: size.height * 0.24)
                .offset(x: span * (0.12 - 0.16 * drift), y: size.height * 0.02)

            band(colour: palette.accents[2], width: span, height: size.height * 0.34)
                .offset(x: -span * (0.06 - 0.11 * drift), y: size.height * 0.28)
        }
        .rotationEffect(.degrees(-6))
        .frame(width: size.width, height: size.height)
    }

    private func band(colour: Color, width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, colour, colour.opacity(0.55), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
    }

    /// Warm motes hanging in the dark. They drift a little and breathe in
    /// brightness rather than rising and looping — a loop that has to wrap is a
    /// loop you eventually notice, which is the opposite of the point.
    private func motes(in size: CGSize) -> some View {
        // Fixed layout rather than random: the composition was chosen, and it
        // should be the same one every launch.
        let seeds: [(x: CGFloat, y: CGFloat, scale: CGFloat, lift: CGFloat, phase: Double)] = [
            (0.16, 0.74, 1.00, 0.055, 0.0),
            (0.32, 0.30, 0.62, 0.038, 0.6),
            (0.54, 0.84, 0.78, 0.048, 0.25),
            (0.70, 0.22, 1.15, 0.062, 0.85),
            (0.86, 0.60, 0.70, 0.042, 0.45),
            (0.44, 0.52, 0.52, 0.030, 0.15),
            (0.08, 0.36, 0.58, 0.035, 0.70),
        ]
        let unit = max(size.width, size.height) * 0.30

        return ZStack {
            ForEach(Array(seeds.enumerated()), id: \.offset) { index, seed in
                // Half a turn, not a whole one. SwiftUI evaluates this body at
                // the endpoints and interpolates the resolved offsets, so a
                // full turn would land on sin(x) and sin(x + 2π) — the same
                // number — and every mote would sit perfectly still.
                let swing = sin((drift * 0.5 + seed.phase) * .pi * 2)
                bloom(colour: palette.accents[index % palette.accents.count],
                      diameter: unit * seed.scale)
                    .position(
                        x: size.width * seed.x,
                        y: size.height * seed.y - size.height * seed.lift * swing
                    )
                    .opacity(0.70 + 0.30 * (0.5 + 0.5 * swing))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// One very large, very soft glow crossing the sky. Slow enough that you
    /// only register it has moved by looking away and back.
    private func travellingGlow(in size: CGSize) -> some View {
        let span = max(size.width, size.height)

        return ZStack {
            bloom(colour: palette.accents[0], diameter: span * 1.4)
                .offset(x: span * (-0.32 + 0.64 * drift), y: -span * (0.20 + 0.06 * drift))

            bloom(colour: palette.accents[1], diameter: span * 0.9)
                .offset(x: span * (0.26 - 0.30 * drift), y: span * 0.26)
                .opacity(0.75)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Palettes

    private struct Palette {
        let base: [Color]
        let accents: [Color]
    }

    private var palette: Palette {
        isDarkMode ? darkPalette : lightPalette
    }

    private var lightPalette: Palette {
        switch style {
        case .parchment:
            Palette(
                base: [
                    Color(red: 0.958, green: 0.945, blue: 0.915),
                    Color(red: 0.942, green: 0.926, blue: 0.891),
                    Color(red: 0.918, green: 0.898, blue: 0.860),
                ],
                accents: []
            )
        case .linen:
            Palette(
                base: [
                    Color(red: 0.960, green: 0.948, blue: 0.921),
                    Color(red: 0.941, green: 0.926, blue: 0.893),
                    Color(red: 0.921, green: 0.902, blue: 0.865),
                ],
                accents: [Color(red: 0.62, green: 0.58, blue: 0.51).opacity(0.055)]
            )
        case .mist:
            Palette(
                base: [
                    Color(red: 0.954, green: 0.949, blue: 0.938),
                    Color(red: 0.930, green: 0.928, blue: 0.922),
                    Color(red: 0.902, green: 0.904, blue: 0.906),
                ],
                accents: [
                    Color.white.opacity(0.55),
                    Color(red: 0.80, green: 0.84, blue: 0.88).opacity(0.42),
                    Color(red: 0.93, green: 0.90, blue: 0.85).opacity(0.40),
                ]
            )
        case .tide:
            Palette(
                base: [
                    Color(red: 0.944, green: 0.951, blue: 0.943),
                    Color(red: 0.918, green: 0.933, blue: 0.928),
                    Color(red: 0.890, green: 0.914, blue: 0.910),
                ],
                accents: [
                    Color(red: 0.72, green: 0.82, blue: 0.80).opacity(0.30),
                    Color.white.opacity(0.42),
                    Color(red: 0.78, green: 0.85, blue: 0.83).opacity(0.26),
                ]
            )
        case .embers:
            Palette(
                base: [
                    Color(red: 0.962, green: 0.940, blue: 0.902),
                    Color(red: 0.940, green: 0.912, blue: 0.870),
                    Color(red: 0.914, green: 0.881, blue: 0.833),
                ],
                accents: [
                    Color(red: 0.94, green: 0.76, blue: 0.50).opacity(0.34),
                    Color(red: 0.90, green: 0.64, blue: 0.44).opacity(0.28),
                    Color(red: 0.97, green: 0.86, blue: 0.66).opacity(0.32),
                ]
            )
        case .nightfall:
            Palette(
                base: [
                    Color(red: 0.902, green: 0.898, blue: 0.918),
                    Color(red: 0.872, green: 0.870, blue: 0.900),
                    Color(red: 0.843, green: 0.847, blue: 0.884),
                ],
                accents: [
                    Color(red: 0.98, green: 0.86, blue: 0.78).opacity(0.42),
                    Color(red: 0.80, green: 0.80, blue: 0.92).opacity(0.36),
                ]
            )
        }
    }

    private var darkPalette: Palette {
        switch style {
        case .parchment:
            Palette(
                base: [
                    Color(red: 0.100, green: 0.090, blue: 0.080),
                    Color(red: 0.130, green: 0.120, blue: 0.105),
                    Color(red: 0.160, green: 0.150, blue: 0.130),
                ],
                accents: []
            )
        case .linen:
            Palette(
                base: [
                    Color(red: 0.104, green: 0.094, blue: 0.084),
                    Color(red: 0.132, green: 0.122, blue: 0.107),
                    Color(red: 0.158, green: 0.148, blue: 0.128),
                ],
                accents: [Color(red: 0.85, green: 0.80, blue: 0.70).opacity(0.030)]
            )
        case .mist:
            Palette(
                base: [
                    Color(red: 0.086, green: 0.090, blue: 0.098),
                    Color(red: 0.112, green: 0.118, blue: 0.128),
                    Color(red: 0.140, green: 0.147, blue: 0.158),
                ],
                accents: [
                    Color(red: 0.62, green: 0.70, blue: 0.80).opacity(0.20),
                    Color(red: 0.50, green: 0.58, blue: 0.70).opacity(0.17),
                    Color(red: 0.72, green: 0.68, blue: 0.62).opacity(0.14),
                ]
            )
        case .tide:
            Palette(
                base: [
                    Color(red: 0.062, green: 0.088, blue: 0.094),
                    Color(red: 0.086, green: 0.118, blue: 0.126),
                    Color(red: 0.108, green: 0.146, blue: 0.154),
                ],
                accents: [
                    Color(red: 0.44, green: 0.72, blue: 0.72).opacity(0.20),
                    Color(red: 0.66, green: 0.86, blue: 0.86).opacity(0.16),
                    Color(red: 0.38, green: 0.62, blue: 0.66).opacity(0.18),
                ]
            )
        case .embers:
            Palette(
                base: [
                    Color(red: 0.104, green: 0.076, blue: 0.058),
                    Color(red: 0.132, green: 0.098, blue: 0.072),
                    Color(red: 0.160, green: 0.120, blue: 0.088),
                ],
                accents: [
                    Color(red: 0.98, green: 0.62, blue: 0.30).opacity(0.26),
                    Color(red: 0.92, green: 0.46, blue: 0.24).opacity(0.20),
                    Color(red: 1.00, green: 0.78, blue: 0.46).opacity(0.24),
                ]
            )
        case .nightfall:
            Palette(
                base: [
                    Color(red: 0.052, green: 0.056, blue: 0.088),
                    Color(red: 0.076, green: 0.082, blue: 0.124),
                    Color(red: 0.100, green: 0.108, blue: 0.158),
                ],
                accents: [
                    Color(red: 0.52, green: 0.46, blue: 0.78).opacity(0.30),
                    Color(red: 0.90, green: 0.62, blue: 0.52).opacity(0.20),
                ]
            )
        }
    }
}

#Preview("Backgrounds") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
            ForEach(BoardBackgroundStyle.allCases) { style in
                VStack(spacing: 6) {
                    BoardBackgroundView(style: style, isDarkMode: false)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    BoardBackgroundView(style: style, isDarkMode: true)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(style.title).font(.caption)
                }
            }
        }
        .padding()
    }
}
