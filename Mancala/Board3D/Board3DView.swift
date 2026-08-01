import RealityKit
import SwiftUI
import simd

#if os(visionOS)
/// SwiftUI host for the 3D board inside the main window — the same carved board
/// the volume puts in the room, kept in the window for players who'd rather not
/// place it out in their space.
///
/// visionOS has no virtual camera; the viewer's own head is the camera. So
/// where iOS frames the board by pointing a camera down at it, this scales the
/// board to the window's 3D bounds and leans it back toward the viewer by the
/// same angle the iOS camera looks down from, which reads as the same
/// foreshortened board.
struct Board3DView: View {
    let pits: [Int]
    let playablePits: Set<Int>
    let hintedPit: Int?
    let currentStoreIndex: Int?
    let flipped: Bool
    let isPortrait: Bool
    let showLabels: Bool
    let isDarkMode: Bool
    let boardMaterial: BoardMaterialStyle
    let scene: BoardScene

    /// Scaled and centered within the window's bounds.
    @State private var boardHolder = Entity()
    /// Carries the lean and the pass-and-play flip, so neither fights the
    /// fitting pass that owns the holder's scale and position.
    @State private var boardLean = Entity()

    /// Matches `BoardScene`'s camera pitch on iOS, so the board is foreshortened
    /// by the same amount here as it is there.
    private static let lean: Float = 0.92
    /// Depth to ask the window for. Enough that the leaned board is framed by
    /// the window's width and height, the way the iOS board is, rather than
    /// being squeezed flat by the depth first.
    private static let depth: CGFloat = 320
    /// Clearance kept between the board and the edges of its bounds.
    private static let fitMargin: Float = 0.94

    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in
                let sceneRoot = await scene.buildRoot()
                boardLean.addChild(sceneRoot)
                boardLean.orientation = Self.orientation(flipped: flipped)
                boardHolder.addChild(boardLean)
                content.add(boardHolder)
                fitBoard(content: content, proxy: proxy)
                syncScene()
            } update: { content in
                fitBoard(content: content, proxy: proxy)
                syncScene()
            }
            .gesture(pitTapGesture)
        }
        .frame(depth: Self.depth)
        .onChange(of: flipped) { _, isFlipped in
            boardLean.move(
                to: Transform(scale: .one, rotation: Self.orientation(flipped: isFlipped), translation: .zero),
                relativeTo: boardHolder,
                duration: 0.5,
                timingFunction: .easeInOut
            )
        }
        .accessibilityLabel("Mancala board")
    }

    /// The board leaned back toward the viewer, turned end for end when the
    /// table is flipped to face player two.
    private static func orientation(flipped: Bool) -> simd_quatf {
        simd_quatf(angle: lean, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: flipped ? .pi : 0, axis: SIMD3(0, 1, 0))
    }

    /// Size the board to the window's bounds. The board is leaned, so what has
    /// to fit is the box the leaned board occupies: standing it up trades depth
    /// for height.
    private func fitBoard(content: RealityViewContent, proxy: GeometryProxy3D) {
        let bounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
        let lying = cos(Self.lean)
        let standing = sin(Self.lean)
        let across = BoardLayout3D.contentHalfWidth * 2
        let along = BoardLayout3D.contentHalfDepth * 2
        let tall = BoardLayout3D.contentHeight
        let needed = SIMD3<Float>(
            across,
            tall * lying + along * standing,
            tall * standing + along * lying
        )

        // Depth only constrains the fit when the window actually grants some.
        // A window that reports none would otherwise scale the board to nothing
        // and leave the board slot empty; better a board that's clipped front to
        // back than no board at all.
        let extents = bounds.extents
        let depthLimit = extents.z > 0.01 ? extents.z / needed.z : .greatestFiniteMagnitude
        let fit = min(
            extents.x / needed.x,
            extents.y / needed.y,
            depthLimit
        ) * Self.fitMargin

        boardHolder.scale = SIMD3(repeating: max(fit, 0.01))
        boardHolder.position = bounds.center
    }

    /// The flip is applied to the board itself here rather than to a camera, so
    /// the scene is told the board is unflipped; the same goes for the other
    /// camera-framing inputs, which do nothing without a camera.
    private func syncScene() {
        scene.sync(
            pits: pits,
            playable: playablePits,
            hinted: hintedPit,
            currentStore: currentStoreIndex,
            flipped: false,
            portrait: false,
            viewSize: CGSize(width: 1, height: 1),
            showLabels: showLabels,
            dark: isDarkMode,
            material: boardMaterial
        )
    }

    private var pitTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                if let pit = value.entity.pitIndex {
                    scene.onPitTapped?(pit)
                }
            }
    }
}
#else
/// SwiftUI host for the 3D board. Renders the RealityKit scene, forwards
/// observed game state into `BoardScene`, and routes entity taps back to the
/// game flow. Count labels are 3D text meshes managed by `BoardScene`
/// (RealityView attachments are not available on iOS).
struct Board3DView: View {
    let pits: [Int]
    let playablePits: Set<Int>
    let hintedPit: Int?
    let currentStoreIndex: Int?
    let flipped: Bool
    let isPortrait: Bool
    let showLabels: Bool
    let isDarkMode: Bool
    let boardMaterial: BoardMaterialStyle
    let scene: BoardScene

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.camera = .virtual
                let sceneRoot = await scene.buildRoot()
                content.add(sceneRoot)
                syncScene(viewSize: geometry.size)
            } update: { _ in
                syncScene(viewSize: geometry.size)
            }
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        if let pit = value.entity.pitIndex {
                            scene.onPitTapped?(pit)
                        }
                    }
            )
        }
        .accessibilityLabel("Mancala board")
    }

    private func syncScene(viewSize: CGSize) {
        scene.sync(
            pits: pits,
            playable: playablePits,
            hinted: hintedPit,
            currentStore: currentStoreIndex,
            flipped: flipped,
            portrait: isPortrait,
            viewSize: viewSize,
            showLabels: showLabels,
            dark: isDarkMode,
            material: boardMaterial
        )
    }
}
#endif
