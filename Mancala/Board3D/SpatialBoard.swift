#if os(visionOS)
import RealityKit
import SwiftUI
import simd

/// An angle folded into (-π, π], so headings can't wind up indefinitely and an
/// accumulating swing reads each step as the short way round.
func normalizedAngle(_ angle: Float) -> Float {
    var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if value > .pi {
        value -= 2 * .pi
    } else if value <= -.pi {
        value += 2 * .pi
    }
    return value
}

/// Shared bridge between the main window (game logic, chrome) and the board
/// volume. Owned by the app so both scenes see the same `BoardScene`;
/// `ContentView` pushes game state in and receives pit taps.
@Observable
@MainActor
final class SpatialBoardModel {
    static let windowID = "SpatialBoard"

    /// Win/lose summary mirrored out of the window's end-game popup. While the
    /// board is out in the room the popup would be stranded on a window the
    /// player isn't looking at, so the volume floats this above the board
    /// instead and the window hides its own copy.
    struct EndGameBanner: Equatable {
        var title: String
        var subtitle: String
        var symbolName: String
        var symbolColor: Color
        var primaryTitle: String
        /// Present only for challenges, which offer a way back to the list.
        var secondaryTitle: String?
    }

    /// Which of the banner's buttons the player pressed.
    enum EndGameAction {
        case primary
        case secondary
    }

    /// The board volume's physical size, in meters. Declared here so the
    /// scene's `defaultSize` and the resize limits its content imposes are
    /// written once and can't drift apart. The range keeps the board between
    /// roughly a chessboard and a coffee table.
    ///
    /// The footprint is square rather than board-shaped because the board turns
    /// inside it: an oblong volume would force the board to shrink every time
    /// it was rotated off-square, to keep its ends from poking through the
    /// walls. A square one lets it face any direction at full size.
    enum VolumeSize {
        static let resting = SIMD3<Float>(1, 0.45, 1)
        static let minimum = resting * 0.55
        static let maximum = resting * 1.7
    }

    let scene = BoardScene()

    /// True while the board volume is open; the main window swaps its board
    /// for a placeholder and routes stone animations to `scene`.
    var isOpen = false

    /// Non-nil only while the game is finished *and* the board is out in the
    /// room; `ContentView` owns the decision and pushes the result here.
    var endGame: EndGameBanner?

    var onEndGameAction: ((EndGameAction) -> Void)?

    /// The board's heading in its volume, in radians about the vertical axis.
    /// Lives on the model rather than in the volume's view so the board keeps
    /// the heading it was left at if the volume is closed and reopened.
    var boardYaw: Float = 0

    /// How big the player has chosen to make the board, as a fraction of the
    /// largest size that fits the volume. Volumes draw their resize handles on
    /// the baseplate, which this board hides, so size is the app's to offer —
    /// see `SpatialBoardView.scaleGesture`.
    ///
    /// The default leaves headroom in both directions: room to grow to a board
    /// that fills the volume, and to shrink to something that fits a side
    /// table.
    var boardScale: Float = BoardScaleRange.default

    enum BoardScaleRange {
        static let minimum: Float = 0.35
        static let maximum: Float = 1
        static let `default`: Float = 0.85
    }

    /// Turn the board by `angle` radians about the vertical axis.
    func rotateBoard(by angle: Float) {
        boardYaw = normalizedAngle(boardYaw + angle)
    }

    /// Set the board's size, held inside the range the volume can show.
    func setBoardScale(_ scale: Float) {
        boardScale = min(max(scale, BoardScaleRange.minimum), BoardScaleRange.maximum)
    }

    func scaleBoard(by factor: Float) {
        setBoardScale(boardScale * factor)
    }

}

/// Equatable snapshot of everything the spatial board mirrors, so
/// `ContentView` can sync the scene from a single `onChange`.
struct SpatialBoardSyncState: Equatable {
    var pits: [Int]
    var playable: Set<Int>
    var hinted: Int?
    var currentStore: Int?
    var showLabels: Bool
    var dark: Bool
    var material: BoardMaterialStyle
}

/// Volumetric-window content: the board resting on the volume's floor, sized
/// to fill it. The system handle under the volume moves it anywhere in the room
/// — including vertically — and snaps it onto real surfaces; pinching the wood
/// and twisting turns it on the spot. Pits play by reaching out and touching
/// them or by gaze + pinch.
struct SpatialBoardView: View {
    let model: SpatialBoardModel

    /// Carries the board so it can be seated on the volume's floor; the
    /// scene root itself keeps the board origin at the slab's top face.
    @State private var boardHolder = Entity()
    /// Sits between the holder and the board and carries nothing but the
    /// heading, so turning the board never fights the fit-and-seat pass that
    /// owns the holder's position and scale.
    @State private var boardRotator = Entity()
    /// Billboarded host for the end-game banner, parented to the board so it
    /// follows wherever the volume is moved or snapped.
    @State private var bannerAnchor = Entity()

    /// True while a twist is in progress, so the heading the gesture is already
    /// drawing isn't animated to a second time when it commits.
    @State private var isRotating = false
    /// The board's size when the current pinch began; magnification arrives
    /// relative to the start of the gesture, not the last frame.
    @State private var scaleAtGestureStart: Float?
    /// Set when a resize claims the hand a twist was already following, and
    /// held until that twist ends.
    @State private var isRotationSuppressed = false
    /// Bookkeeping for the turn in progress; reset when the hand lets go.
    @State private var turn = TurnState()

    /// A turn can be led two ways, and this tracks the handover between them.
    /// Swinging the hand around the board is measured from where the hand is,
    /// which accumulates without limit; twisting in place is measured from how
    /// the hand is held, which runs out at the end of the wrist's range.
    private struct TurnState {
        /// The hand's bearing around the board last frame, for accumulating a
        /// swing that may wrap past a half turn.
        var lastBearing: Float?
        /// Total swing so far, unwrapped.
        var swing: Float = 0
        /// Set once a swing takes the lead, holding whatever the twist had
        /// already turned so the handover doesn't jump.
        var swingOffset: Float?
    }

    /// Resting height of the banner's center above the board's top face, in
    /// meters — clear of the wood, so the finished board stays visible beneath
    /// it.
    private static let bannerHeight: Float = 0.18
    /// Roughly half the rendered panel (attachments render at ~1360 points per
    /// meter), used to keep it inside the volume's bounds — volumes clip
    /// anything that pokes out.
    private static let bannerHalfHeight: Float = 0.13

    /// Clearance left between the board's footprint and the volume's walls, so
    /// the board never appears to graze the edge of its own bounds.
    private static let fitMargin: Float = 0.94
    /// Safety rails on the fitted scale. The volume's own resize limits (see
    /// `MancalaApp`) keep it well inside this range; these only matter if the
    /// system hands over bounds outside what those limits allow.
    private static let minScale: Float = 0.4
    private static let maxScale: Float = 2.5

    /// Board degrees per degree of wrist. A wrist has maybe 60° of comfortable
    /// travel, so turning the board a quarter turn one-to-one would take
    /// several goes; this puts a quarter turn inside a single twist.
    private static let twistGain: Float = 2.5
    /// How far the hand must travel around the board before a swing takes over
    /// from a twist — enough that the wrist's own wobble doesn't trip it.
    private static let swingThreshold: Float = 0.07
    /// Nearer than this to the axis of rotation, the hand's bearing around the
    /// board is too unstable to steer by.
    private static let minimumSwingRadius: Float = 0.05

    /// Points per meter, resolved for this scene, so the volume's resize
    /// limits can be written in real-world units like its default size is.
    @PhysicalMetric(from: .meters) private var pointsPerMeter = 1.0

    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in
                let sceneRoot = await model.scene.buildRoot()
                boardRotator.addChild(sceneRoot)
                boardRotator.orientation = Self.rotation(yaw: model.boardYaw)
                boardHolder.addChild(boardRotator)
                content.add(boardHolder)

                // Faces the viewer from wherever they stand, the same way the
                // per-well count labels do. It sits beside the board rather
                // than inside it so that shrinking the board doesn't shrink the
                // result text along with it.
                bannerAnchor.components.set(BillboardComponent())
                bannerAnchor.components.set(ViewAttachmentComponent(rootView: banner))
                bannerAnchor.isEnabled = false
                content.add(bannerAnchor)

                seatBoard(content: content, proxy: proxy)
            } update: { content in
                bannerAnchor.isEnabled = model.endGame != nil
                seatBoard(content: content, proxy: proxy)
            }
            .gesture(rotateGesture)
            // Simultaneous, not exclusive: the twist gesture has already
            // claimed the first hand by the time the second one pinches, so an
            // exclusive resize would never get to start.
            .simultaneousGesture(scaleGesture)
            .gesture(pitTapGesture)
            .gesture(pitTouchGesture)
        }
        .onChange(of: model.boardYaw) { _, yaw in
            // Fires for the rotate buttons in the main window, and once more
            // when a twist commits — where the board is already at that
            // heading, so it lands rather than animating to where it is.
            applyYaw(yaw, animated: !isRotating)
            isRotating = false
        }
        // The system floor plate that fades in whenever you look down toward
        // the volume's base. It reads as a slab of glass lying under the board
        // — and since the volume is square while the board isn't, it sticks out
        // past the wood on every side. The board is its own anchor.
        .volumeBaseplateVisibility(.hidden)
        // Volumes take their resize limits from their content, so this is what
        // bounds how far the board can be scaled up or down.
        .frame(
            minWidth: points(SpatialBoardModel.VolumeSize.minimum.x),
            idealWidth: points(SpatialBoardModel.VolumeSize.resting.x),
            maxWidth: points(SpatialBoardModel.VolumeSize.maximum.x),
            minHeight: points(SpatialBoardModel.VolumeSize.minimum.y),
            idealHeight: points(SpatialBoardModel.VolumeSize.resting.y),
            maxHeight: points(SpatialBoardModel.VolumeSize.maximum.y)
        )
        .frame(
            minDepth: points(SpatialBoardModel.VolumeSize.minimum.z),
            idealDepth: points(SpatialBoardModel.VolumeSize.resting.z),
            maxDepth: points(SpatialBoardModel.VolumeSize.maximum.z)
        )
        .onAppear { model.isOpen = true }
        .onDisappear {
            model.isOpen = false
            model.endGame = nil
        }
    }

    /// Meters as SwiftUI points, for the frame limits above.
    private func points(_ meters: Float) -> CGFloat {
        CGFloat(meters) * pointsPerMeter
    }

    /// The banner's content, re-evaluated by SwiftUI as `model.endGame`
    /// changes; the attachment hosts it as a live view, so no entity rebuild
    /// is needed when the result text changes.
    private var banner: some View {
        SpatialEndGameBanner(model: model)
    }

    /// Size the board to the volume and rest the slab's underside on the
    /// volume's floor, so the board sits on the baseplate and on whatever
    /// surface the volume snaps to.
    ///
    /// The volume is resizable, and its content keeps its physical size unless
    /// something scales it — so without this the board simply gets sliced off
    /// at the walls when the volume shrinks, and rattles around inside it when
    /// it grows. One uniform scale for all three axes keeps the board square
    /// with itself no matter what proportions the bounds arrive in.
    private func seatBoard(content: RealityViewContent, proxy: GeometryProxy3D) {
        let bounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
        let extents = bounds.extents

        // Fit the widest, deepest, tallest thing the scene draws — the slab
        // plus the count labels overhanging its ends, not the slab alone. The
        // footprint used is the circle the board sweeps as it turns, not its
        // rectangle, so the fitted size doesn't depend on the heading: the
        // board stays exactly as big when spun as it was square-on, the way a
        // real board would.
        let sweep = BoardLayout3D.contentSweepRadius
        let fit = min(
            extents.x / (sweep * 2),
            extents.z / (sweep * 2),
            extents.y / BoardLayout3D.contentHeight
        ) * Self.fitMargin
        // The fit is the largest the board may be; the player's chosen size is
        // a fraction of it, so the board can never outgrow its volume however
        // far they pinch.
        let scale = min(max(fit, Self.minScale), Self.maxScale) * model.boardScale

        boardHolder.scale = SIMD3(repeating: scale)
        boardHolder.position = SIMD3(0, bounds.min.y + BoardLayout3D.thickness * scale, 0)

        // The banner keeps its own size, so its clearance is in meters, not
        // board units. Clamped against the volume's ceiling so a shallow volume
        // lowers it toward the board rather than clipping its top off.
        let boardTop = boardHolder.position.y
        let headroom = bounds.max.y - boardTop
        let y = min(Self.bannerHeight, max(0.05, headroom - Self.bannerHalfHeight))
        bannerAnchor.position = SIMD3(0, boardTop + y, 0)
    }

    // MARK: - Heading

    private static func rotation(yaw: Float) -> simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
    }

    /// How far the hand has twisted about the vertical axis since the pinch
    /// began. Measured from the rotation between the two poses rather than from
    /// each pose's own yaw: a hand is held at some arbitrary angle, and only the
    /// change between the two is the twist the player means. Taken from the
    /// quaternion directly rather than from `axis`, which is undefined at the
    /// zero rotation every gesture starts at.
    private static func yawDelta(from start: Rotation3D, to current: Rotation3D) -> Float {
        let relative = current.quaternion * start.quaternion.inverse
        return Float(2 * atan2(relative.imag.y, relative.real))
    }

    private func applyYaw(_ yaw: Float, animated: Bool) {
        let target = Self.rotation(yaw: yaw)
        guard animated else {
            boardRotator.orientation = target
            return
        }
        boardRotator.move(
            to: Transform(scale: .one, rotation: target, translation: .zero),
            relativeTo: boardHolder,
            duration: 0.35,
            timingFunction: .easeInOut
        )
    }

    /// Pinch the bare wood with one hand to turn the board on the spot — the way
    /// you'd nudge a real board around to face the other player, or to line it
    /// up with the table it's sitting on.
    ///
    /// Two ways to lead it, because both are things people reach for: swing the
    /// pinched hand around the board and the wood follows it, like a lazy
    /// susan; or hold still and twist your wrist. The swing is what actually
    /// carries a big turn — it accumulates without limit and is right-way-round
    /// by construction, since the board simply goes where the hand goes.
    ///
    /// Driven by the pinching hand rather than by `RotateGesture3D`, which on
    /// visionOS is the *two*-handed rotate: it would both demand two hands for
    /// a turn and swallow the two-handed pinch that `scaleGesture` needs. Only
    /// the heading is taken, so the board can never end up tilted or upside
    /// down, and it targets the slab specifically so a twist that starts on a
    /// pit still sows.
    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .handActivationBehavior(.pinch)
            .targetedToEntity(where: .has(BoardSlabComponent.self))
            .onChanged { value in
                if isScaling {
                    // A resize has taken this hand over. Leave the heading
                    // alone for the rest of the drag, so that releasing the
                    // second hand doesn't snap the board round by everything
                    // the two-handed pinch travelled through.
                    isRotationSuppressed = true
                }
                let delta = turnDelta(for: value)
                guard !isRotationSuppressed else { return }
                // Guarded: this runs every frame of the turn, and an
                // unconditional write would re-run the view for no reason.
                if !isRotating {
                    isRotating = true
                }
                boardRotator.orientation = Self.rotation(yaw: model.boardYaw + delta)
            }
            .onEnded { value in
                let delta = turnDelta(for: value)
                let suppressed = isRotationSuppressed || isScaling
                isRotating = false
                isRotationSuppressed = false
                turn = TurnState()
                guard !suppressed else { return }
                model.rotateBoard(by: delta)
            }
    }

    /// How far the board should have turned so far in this drag, advancing the
    /// per-drag bookkeeping as it goes.
    private func turnDelta(for value: EntityTargetValue<DragGesture.Value>) -> Float {
        var state = turn
        defer { turn = state }

        let twist = Self.twist(during: value) * Self.twistGain

        if let bearing = handBearing(in: value) {
            if let last = state.lastBearing {
                state.swing += normalizedAngle(bearing - last)
            }
            state.lastBearing = bearing
        }

        if state.swingOffset == nil, abs(state.swing) > Self.swingThreshold {
            // Carry over whatever the wrist had already turned, so the board
            // doesn't jump as the swing takes the lead.
            state.swingOffset = twist - state.swing
        }

        // Once swinging, the wrist is along for the ride: it follows the arc of
        // the arm, so counting it again would turn the board twice as far as
        // the hand went.
        return state.swingOffset.map { state.swing + $0 } ?? twist
    }

    /// The pinching hand's bearing around the board's axis of rotation, or
    /// `nil` when it's too close to that axis to read, or the driving device
    /// reports no position at all.
    private func handBearing(in value: EntityTargetValue<DragGesture.Value>) -> Float? {
        let hand = value.convert(value.location3D, from: .local, to: .scene)
        // The board turns about the vertical through the volume's center.
        guard (hand.x * hand.x + hand.z * hand.z).squareRoot() > Self.minimumSwingRadius else {
            return nil
        }
        // Matches the board's own sense of yaw: +y rotation carries +x toward -z.
        return atan2(-hand.z, hand.x)
    }

    /// How far the hand has twisted in place since the pinch began; zero when
    /// the driving device reports no pose to measure one from.
    private static func twist(during value: EntityTargetValue<DragGesture.Value>) -> Float {
        guard let start = value.startInputDevicePose3D, let current = value.inputDevicePose3D else {
            return 0
        }
        return yawDelta(from: start.rotation, to: current.rotation)
    }

    // MARK: - Size

    /// Pinch the board with both hands and pull apart to grow it, together to
    /// shrink it. This is the board's own resize: a volume's corner handles are
    /// drawn on the baseplate, which this one hides, so size is offered here
    /// and on the buttons in the main window instead.
    private var scaleGesture: some Gesture {
        MagnifyGesture()
            .targetedToEntity(where: .has(BoardSlabComponent.self))
            .onChanged { value in
                if scaleAtGestureStart == nil {
                    scaleAtGestureStart = model.boardScale
                    // A two-handed pinch starts as a one-handed one, so the
                    // twist gesture has already been running and may have
                    // turned the board a little. Put that back: the player
                    // reached for a resize, not a turn.
                    boardRotator.orientation = Self.rotation(yaw: model.boardYaw)
                }
                model.setBoardScale((scaleAtGestureStart ?? model.boardScale) * Float(value.magnification))
            }
            .onEnded { value in
                model.setBoardScale((scaleAtGestureStart ?? model.boardScale) * Float(value.magnification))
                scaleAtGestureStart = nil
            }
    }

    /// True while a two-handed pinch is resizing the board, so the twist
    /// gesture — which the same interaction also drives — stands down.
    private var isScaling: Bool {
        scaleAtGestureStart != nil
    }

    /// Gaze + pinch (and system-recognized pokes).
    private var pitTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                playPit(startingAt: value.entity)
            }
    }

    /// Direct touch: a fingertip pressed onto a pit ends as a touch-kind
    /// spatial event rather than always registering as a tap, so treat a
    /// completed touch on a pit as a play. When the system also recognizes
    /// the poke as a tap, `animateMove`'s in-progress guard drops the
    /// duplicate.
    private var pitTouchGesture: some Gesture {
        SpatialEventGesture()
            .onEnded { events in
                for event in events where event.kind == .touch && event.phase == .ended {
                    if let entity = event.targetedEntity {
                        playPit(startingAt: entity)
                    }
                }
            }
    }

    private func playPit(startingAt entity: Entity) {
        var current: Entity? = entity
        while let entity = current {
            if let pit = entity.components[PitIndexComponent.self]?.index {
                model.scene.onPitTapped?(pit)
                return
            }
            current = entity.parent
        }
    }
}

/// The result panel floating over the anchored board: same wording, score, and
/// actions as the window's end-game popup, rendered as a glass attachment so it
/// reads against the room rather than against the board's wood.
private struct SpatialEndGameBanner: View {
    let model: SpatialBoardModel

    var body: some View {
        // Kept mounted (empty, zero-size) while there's no result, so the
        // attachment's hosted view stays alive to observe `model.endGame`.
        if let endGame = model.endGame {
            VStack(spacing: 16) {
                Image(systemName: endGame.symbolName)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(endGame.symbolColor)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text(endGame.title)
                        .font(.system(size: 38, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)

                    Text(endGame.subtitle)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    Button {
                        model.onEndGameAction?(.primary)
                    } label: {
                        Label(endGame.primaryTitle, systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if let secondaryTitle = endGame.secondaryTitle {
                        Button {
                            model.onEndGameAction?(.secondary)
                        } label: {
                            Label(secondaryTitle, systemImage: "list.bullet")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .font(.headline)
                .controlSize(.large)
            }
            .padding(28)
            .frame(width: 360)
            .glassBackgroundEffect()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(endGame.title), \(endGame.subtitle)")
        }
    }
}
#endif
