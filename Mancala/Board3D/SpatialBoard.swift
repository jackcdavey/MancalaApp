#if os(visionOS)
import RealityKit
import SwiftUI
import simd

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
        static let resting = SIMD3<Float>(0.85, 0.4, 0.85)
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

    /// Turn the board by `angle` radians about the vertical axis, normalized to
    /// (-π, π] so repeated turns can't wind the value up indefinitely.
    func rotateBoard(by angle: Float) {
        var yaw = (boardYaw + angle).truncatingRemainder(dividingBy: 2 * .pi)
        if yaw > .pi {
            yaw -= 2 * .pi
        } else if yaw <= -.pi {
            yaw += 2 * .pi
        }
        boardYaw = yaw
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

    /// Resting height of the banner's center above the board's top face, in
    /// board-local units — clear of the wood, so the finished board stays
    /// visible beneath it.
    private static let bannerHeight: Float = 0.16
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
                // per-well count labels do.
                bannerAnchor.components.set(BillboardComponent())
                bannerAnchor.components.set(ViewAttachmentComponent(rootView: banner))
                bannerAnchor.isEnabled = false
                boardHolder.addChild(bannerAnchor)

                seatBoard(content: content, proxy: proxy)
            } update: { content in
                bannerAnchor.isEnabled = model.endGame != nil
                seatBoard(content: content, proxy: proxy)
            }
            .gesture(rotateGesture)
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
        let scale = min(max(fit, Self.minScale), Self.maxScale)

        boardHolder.scale = SIMD3(repeating: scale)
        boardHolder.position = SIMD3(0, bounds.min.y + BoardLayout3D.thickness * scale, 0)

        // The banner rides inside the scaled board, so its clearance is
        // measured in board-local units too. Clamped against the volume's
        // ceiling so a shallow volume lowers the banner toward the board
        // rather than clipping its top off.
        let headroom = (bounds.max.y - boardHolder.position.y) / scale
        let y = min(Self.bannerHeight, max(0.05, headroom - Self.bannerHalfHeight))
        bannerAnchor.position = SIMD3(0, y, 0)
    }

    // MARK: - Heading

    private static func rotation(yaw: Float) -> simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
    }

    /// The yaw component of a rotation, taken from the quaternion directly
    /// rather than from `axis` — which is undefined at zero rotation, the
    /// value every gesture starts at.
    private static func yaw(of rotation: Rotation3D) -> Float {
        let quaternion = rotation.quaternion
        return Float(2 * atan2(quaternion.imag.y, quaternion.real))
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

    /// Pinch the bare wood and twist to turn the board on the spot — the way
    /// you'd nudge a real board around to face the other player, or to line it
    /// up with the table it's sitting on. Constrained to the vertical axis so
    /// the board can never end up tilted or upside down, and targeted at the
    /// slab specifically so a twist that starts on a pit still sows.
    private var rotateGesture: some Gesture {
        RotateGesture3D(constrainedToAxis: .y)
            .targetedToEntity(where: .has(BoardSlabComponent.self))
            .onChanged { value in
                // Guarded: this runs every frame of the twist, and an
                // unconditional write would re-run the view for no reason.
                if !isRotating {
                    isRotating = true
                }
                boardRotator.orientation = Self.rotation(yaw: model.boardYaw + Self.yaw(of: value.rotation))
            }
            .onEnded { value in
                model.rotateBoard(by: Self.yaw(of: value.rotation))
                isRotating = false
            }
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
