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
    let stoneSet: StoneSetStyle
    let scene: BoardScene

    /// The board's result banner rides in the board's own scene rather than
    /// over it as window content: a panel drawn flat on the window is run
    /// through by a board that leans out toward the viewer, and no amount of
    /// nudging it forward in the window's depth fixes that reliably. In here,
    /// the renderer sorts the two.
    @Environment(SpatialBoardModel.self) private var spatialBoard

    /// Scaled and centered within the window's bounds.
    @State private var boardHolder = Entity()
    /// Carries the lean and the pass-and-play flip, so neither fights the
    /// fitting pass that owns the holder's scale and position.
    @State private var boardLean = Entity()
    /// Billboarded host for the result banner, kept out of `boardHolder` so
    /// shrinking the board doesn't shrink the result along with it.
    @State private var bannerAnchor = Entity()

    /// How far back the board is leaned toward the viewer. Lying back matches
    /// `BoardScene`'s camera pitch on iOS, so a board across a wide window is
    /// foreshortened by the same amount here as it is there.
    ///
    /// Stood end-up in a tall window it has to lean much closer to upright:
    /// what leaning costs in depth is proportional to the length of the board
    /// running away from the viewer, and end-up that's its long axis — laid
    /// back the same amount, a portrait board would reach half a meter out of
    /// the window.
    private static let landscapeLean: Float = 0.92
    private static let portraitLean: Float = 1.4
    /// Depth to ask the window for. Enough that the leaned board is framed by
    /// the window's width and height, the way the iOS board is, rather than
    /// being squeezed flat by the depth first — but no deeper, because
    /// everything the board reaches forward costs it twice: it draws over
    /// SwiftUI chrome sitting on the window plane, like menus and sheets, and
    /// it projects larger than its own footprint.
    ///
    /// Not private: it's the depth of the window's content as a whole, so
    /// anything the window layers over the board inherits it (see
    /// `ContentView`'s main menu).
    static let windowDepth: CGFloat = boardDepth + bannerDepth
    /// The share of that depth the board itself may fill.
    private static let boardDepth: CGFloat = 200
    /// The share kept clear in front of the board, so the result banner has
    /// somewhere to sit that's ahead of the board and still inside the window's
    /// bounds.
    private static let bannerDepth: CGFloat = 60
    /// Gap between the board's nearest point and the banner.
    private static let bannerClearance: Float = 0.008
    /// Clearance kept between the board and the edges of its bounds. Generous,
    /// because the board stands in front of the window rather than on it: it's
    /// nearer the eye than the glass is, so it projects bigger than the box it
    /// occupies, and a board fitted flush to its bounds spills past the
    /// window's edges.
    private static let fitMargin: Float = 0.85
    /// Clearance kept below the board, in meters, on top of that margin.
    private static let bottomInset: Float = 0.022

    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in
                let sceneRoot = await scene.buildRoot()
                boardLean.addChild(sceneRoot)
                boardLean.orientation = orientation
                boardHolder.addChild(boardLean)
                content.add(boardHolder)

                bannerAnchor.components.set(BillboardComponent())
                bannerAnchor.components.set(ViewAttachmentComponent(rootView: banner))
                bannerAnchor.isEnabled = false
                content.add(bannerAnchor)

                fitBoard(content: content, proxy: proxy)
                syncScene()
            } update: { content in
                bannerAnchor.isEnabled = spatialBoard.endGame != nil
                fitBoard(content: content, proxy: proxy)
                syncScene()
            }
            .gesture(pitTapGesture)
        }
        .frame(depth: Self.windowDepth)
        .onChange(of: flipped) { _, _ in settleLean() }
        .onChange(of: isPortrait) { _, _ in settleLean() }
        .accessibilityLabel("Mancala board")
    }

    /// The banner's content, re-evaluated by SwiftUI as the result changes;
    /// the attachment hosts it as a live view.
    private var banner: some View {
        SpatialEndGameBanner(model: spatialBoard)
    }

    /// The board leaned back toward the viewer, turned end for end when the
    /// table is flipped to face player two. Standing it on end for a tall
    /// window is `BoardScene`'s job, not this one's — the scene owns which way
    /// round that turn goes, and the 2D board's portrait layout is matched to
    /// it.
    private var orientation: simd_quatf {
        simd_quatf(angle: isPortrait ? Self.portraitLean : Self.landscapeLean, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: flipped ? .pi : 0, axis: SIMD3(0, 1, 0))
    }

    private func settleLean() {
        boardLean.move(
            to: Transform(scale: .one, rotation: orientation, translation: .zero),
            relativeTo: boardHolder,
            duration: 0.5,
            timingFunction: .easeInOut
        )
    }

    /// Size the board to the window's bounds. The board is leaned, so what has
    /// to fit is the box the leaned board occupies: standing it up trades depth
    /// for height.
    private func fitBoard(content: RealityViewContent, proxy: GeometryProxy3D) {
        let bounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
        let lean = isPortrait ? Self.portraitLean : Self.landscapeLean
        let lying = cos(lean)
        let standing = sin(lean)
        // Stood on end for a tall window, it's the board's length that runs up
        // the window and its width that runs across.
        let across = 2 * (isPortrait ? BoardLayout3D.contentHalfDepth : BoardLayout3D.contentHalfWidth)
        let along = 2 * (isPortrait ? BoardLayout3D.contentHalfWidth : BoardLayout3D.contentHalfDepth)
        let tall = BoardLayout3D.contentHeight
        let needed = SIMD3<Float>(
            across,
            tall * lying + along * standing,
            tall * standing + along * lying
        )

        // The margin applies to what the window shows of the board, not to how
        // far it reaches toward the viewer — depth is a hard ceiling, and
        // holding the board back from it would only waste it.
        //
        // Depth constrains the fit only when the window actually grants some. A
        // window reporting none would otherwise scale the board to nothing and
        // leave the board slot empty; better a board clipped front to back than
        // no board at all.
        // Held clear of the bottom of its own slot rather than by padding the
        // slot: the leaned board's near edge is the part that reaches for the
        // window's lower edge and the system handle below it.
        let extents = bounds.extents
        let usableHeight = max(extents.y - Self.bottomInset, 0.01)

        // The board gets the back of the depth; the front is kept for the
        // banner. Taken as a share of whatever depth the window granted, so the
        // two stay in proportion however much that turns out to be.
        let boardDepth = extents.z * Float(Self.boardDepth / Self.windowDepth)
        let reserved = extents.z - boardDepth

        let framed = min(extents.x / needed.x, usableHeight / needed.y) * Self.fitMargin
        let deep = boardDepth > 0.01 ? boardDepth / needed.z : .greatestFiniteMagnitude
        let scale = max(min(framed, deep), 0.01)

        boardHolder.scale = SIMD3(repeating: scale)
        boardHolder.position = bounds.center + SIMD3(0, Self.bottomInset / 2, -reserved / 2)

        // Just ahead of the board's nearest point, wherever the fit put that.
        bannerAnchor.position = SIMD3(
            bounds.center.x,
            bounds.center.y,
            boardHolder.position.z + needed.z * scale / 2 + Self.bannerClearance
        )
    }

    /// `portrait` stands the board on end for a tall window, which the scene
    /// does by turning the board itself — so it applies here just as it does on
    /// iOS. The flip is the opposite case: on iOS the scene swings a camera,
    /// which visionOS hasn't got, so this view turns the board instead and the
    /// scene is told it's unflipped. `viewSize` only frames that camera.
    private func syncScene() {
        scene.sync(
            pits: pits,
            playable: playablePits,
            hinted: hintedPit,
            currentStore: currentStoreIndex,
            flipped: false,
            portrait: isPortrait,
            viewSize: CGSize(width: 1, height: 1),
            showLabels: showLabels,
            dark: isDarkMode,
            material: boardMaterial,
            stoneSet: stoneSet
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
    let stoneSet: StoneSetStyle
    let scene: BoardScene

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.camera = .virtual
                let sceneRoot = await scene.buildRoot()
                content.add(sceneRoot)
                syncScene(viewSize: geometry.size)
            } update: { _ in
                PerfProbe.tick("RealityUpdate")
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
            material: boardMaterial,
            stoneSet: stoneSet
        )
    }
}
#endif
