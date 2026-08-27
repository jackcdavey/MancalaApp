import SwiftUI

/// The five decorative pebbles above the main menu wordmark. At rest they sit
/// in the same orderly row they always have; between rests they roll out into a
/// shape, hold it, and roll home again. Shapes and "moods" (how energetically
/// the trip is made) are drawn from shuffled decks so the loop never repeats
/// itself the same way twice.
///
/// Every few cycles a `Routine` runs instead: a longer scripted set piece. They
/// gather into a wheel and roll clean off one edge of the screen and back on
/// from the other, leapfrog over each other down the row, trade swings like a
/// Newton's cradle, turn as a carousel, spiral into a huddle and burst out
/// again, or rock the row to a standstill.
///
/// Touching the stage shoves them: every pebble takes an impulse away from the
/// finger, falling off with distance, and then rolls back to wherever the idle
/// loop has since put them. Shoves stack on top of the loop rather than
/// interrupting it, so the pebbles stay pushable at any moment.
///
/// The whole thing lives and dies with the menu: the drive loop is a `.task`,
/// so entering a game or opening the challenge list cancels it, and coming back
/// restarts from the resting row.
///
/// Pacing is all in one place: see `Tuning` for the delay before the first
/// move, the gaps between cycles, how fast the travel itself plays, and how
/// often routines interrupt. `Push` holds the touch-response knobs and `Layout`
/// the sizes.
struct MenuPebbleStage: View {
    /// Injected rather than duplicated—`ContentView.stoneColor(for:)` already
    /// branches on the visual theme.
    let color: (Int) -> Color
    let isDarkMode: Bool
    /// Set only by the dev menu's preview screen (see `PebbleDevMenu`): the
    /// stage plays this one item over and over instead of drawing from the
    /// shuffled decks. `nil` for the real menu.
    var preview: AnimationItem? = nil

    @Environment(\.mancalaVisualTheme) private var visualTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Where each pebble is headed, as an offset from the centre of the stage.
    /// Formations and routines both just write into this.
    @State private var pose = Formation.home.positions
    @State private var motion = Motion(animation: Mood.tumble.travel, stagger: Mood.tumble.stagger)
    /// Rigid-body transform of the whole group, used by routines that need true
    /// circular motion—interpolating five positions would cut chords across the
    /// arc, which reads as a wheel deflating rather than turning.
    @State private var spin: Double = 0
    @State private var travelX: CGFloat = 0
    @State private var groupMotion: Animation = .linear(duration: 0.01)
    /// Accumulated spin per pebble, in degrees. Path-dependent, so it can't be
    /// derived from `pose` alone.
    @State private var roll = [Double](repeating: 0, count: Layout.count)
    /// Displacement from the current pose caused by touches, and the spin that
    /// displacement earned. Both ride on top of `pose`/`roll` so a shove never
    /// has to fight the idle loop for the same piece of state.
    @State private var impulse = [CGSize](repeating: .zero, count: Layout.count)
    @State private var impulseRoll = [Double](repeating: 0, count: Layout.count)
    @State private var impulseAnimation: Animation = Push.shove
    /// Zero on impact—a shove hits everything at once—but non-zero on the way
    /// back, so they trickle home instead of marching.
    @State private var impulseStagger: Double = 0
    @State private var lastPushPoint: CGPoint?
    @State private var recoilTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<Layout.count, id: \.self) { index in
                    pebble(index: index)
                }
            }
            // Sized to the stage so the group turns about the stage centre, not
            // about the bounding box of whatever pose it happens to be in.
            .frame(width: proxy.size.width, height: proxy.size.height)
            .rotationEffect(.degrees(spin))
            .offset(x: travelX)
            .animation(groupMotion, value: spin)
            .animation(groupMotion, value: travelX)
            .frame(width: proxy.size.width, height: proxy.size.height)
            // The whole band takes touches, not just the pebbles—chasing a 10pt
            // circle around isn't a game anyone wants to play.
            .contentShape(Rectangle())
            .gesture(pushGesture(in: proxy.size))
        }
        .frame(height: Layout.stageHeight)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .perfProbe("PebbleStage")
        .task(id: loopKey) {
            if let preview {
                await runPreviewLoop(preview)
            } else {
                await runIdleLoop()
            }
        }
    }

    // MARK: Pebble

    private func pebble(index: Int) -> some View {
        let diameter = Layout.diameters[index]
        let position = pose[index]
        let tint = color(index).opacity(isDarkMode ? 0.82 : 0.92)
        let travel = motion.animation.delay(Double(index) * motion.stagger)

        return Circle()
            // Flat stones are matte by design (see `stoneView`); only the glass
            // theme gets the sheen.
            .fill(visualTheme == .flat ? AnyShapeStyle(tint) : AnyShapeStyle(tint.gradient))
            .frame(width: diameter, height: diameter)
            .overlay { flecks(diameter: diameter) }
            .rotationEffect(.degrees(roll[index]))
            .animation(travel, value: roll[index])
            // Both spins have to be applied before any `offset`: `offset` moves
            // pixels but not the layout frame, so a rotation placed after one
            // pivots around where the pebble *would* have been—swinging it
            // across the stage instead of spinning it in place.
            .rotationEffect(.degrees(impulseRoll[index]))
            .animation(shoveAnimation(index: index), value: impulse[index])
            // Outside the rotation: a specular highlight that spun with the
            // body would read as a painted dot rather than a reflection.
            .overlay { specular(diameter: diameter) }
            .shadow(color: .black.opacity(isDarkMode ? 0.32 : 0.15), radius: 2, x: 0, y: 1.5)
            .offset(x: position.x, y: position.y)
            .animation(travel, value: pose)
            // The shove rides outside the idle loop's animation so a punch
            // stays snappy even mid-drift.
            .offset(x: impulse[index].width, y: impulse[index].height)
            .animation(shoveAnimation(index: index), value: impulse[index])
    }

    private func shoveAnimation(index: Int) -> Animation {
        impulseAnimation.delay(Double(index) * impulseStagger)
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

    // MARK: Touch

    /// A zero-distance drag rather than a tap: the pebbles should scatter the
    /// instant a finger lands, not when it lifts. Sweeping the finger keeps
    /// shoving, so a drag ploughs a furrow through them.
    private func pushGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard Tuning.pushEnabled else { return }
                let point = CGPoint(x: value.location.x - size.width / 2,
                                    y: value.location.y - size.height / 2)
                if let last = lastPushPoint, hypot(point.x - last.x, point.y - last.y) < Push.resweep {
                    return
                }
                lastPushPoint = point
                shove(from: point, in: size)
            }
            .onEnded { _ in
                lastPushPoint = nil
            }
    }

    /// Pushes every pebble directly away from `point`, hardest for the ones
    /// nearest it, then schedules the trip home.
    private func shove(from point: CGPoint, in size: CGSize) {
        recoilTask?.cancel()

        let limitX = max(size.width / 2 - Push.margin, 0)
        var nextImpulse = impulse
        var nextRoll = impulseRoll

        for index in 0..<Layout.count {
            let home = pose[index]
            let current = CGPoint(x: home.x + impulse[index].width, y: home.y + impulse[index].height)
            var dx = current.x - point.x
            var dy = current.y - point.y
            var distance = hypot(dx, dy)

            if distance < 0.01 {
                // Dead-centre hit: send it somewhere rather than nowhere.
                dx = index.isMultiple(of: 2) ? 1 : -1
                dy = -0.35
                distance = hypot(dx, dy)
            }

            let strength = Push.strength * CGFloat(exp(-Double(distance) / Double(Push.falloff)))
            let target = CGPoint(
                x: min(max(current.x + dx / distance * strength, -limitX), limitX),
                y: min(max(current.y + dy / distance * strength, -Push.headroom), Push.footroom)
            )

            nextImpulse[index] = CGSize(width: target.x - home.x, height: target.y - home.y)
            let radius = Layout.diameters[index] / 2
            nextRoll[index] += Double((target.x - current.x) / radius) * (180 / .pi) * Tuning.rollFactor
        }

        impulseAnimation = reduceMotion ? Push.calmShove : Push.shove
        impulseStagger = 0
        impulseRoll = nextRoll
        impulse = nextImpulse

        recoilTask = Task { @MainActor in
            guard await pause(Push.hold) else { return }
            impulseAnimation = reduceMotion ? Push.calmSettle : Push.settle
            impulseStagger = reduceMotion ? 0 : Push.returnStagger
            // Unwinding the spin as they come back keeps the roll honest—they
            // rolled out, so they roll back.
            impulseRoll = [Double](repeating: 0, count: Layout.count)
            impulse = [CGSize](repeating: .zero, count: Layout.count)
        }
    }

    // MARK: Drive loop

    /// Restarts the loop when Reduce Motion is toggled, the app leaves the
    /// foreground, the previewed item changes, or the dev menu enables or
    /// disables something; `.task(id:)` cancels the previous run for us.
    private var loopKey: String {
        var key = "\(reduceMotion)-\(scenePhase == .active)-\(preview?.id ?? "idle")"
        if PebbleDevMenu.isEnabled {
            key += "-\(PebbleDevMenu.settings.loopKeyFragment)"
        }
        return key
    }

    /// The plain-cycle shapes, the moods to perform them in, and the set
    /// pieces, each with anything switched off in the dev menu removed. With
    /// the dev menu off these are just the tuning decks.
    private var liveFormations: [Formation] {
        let deck = Tuning.formationDeck.isEmpty ? Formation.roaming : Tuning.formationDeck
        return PebbleDevMenu.enabled(deck)
    }

    private var liveMoods: [Mood] {
        PebbleDevMenu.enabled(Tuning.moodDeck.isEmpty ? Mood.all : Tuning.moodDeck)
    }

    private var liveRoutines: [Routine] {
        PebbleDevMenu.enabled(Tuning.routineDeck)
    }

    private func runIdleLoop() async {
        guard !reduceMotion, scenePhase == .active, Tuning.idleMotionEnabled else {
            restToHome()
            return
        }

        let formationDeck = liveFormations
        let moodDeck = liveMoods
        let routineDeck = liveRoutines
        // A plain cycle needs both a shape to draw and a mood to draw it in.
        let canRunCycles = !formationDeck.isEmpty && !moodDeck.isEmpty
        // Nothing left to play—which only the dev menu can arrange. Returning
        // is safe: the loop restarts the moment anything is switched back on,
        // because that changes `loopKey`.
        guard canRunCycles || !routineDeck.isEmpty else {
            restToHome()
            return
        }

        var shapes: [Formation] = []
        var moods: [Mood] = []
        var routines: [Routine] = []
        var lastShape: Formation?
        // Routines are the rare treat, so a few plain cycles come first.
        var cyclesUntilRoutine = Int.random(in: Tuning.cyclesBeforeFirstRoutine)

        // Let the menu's own fade-in finish before anything moves.
        guard await pause(Tuning.startupDelay) else { return }

        while !Task.isCancelled {
            if (cyclesUntilRoutine <= 0 || !canRunCycles), !routineDeck.isEmpty {
                if routines.isEmpty {
                    routines = routineDeck.shuffled()
                }
                cyclesUntilRoutine = Int.random(in: Tuning.cyclesBetweenRoutines)
                guard await perform(routines.removeLast()) else { return }
                continue
            }
            // Floored rather than decremented freely: with an empty routine
            // deck nothing ever consumes the count.
            cyclesUntilRoutine = max(cyclesUntilRoutine - 1, 0)

            if shapes.isEmpty {
                shapes = formationDeck.shuffled()
                // `removeLast` draws from the end, so a repeat of the shape we
                // just showed is only possible at that one position.
                if shapes.count > 1, shapes.last == lastShape {
                    shapes.swapAt(0, shapes.count - 1)
                }
            }
            if moods.isEmpty {
                moods = moodDeck.shuffled()
            }

            let nextShape = shapes.removeLast()
            lastShape = nextShape

            guard await runCycle(shape: nextShape, mood: moods.removeLast()) else { return }
        }
    }

    /// One out-and-back trip: roll into `shape`, dwell, roll home, dwell.
    /// Returns false if the loop was cancelled part-way.
    private func runCycle(shape: Formation, mood: Mood) async -> Bool {
        let speed = Tuning.clamped(speed: Tuning.travelSpeed)
        let motion = Motion(animation: mood.travel, stagger: mood.stagger).paced(speed: speed)
        // The settle covers the travel itself, so it tracks `travelSpeed`
        // while the dwell either side is tuned independently.
        let travelTime = mood.settle / speed

        move(to: shape.positions, motion: motion, rolling: mood.rolls)
        guard await pause(travelTime + mood.hold * Tuning.holdScale + Tuning.holdBonus) else { return false }

        move(to: Formation.home.positions, motion: motion, rolling: mood.rolls)
        return await pause(travelTime + mood.rest * Tuning.restScale + Tuning.restBonus)
    }

    /// Plays one catalog item on repeat for the dev menu. Deliberately ignores
    /// Reduce Motion and `idleMotionEnabled`: asking to preview an animation is
    /// asking to see it move, and nothing here is decoration the user didn't
    /// go looking for.
    private func runPreviewLoop(_ item: AnimationItem) async {
        guard scenePhase == .active else {
            restToHome()
            return
        }

        guard await pause(Tuning.previewStartupDelay) else { return }

        while !Task.isCancelled {
            switch item.payload {
            case let .formation(formation):
                guard await runCycle(shape: formation, mood: AnimationItem.previewMood) else { return }
            case let .mood(mood):
                guard await runCycle(shape: AnimationItem.previewShape, mood: mood) else { return }
            case let .routine(routine):
                guard await perform(routine) else { return }
            }
        }
    }

    /// Plays a scripted set piece step by step. Returns false if the loop was
    /// cancelled part-way, in which case the view is going away anyway.
    private func perform(_ routine: Routine) async -> Bool {
        let speed = Tuning.clamped(speed: Tuning.routineSpeed)

        for step in routine.steps {
            if let points = step.points {
                move(to: points, motion: step.motion.paced(speed: speed), rolling: step.rolls)
            }
            if step.spin != nil || step.travel != nil {
                groupMotion = (step.groupAnimation ?? step.motion.animation).speed(speed)
                if let spinTo = step.spin { spin = spinTo }
                if let travelTo = step.travel { travelX = travelTo }
            }
            // A step's hold covers its own animation, so it moves with the
            // speed rather than being tuned separately.
            guard await pause(step.hold / speed) else { return false }
        }

        // Every routine is written to land back at an upright, untranslated
        // group, so clearing the transform here is a no-op on screen.
        spin = 0
        travelX = 0
        return await pause(Tuning.routineRestBonus)
    }

    private func move(to points: [CGPoint], motion nextMotion: Motion, rolling: Bool) {
        if rolling {
            for index in 0..<Layout.count {
                let distance = points[index].x - pose[index].x
                let radius = Layout.diameters[index] / 2
                roll[index] += Double(distance / radius) * (180 / .pi) * Tuning.rollFactor
            }
        }
        // Set the motion first: the pebbles read it when building the animation
        // for the pose change below.
        motion = nextMotion
        pose = points
    }

    private func restToHome() {
        spin = 0
        travelX = 0
        pose = Formation.home.positions
    }

    /// Returns false when the loop was cancelled mid-sleep. Tuned-down waits
    /// can come out negative, which is just "don't wait"—but still a
    /// cancellation point, so the loop can't spin forever on a dead view.
    private func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(max(seconds, 0)))
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
    }
}

// MARK: - Tuning

extension MenuPebbleStage {
    /// Every knob that governs *when* and *how briskly* the idle loop moves.
    ///
    /// These are `var`s rather than `let`s so they can be nudged from a preview
    /// or a debug build without threading state through the view; nothing in
    /// the app writes to them at runtime, and they're read on the main actor
    /// like the rest of the view.
    ///
    /// The scale factors all mean the same thing: `1.0` is the hand-tuned
    /// original, larger is more of whatever the name says. Nothing here changes
    /// the *shapes*—those live in `Formation` and `Routine`.
    fileprivate enum Tuning {
        // MARK: Startup

        /// Dead time after the menu appears before the pebbles first stir.
        /// Long enough by default for the menu's own fade-in to finish.
        static var startupDelay: Double = 0.5

        /// The same for the dev menu's preview stage, where the wait is only
        /// long enough to see the resting row before it breaks apart.
        static var previewStartupDelay: Double = 0.35

        /// Master switch for the idle loop. Off leaves the pebbles in the
        /// resting row—still pushable, just never self-propelled.
        static var idleMotionEnabled = true

        // MARK: Cycle pacing

        /// Speed multiplier on a formation's travel animation. Above `1.0` the
        /// pebbles hurry; the waits that cover the travel shrink to match, so
        /// this doesn't leave dead air behind.
        static var travelSpeed: Double = 1.0

        /// Dwell once a formation has landed, before they head home.
        /// The scale multiplies the mood's own hold; the bonus is added on top,
        /// so a mood's relative laziness survives either adjustment.
        static var holdScale: Double = 1.0
        static var holdBonus: Double = 0

        /// Dwell back at the resting row before the next cycle starts—the gap
        /// between one animation and the next.
        static var restScale: Double = 1.0
        static var restBonus: Double = 0

        /// Multiplier on the per-pebble departure delay that breaks the row
        /// apart. `0` sends them as one block.
        static var staggerScale: Double = 1.0

        /// Full physical rolling (`1.0`) spins fast enough to blur on long
        /// hops; the default trims it back to something that reads as a roll.
        static var rollFactor: Double = 0.7

        /// The shapes a plain cycle may draw from, and the moods it performs
        /// them in. Trim either to bias the loop toward particular ones; an
        /// empty deck falls back to the full set.
        static var formationDeck: [Formation] = Formation.roaming
        static var moodDeck: [Mood] = Mood.all

        // MARK: Routines

        /// Plain cycles to get through before the first routine, and between
        /// routines thereafter. A fresh count is rolled from the range each
        /// time, so the set pieces never land on a metronome.
        static var cyclesBeforeFirstRoutine: ClosedRange<Int> = 2...4
        static var cyclesBetweenRoutines: ClosedRange<Int> = 2...5

        /// Speed multiplier on a routine's scripted steps. Their holds are
        /// scaled to match, since a step's hold covers its own animation.
        static var routineSpeed: Double = 1.0

        /// Extra breath after a routine finishes, on top of its closing step.
        static var routineRestBonus: Double = 0

        /// Which set pieces are in the deck. Empty disables routines entirely
        /// and the loop runs nothing but plain cycles.
        static var routineDeck: [Routine] = Routine.all

        // MARK: Touch

        /// Whether touching the stage shoves the pebbles at all. The force,
        /// falloff and recoil timings live in `Push`.
        static var pushEnabled = true

        // MARK: Guards

        /// Speeds are divided into the loop's waits, so a zero or negative one
        /// would stall it outright rather than slowing it down. Every read of a
        /// speed goes through here.
        static func clamped(speed: Double) -> Double {
            max(speed, 0.05)
        }
    }
}

// MARK: - Routines

extension MenuPebbleStage {
    /// How a pose change is animated. Formations get theirs from a `Mood`;
    /// routines carry one per step.
    fileprivate struct Motion {
        let animation: Animation
        let stagger: Double

        /// Applies the tuning knobs to an authored motion. The stagger is
        /// divided by the speed as well as scaled, so a hurried cycle breaks
        /// the row apart in the same proportion as a lazy one instead of
        /// spending most of its travel time waiting to set off.
        func paced(speed: Double) -> Motion {
            guard speed > 0 else { return self }
            return Motion(animation: animation.speed(speed),
                          stagger: stagger * Tuning.staggerScale / speed)
        }
    }

    /// One beat of a set piece. `points` moves the pebbles individually;
    /// `spin`/`travel` move the whole group as a rigid body. A step may do
    /// either or both.
    fileprivate struct Step {
        var points: [CGPoint]?
        var spin: Double?
        var travel: CGFloat?
        var motion = Motion(animation: .easeInOut(duration: 0.5), stagger: 0)
        /// Overrides `motion.animation` for the group transform, which usually
        /// wants a different curve than the pebbles' own scatter.
        var groupAnimation: Animation?
        var rolls = false
        /// Seconds to wait before the next step begins.
        var hold: Double
    }

    /// The occasional showpiece: longer, scripted, and rarer than a formation
    /// cycle. Each one must finish with the group upright and untranslated.
    ///
    /// Visible outside this file only so the dev menu can list one by name;
    /// the script itself stays private to the stage.
    struct Routine {
        /// Identify the routine in the dev menu. Never shown to players.
        let name: String
        let detail: String
        fileprivate let steps: [Step]

        static let all: [Routine] = [.wheel, .cradle, .leapfrog, .carousel, .vortex, .seesaw]

        /// Radius of the wheel, and the roll that carries it a whole number of
        /// turns—landing on a multiple of 360° is what lets the group snap back
        /// to zero rotation without anything visibly moving.
        private static let wheelRadius: CGFloat = 20
        private static let wheelTurns: CGFloat = 2
        private static var wheelTravel: CGFloat { 2 * .pi * wheelRadius * wheelTurns }
        private static var wheelSpin: Double { Double(wheelTurns) * 360 }

        /// Four pebbles on the rim, the fat middle one as the hub.
        private static var wheelPose: [CGPoint] {
            let r = wheelRadius * CGFloat(cos(Double.pi / 4))
            return [
                CGPoint(x: -r, y: r),
                CGPoint(x: -r, y: -r),
                .zero,
                CGPoint(x: r, y: r),
                CGPoint(x: r, y: -r)
            ]
        }

        /// Gather into a wheel, roll off the right edge, come back on from the
        /// left, and fall apart into the row again.
        static let wheel = Routine(
            name: "Wheel",
            detail: "Gathers into a wheel, rolls off the right edge, and comes back on from the left.",
            steps: [
            Step(points: wheelPose,
                 motion: Motion(animation: .spring(response: 0.55, dampingFraction: 0.80), stagger: 0.045),
                 rolls: true,
                 hold: 0.9),
            Step(spin: wheelSpin,
                 travel: wheelTravel,
                 groupAnimation: .easeIn(duration: 1.15),
                 hold: 1.2),
            // Re-enter from the far side. Winding the rotation back the same
            // amount means the return leg is another honest right-hand roll.
            Step(spin: -wheelSpin,
                 travel: -wheelTravel,
                 groupAnimation: .linear(duration: 0.001),
                 hold: 0.18),
            Step(spin: 0,
                 travel: 0,
                 groupAnimation: .easeOut(duration: 1.2),
                 hold: 1.25),
            Step(points: Formation.home.positions,
                 motion: Motion(animation: .spring(response: 0.62, dampingFraction: 0.75), stagger: 0.05),
                 rolls: true,
                 hold: 2.2)
        ])

        /// Newton's cradle: the outer pebbles trade a swing through the middle.
        static let cradle = Routine(
            name: "Cradle",
            detail: "Newton's cradle: the outer pebbles trade a swing through the middle.",
            steps: [
            Step(points: line([-64, -32, 0, 32, 64]),
                 motion: Motion(animation: .spring(response: 0.50, dampingFraction: 0.85), stagger: 0.05),
                 rolls: true,
                 hold: 0.7),
            Step(points: line([-98, -32, 0, 32, 64]),
                 motion: Motion(animation: .easeOut(duration: 0.42), stagger: 0),
                 rolls: true,
                 hold: 0.46),
            Step(points: line([-66, -32, 0, 32, 64]),
                 motion: Motion(animation: .easeIn(duration: 0.24), stagger: 0),
                 rolls: true,
                 hold: 0.26),
            Step(points: line([-66, -32, 0, 32, 98]),
                 motion: Motion(animation: .easeOut(duration: 0.30), stagger: 0),
                 rolls: true,
                 hold: 0.34),
            Step(points: line([-66, -32, 0, 32, 66]),
                 motion: Motion(animation: .easeIn(duration: 0.26), stagger: 0),
                 rolls: true,
                 hold: 0.28),
            Step(points: line([-98, -32, 0, 32, 66]),
                 motion: Motion(animation: .easeOut(duration: 0.34), stagger: 0),
                 rolls: true,
                 hold: 0.42),
            Step(points: Formation.home.positions,
                 motion: Motion(animation: .spring(response: 0.60, dampingFraction: 0.78), stagger: 0.05),
                 rolls: true,
                 hold: 2.2)
        ])

        /// Each pebble in turn arcs over the top of the row to the far end while
        /// everyone else slides down a place. Five hops puts every pebble back
        /// where it started, so the routine closes itself.
        static let leapfrog: Routine = {
            let slots = Formation.home.positions
            let apex = CGPoint(x: 0, y: -24)
            var slotOf = Array(0..<Layout.count)

            var steps = [
                Step(points: slots,
                     motion: Motion(animation: .spring(response: 0.50, dampingFraction: 0.85), stagger: 0.04),
                     rolls: true,
                     hold: 0.55)
            ]

            for flyer in 0..<Layout.count {
                var rising = [CGPoint](repeating: .zero, count: Layout.count)
                for index in 0..<Layout.count where index != flyer {
                    // The flyer is always the one currently in slot 0, so no one
                    // else is ever asked to step off the left end.
                    slotOf[index] = max(slotOf[index] - 1, 0)
                    rising[index] = slots[slotOf[index]]
                }
                rising[flyer] = apex
                steps.append(Step(points: rising,
                                  motion: Motion(animation: .easeOut(duration: 0.26), stagger: 0),
                                  rolls: true,
                                  hold: 0.26))

                slotOf[flyer] = Layout.count - 1
                var landing = rising
                landing[flyer] = slots[slotOf[flyer]]
                steps.append(Step(points: landing,
                                  motion: Motion(animation: .easeIn(duration: 0.24), stagger: 0),
                                  rolls: true,
                                  hold: 0.24))
            }

            steps.append(Step(points: slots,
                              motion: Motion(animation: .spring(response: 0.55, dampingFraction: 0.80), stagger: 0.04),
                              rolls: true,
                              hold: 2.2))
            return Routine(
                name: "Leapfrog",
                detail: "Each pebble in turn arcs over the row to the far end.",
                steps: steps
            )
        }()

        /// A fairground turn: the ring breathes wider and back while the whole
        /// group rotates two full times.
        static let carousel = Routine(
            name: "Carousel",
            detail: "A ring that breathes wider and back through two full turns.",
            steps: [
            Step(points: ring(13),
                 motion: Motion(animation: .spring(response: 0.50, dampingFraction: 0.85), stagger: 0.04),
                 rolls: true,
                 hold: 0.7),
            Step(points: ring(spinningRadius),
                 spin: 360,
                 motion: Motion(animation: .easeInOut(duration: 1.0), stagger: 0),
                 groupAnimation: .easeInOut(duration: 1.0),
                 hold: 1.0),
            Step(points: ring(13),
                 spin: 720,
                 motion: Motion(animation: .easeInOut(duration: 1.0), stagger: 0),
                 groupAnimation: .easeInOut(duration: 1.0),
                 hold: 1.05),
            Step(points: Formation.home.positions,
                 spin: 0,
                 motion: Motion(animation: .spring(response: 0.60, dampingFraction: 0.78), stagger: 0.05),
                 groupAnimation: .linear(duration: 0.001),
                 rolls: true,
                 hold: 2.2)
        ])

        /// Spiral inward to a huddle, hang there a beat, then burst back out.
        static let vortex = Routine(
            name: "Vortex",
            detail: "Spirals inward to a huddle, hangs a beat, then bursts back out.",
            steps: [
            Step(points: ring(spinningRadius),
                 motion: Motion(animation: .spring(response: 0.50, dampingFraction: 0.80), stagger: 0.05),
                 rolls: true,
                 hold: 0.5),
            Step(points: ring(6),
                 spin: 720,
                 motion: Motion(animation: .easeIn(duration: 0.85), stagger: 0),
                 groupAnimation: .easeIn(duration: 0.85),
                 hold: 0.9),
            // A beat of stillness makes the burst land harder.
            Step(hold: 0.3),
            Step(points: ring(spinningRadius),
                 spin: 1080,
                 motion: Motion(animation: .easeOut(duration: 0.5), stagger: 0),
                 groupAnimation: .easeOut(duration: 0.5),
                 hold: 0.55),
            Step(points: Formation.home.positions,
                 spin: 0,
                 motion: Motion(animation: .spring(response: 0.62, dampingFraction: 0.72), stagger: 0.05),
                 groupAnimation: .linear(duration: 0.001),
                 rolls: true,
                 hold: 2.2)
        ])

        /// The row spreads into a beam and rocks itself to a standstill.
        static let seesaw = Routine(
            name: "Seesaw",
            detail: "The row spreads into a beam and rocks itself to a standstill.",
            steps: [
            Step(points: line([-62, -31, 0, 31, 62]),
                 motion: Motion(animation: .spring(response: 0.50, dampingFraction: 0.85), stagger: 0.04),
                 rolls: true,
                 hold: 0.45),
            Step(spin: 17, groupAnimation: .spring(response: 0.50, dampingFraction: 0.60), hold: 0.6),
            Step(spin: -17, groupAnimation: .spring(response: 0.55, dampingFraction: 0.55), hold: 0.7),
            Step(spin: 11, groupAnimation: .spring(response: 0.50, dampingFraction: 0.55), hold: 0.55),
            Step(spin: 0, groupAnimation: .spring(response: 0.70, dampingFraction: 0.50), hold: 0.7),
            Step(points: Formation.home.positions,
                 motion: Motion(animation: .spring(response: 0.60, dampingFraction: 0.80), stagger: 0.045),
                 rolls: true,
                 hold: 2.2)
        ])

        /// Widest a ring may be while the group is rotating. Bigger reads better
        /// but a turning circle puts a pebble at the full radius straight down,
        /// and below this the wordmark starts.
        private static let spinningRadius: CGFloat = 20

        private static func line(_ xs: [CGFloat]) -> [CGPoint] {
            xs.map { CGPoint(x: $0, y: 0) }
        }

        /// A true circle, not an ellipse: a flattened ring looks like a
        /// wobbling blob once the group starts turning.
        private static func ring(_ radius: CGFloat) -> [CGPoint] {
            [-90.0, -18, 54, 126, 198].map { angle in
                let radians = angle * .pi / 180
                return CGPoint(x: radius * CGFloat(cos(radians)), y: radius * CGFloat(sin(radians)))
            }
        }
    }
}

// MARK: - Touch response

extension MenuPebbleStage {
    fileprivate enum Push {
        /// Displacement, in points, for a pebble the finger lands right on.
        static let strength: CGFloat = 56
        /// e-folding distance of the shove. Deliberately long: with a short
        /// falloff the pebble nearest the finger out-runs the one beyond it and
        /// they collide, so the row bunches instead of fanning out.
        static let falloff: CGFloat = 130
        /// Keeps shoved pebbles inside the stage horizontally.
        static let margin: CGFloat = 6
        /// Vertical limits are lopsided because the space is: the menu leaves a
        /// wide gap above the pebbles and almost none between them and the
        /// wordmark, so they can fly high but barely sink.
        static let headroom: CGFloat = 32
        static let footroom: CGFloat = 10
        /// How far a finger must sweep before it counts as a fresh shove.
        static let resweep: CGFloat = 26
        /// Time the pebbles stay scattered before heading home—long enough to
        /// see where they landed.
        static let hold = 0.34
        /// Per-pebble delay on the trip home only.
        static let returnStagger = 0.05

        static let shove = Animation.spring(response: 0.26, dampingFraction: 0.58)
        /// Deliberately unhurried: they should look like they're rolling back,
        /// not snapping back.
        static let settle = Animation.spring(response: 1.05, dampingFraction: 0.72)
        /// Reduce Motion still gets to push pebbles—direct manipulation is the
        /// one kind of movement it isn't asking us to stop—just without the
        /// overshoot.
        static let calmShove = Animation.easeOut(duration: 0.3)
        static let calmSettle = Animation.easeInOut(duration: 0.9)
    }
}

// MARK: - Formations

extension MenuPebbleStage {
    /// Pebble positions as offsets from the centre of the stage. Every case
    /// stays inside roughly ±61pt horizontally and ±25pt vertically (including
    /// the pebble radius), so nothing escapes the stage frame.
    enum Formation: CaseIterable, Equatable {
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

        /// Names the shape in the dev menu. Never shown to players.
        var name: String {
            switch self {
            case .home: "Row"
            case .ring: "Ring"
            case .arc: "Arc"
            case .wave: "Wave"
            case .cascade: "Cascade"
            case .pyramid: "Pyramid"
            case .orbit: "Orbit"
            case .huddle: "Huddle"
            }
        }

        var detail: String {
            switch self {
            case .home: "The resting row the loop always comes back to."
            case .ring: "A wide ellipse, the full width of the stage."
            case .arc: "A shallow smile with both ends lifted."
            case .wave: "Alternating high and low, a zigzag across the row."
            case .cascade: "A diagonal staircase, low on the left to high on the right."
            case .pyramid: "Three low, two perched in the gaps between them."
            case .orbit: "Four around the fat centre pebble, which stays put."
            case .huddle: "All five bunched together at the centre."
            }
        }

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
    struct Mood: Equatable {
        /// Identify the mood in the dev menu. Never shown to players.
        let name: String
        let detail: String
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
            name: "Tumble",
            detail: "Springy and quick, rolling the whole way.",
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
            name: "Drift",
            detail: "Slow and weightless, with no roll at all.",
            travel: .easeInOut(duration: 1.9),
            settle: 2.4,
            stagger: 0.12,
            rolls: false,
            hold: 2.0,
            rest: 3.0
        )

        static let cascadeRoll = Mood(
            name: "Cascade Roll",
            detail: "A firm spring with a long per-pebble stagger, so the row peels apart.",
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

// MARK: - Animation catalog

extension MenuPebbleStage {
    /// One reviewable animation, as listed by the dev menu (`PebbleDevMenu`).
    ///
    /// The catalog is the only thing outside this file that knows the stage's
    /// vocabulary, and it exists purely so a shape, a mood or a set piece can
    /// be named, previewed on its own, and taken out of the deck while it's
    /// being worked on. Nothing the player sees depends on it.
    struct AnimationItem: Identifiable, Equatable {
        enum Kind: String, CaseIterable {
            case formation
            case mood
            case routine

            var title: String {
                switch self {
                case .formation: "Shapes"
                case .mood: "Moods"
                case .routine: "Routines"
                }
            }

            var footer: String {
                switch self {
                case .formation: "Poses a plain cycle rolls out into before rolling home."
                case .mood: "How briskly a plain cycle is performed."
                case .routine: "Scripted set pieces that interrupt every few cycles."
                }
            }
        }

        enum Payload {
            case formation(Formation)
            case mood(Mood)
            case routine(Routine)
        }

        let id: String
        let kind: Kind
        let title: String
        let detail: String
        let payload: Payload

        /// A shape is previewed in one fixed mood and a mood over one fixed
        /// shape, so that two of either can be told apart by the one thing
        /// that differs between them.
        static let previewMood = Mood.tumble
        static let previewShape = Formation.wave

        /// What the preview is holding constant, spelled out on screen so a
        /// mood's stagger isn't mistaken for a property of the shape.
        var previewNote: String {
            switch kind {
            case .formation: "Shown in the \(Self.previewMood.name) mood, on a loop."
            case .mood: "Shown rolling out to the \(Self.previewShape.name) shape, on a loop."
            case .routine: "Played on a loop, with its own closing rest between runs."
            }
        }

        static func == (lhs: AnimationItem, rhs: AnimationItem) -> Bool {
            lhs.id == rhs.id
        }

        init(_ formation: Formation) {
            id = formation.animationID
            kind = .formation
            title = formation.name
            detail = formation.detail
            payload = .formation(formation)
        }

        init(_ mood: Mood) {
            id = mood.animationID
            kind = .mood
            title = mood.name
            detail = mood.detail
            payload = .mood(mood)
        }

        init(_ routine: Routine) {
            id = routine.animationID
            kind = .routine
            title = routine.name
            detail = routine.detail
            payload = .routine(routine)
        }
    }

    /// Everything the idle loop can play, in the order the dev menu lists it.
    /// `home` is left out: it's the rest pose every cycle returns to rather
    /// than an animation in its own right.
    static let animationCatalog: [AnimationItem] =
        Formation.roaming.map { AnimationItem($0) }
        + Mood.all.map { AnimationItem($0) }
        + Routine.all.map { AnimationItem($0) }

    static func animationItems(of kind: AnimationItem.Kind) -> [AnimationItem] {
        animationCatalog.filter { $0.kind == kind }
    }
}

// MARK: - Identity

/// Stable keys for the dev menu's on/off switches, which outlive a launch in
/// `UserDefaults`. Built from the names rather than the declaration order so
/// reordering a deck doesn't silently re-point somebody's switches.
extension MenuPebbleStage.Formation {
    var animationID: String { "formation.\(name)" }
}

extension MenuPebbleStage.Mood {
    var animationID: String { "mood.\(name)" }
}

extension MenuPebbleStage.Routine {
    var animationID: String { "routine.\(name)" }
}
