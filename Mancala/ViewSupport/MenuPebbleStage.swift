import SwiftUI

/// The five decorative pebbles above the main menu wordmark. At rest they sit
/// in the same orderly row they always have; between rests they roll out into a
/// shape, hold it, and roll home again. Shapes and "moods" (how energetically
/// the trip is made) are drawn from shuffled decks so the loop never repeats
/// itself the same way twice.
///
/// The whole thing lives and dies with the menu: the drive loop is a `.task`,
/// so entering a game or opening the challenge list cancels it, and coming back
/// restarts from the resting row.
struct MenuPebbleStage: View {
    /// Injected rather than duplicated—`ContentView.stoneColor(for:)` already
    /// branches on the visual theme.
    let color: (Int) -> Color
    let isDarkMode: Bool

    @Environment(\.mancalaVisualTheme) private var visualTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var formation: Formation = .home
    @State private var mood: Mood = .tumble
    /// Accumulated spin per pebble, in degrees. Path-dependent, so it can't be
    /// derived from `formation` alone.
    @State private var roll = [Double](repeating: 0, count: Layout.count)

    var body: some View {
        ZStack {
            ForEach(0..<Layout.count, id: \.self) { index in
                pebble(index: index)
            }
        }
        .frame(height: Layout.stageHeight)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .task(id: loopKey) {
            await runIdleLoop()
        }
    }

    // MARK: Pebble

    private func pebble(index: Int) -> some View {
        let diameter = Layout.diameters[index]
        let position = formation.positions[index]
        let tint = color(index).opacity(isDarkMode ? 0.82 : 0.92)
        let travel = mood.travel.delay(Double(index) * mood.stagger)

        return Circle()
            // Flat stones are matte by design (see `stoneView`); only the glass
            // theme gets the sheen.
            .fill(visualTheme == .flat ? AnyShapeStyle(tint) : AnyShapeStyle(tint.gradient))
            .frame(width: diameter, height: diameter)
            .overlay { flecks(diameter: diameter) }
            .rotationEffect(.degrees(roll[index]))
            .animation(travel, value: roll[index])
            // Outside the rotation: a specular highlight that spun with the
            // body would read as a painted dot rather than a reflection.
            .overlay { specular(diameter: diameter) }
            .shadow(color: .black.opacity(isDarkMode ? 0.32 : 0.15), radius: 2, x: 0, y: 1.5)
            .offset(x: position.x, y: position.y)
            .animation(travel, value: formation)
    }

    /// Surface markings—the only reason rotation is visible at all on a circle.
    @ViewBuilder
    private func flecks(diameter: CGFloat) -> some View {
        let isFlat = visualTheme == .flat

        ZStack {
            Circle()
                .fill(Color.black.opacity(isFlat ? 0.10 : 0.16))
                .frame(width: diameter * 0.20, height: diameter * 0.20)
                .offset(x: -diameter * 0.16, y: diameter * 0.20)

            if !isFlat {
                Circle()
                    .fill(Color.black.opacity(0.11))
                    .frame(width: diameter * 0.13, height: diameter * 0.13)
                    .offset(x: diameter * 0.24, y: -diameter * 0.10)
            }
        }
    }

    @ViewBuilder
    private func specular(diameter: CGFloat) -> some View {
        if visualTheme != .flat {
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: diameter * 0.28, height: diameter * 0.28)
                .offset(x: -diameter * 0.20, y: -diameter * 0.22)
                .blur(radius: 0.4)
        }
    }

    // MARK: Drive loop

    /// Restarts the loop when Reduce Motion is toggled or the app leaves the
    /// foreground; `.task(id:)` cancels the previous run for us.
    private var loopKey: String {
        "\(reduceMotion)-\(scenePhase == .active)"
    }

    private func runIdleLoop() async {
        guard !reduceMotion, scenePhase == .active else {
            formation = .home
            return
        }

        var shapes: [Formation] = []
        var moods: [Mood] = []
        var lastShape: Formation?

        // Let the menu's own fade-in finish before anything moves.
        guard await pause(1.2) else { return }

        while !Task.isCancelled {
            if shapes.isEmpty {
                shapes = Formation.roaming.shuffled()
                // `removeLast` draws from the end, so a repeat of the shape we
                // just showed is only possible at that one position.
                if shapes.count > 1, shapes.last == lastShape {
                    shapes.swapAt(0, shapes.count - 1)
                }
            }
            if moods.isEmpty {
                moods = Mood.all.shuffled()
            }

            let nextMood = moods.removeLast()
            let nextShape = shapes.removeLast()
            lastShape = nextShape

            // Set the mood first: the pebbles read it when building the
            // animation for the formation change below.
            mood = nextMood
            move(to: nextShape, rolling: nextMood.rolls)
            guard await pause(nextMood.settle + nextMood.hold) else { return }

            move(to: .home, rolling: nextMood.rolls)
            guard await pause(nextMood.settle + nextMood.rest) else { return }
        }
    }

    private func move(to next: Formation, rolling: Bool) {
        if rolling {
            let from = formation.positions
            let to = next.positions
            for index in 0..<Layout.count {
                let distance = to[index].x - from[index].x
                let radius = Layout.diameters[index] / 2
                roll[index] += Double(distance / radius) * (180 / .pi) * Layout.rollFactor
            }
        }
        formation = next
    }

    /// Returns false when the loop was cancelled mid-sleep.
    private func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Layout

extension MenuPebbleStage {
    fileprivate enum Layout {
        static let count = 5
        /// The centre pebble has always been the fat one.
        static let diameters: [CGFloat] = [10, 10, 13, 10, 10]
        static let stageHeight: CGFloat = 54
        /// Full physical rolling (`1.0`) spins fast enough to blur on long
        /// hops; this trims it back to something that reads as a roll.
        static let rollFactor: Double = 0.7
    }
}

// MARK: - Formations

extension MenuPebbleStage {
    /// Pebble positions as offsets from the centre of the stage. Every case
    /// stays inside roughly ±61pt horizontally and ±25pt vertically (including
    /// the pebble radius), so nothing escapes the stage frame.
    fileprivate enum Formation: CaseIterable, Equatable {
        /// The resting row: the original `HStack(spacing: 9)` laid out by hand.
        case home
        case ring
        case arc
        case wave
        case cascade
        case pyramid
        case orbit
        case huddle

        /// Everything except `home`—the loop always returns home in between.
        static let roaming: [Formation] = allCases.filter { $0 != .home }

        var positions: [CGPoint] {
            switch self {
            case .home:
                return points(x: [-39.5, -20.5, 0, 20.5, 39.5], y: [0, 0, 0, 0, 0])
            case .ring:
                return ellipse(radiusX: 46, radiusY: 20, degrees: [-90, -18, 54, 126, 198])
            case .arc:
                let xs: [CGFloat] = [-52, -26, 0, 26, 52]
                return xs.map { x in
                    let t = x / 52
                    return CGPoint(x: x, y: -8 + t * t * 18)
                }
            case .wave:
                return points(x: [-56, -28, 0, 28, 56], y: [-13, 9, -13, 9, -13])
            case .cascade:
                return points(x: [-48, -24, 0, 24, 48], y: [-16, -8, 0, 8, 16])
            case .pyramid:
                // Three low, two perched between them—the big centre pebble
                // anchors the base.
                return points(x: [-26, -13, 0, 13, 26], y: [12, -11, 12, -11, 12])
            case .orbit:
                var ring = ellipse(radiusX: 40, radiusY: 18, degrees: [225, 135, 0, 45, 315])
                ring[2] = .zero
                return ring
            case .huddle:
                return points(x: [-9, -4, 0, 5, 9], y: [3, -7, 2, -7, 3])
            }
        }

        private func points(x: [CGFloat], y: [CGFloat]) -> [CGPoint] {
            zip(x, y).map { CGPoint(x: $0, y: $1) }
        }

        private func ellipse(radiusX: CGFloat, radiusY: CGFloat, degrees: [Double]) -> [CGPoint] {
            degrees.map { angle in
                let radians = angle * .pi / 180
                return CGPoint(x: radiusX * CGFloat(cos(radians)), y: radiusY * CGFloat(sin(radians)))
            }
        }
    }
}

// MARK: - Moods

extension MenuPebbleStage {
    /// How a single out-and-back cycle is performed. Cycles are drawn from a
    /// shuffled deck of these so the loop reads as varied rather than timed.
    fileprivate struct Mood: Equatable {
        let travel: Animation
        /// Roughly how long `travel` needs to look finished—used only for
        /// pacing the sleeps, not for the animation itself.
        let settle: Double
        /// Per-pebble departure delay, so the row breaks apart rather than
        /// moving as one block.
        let stagger: Double
        let rolls: Bool
        let hold: Double
        let rest: Double

        static let tumble = Mood(
            travel: .spring(response: 0.62, dampingFraction: 0.62),
            settle: 1.2,
            stagger: 0.055,
            rolls: true,
            hold: 1.2,
            rest: 1.8
        )

        /// Slow and weightless: no rolling, because a lazy drift that spins
        /// looks driven rather than drifting.
        static let drift = Mood(
            travel: .easeInOut(duration: 1.9),
            settle: 2.4,
            stagger: 0.12,
            rolls: false,
            hold: 2.0,
            rest: 3.0
        )

        static let cascadeRoll = Mood(
            travel: .spring(response: 0.50, dampingFraction: 0.80),
            settle: 1.2,
            stagger: 0.11,
            rolls: true,
            hold: 1.4,
            rest: 2.2
        )

        static let all: [Mood] = [.tumble, .drift, .cascadeRoll]
    }
}
