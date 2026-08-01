import RealityKit
import SwiftUI
import simd

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformColor = NSColor
#endif

/// Tags a tap-target entity with the `MancalaGame.pits` index it represents.
struct PitIndexComponent: Component {
    let index: Int
}

/// Tags the carved slab itself. On visionOS the board's bare wood is what the
/// rotate gesture grabs, so it needs to be findable without reaching for the
/// pit targets that sit on top of it.
struct BoardSlabComponent: Component {}

extension Entity {
    /// The pit this entity stands for, looking up through its ancestors: a hit
    /// test can land on any part of a tap target, not just the tagged entity.
    var pitIndex: Int? {
        var entity: Entity? = self
        while let current = entity {
            if let index = current.components[PitIndexComponent.self]?.index {
                return index
            }
            entity = current.parent
        }
        return nil
    }
}

/// Per-frame motion state for a flying sowing stone: a damped-spring follower
/// chasing `target`, so velocity carries across retargets — the pile
/// accelerates out of a well, coasts, and settles into the next one instead
/// of stopping dead on every hop.
struct SowingMotionComponent: Component {
    var target: SIMD3<Float>
    var velocity: SIMD3<Float> = .zero
    /// Spring constant of the follower; higher tracks the target tighter.
    var stiffness: Float
    /// Velocity decay rate; near critical (2·√stiffness) so the follower lags
    /// with momentum but never visibly oscillates — jiggle reads as soft.
    var damping: Float
}

/// Integrates every `SowingMotionComponent` each frame, then runs a
/// lightweight rigid-contact pass so the traveling stones never interpenetrate.
struct SowingMotionSystem: System {
    private static let query = EntityQuery(where: .has(SowingMotionComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        // Clamp dt so a frame hitch can't fling the spring past its target.
        let dt = Float(min(context.deltaTime, 1.0 / 30.0))
        guard dt > 0 else { return }
        var moving: [Entity] = []
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var motion = entity.components[SowingMotionComponent.self] else { continue }
            motion.velocity += (motion.target - entity.position) * motion.stiffness * dt
            motion.velocity *= exp(-motion.damping * dt)
            entity.position += motion.velocity * dt
            entity.components.set(motion)
            moving.append(entity)
        }

        // Sphere-sphere separation: project overlapping pairs apart and kill
        // their approaching velocity, so contacts hold rigidly instead of
        // springing through each other. O(n²) over the ≤ two dozen flyers.
        guard moving.count > 1 else { return }
        let minDistance = BoardLayout3D.stoneRadius * 2
        for i in 0..<(moving.count - 1) {
            for j in (i + 1)..<moving.count {
                let a = moving[i]
                let b = moving[j]
                var delta = b.position - a.position
                var distance = simd_length(delta)
                if distance < 1e-5 {
                    delta = SIMD3(minDistance * 0.01, 0, 0)
                    distance = minDistance * 0.01
                }
                guard distance < minDistance else { continue }
                let normal = delta / distance
                let push = (minDistance - distance) / 2
                a.position -= normal * push
                b.position += normal * push
                guard var motionA = a.components[SowingMotionComponent.self],
                      var motionB = b.components[SowingMotionComponent.self] else { continue }
                let approaching = simd_dot(motionB.velocity - motionA.velocity, normal)
                if approaching < 0 {
                    let correction = normal * (approaching / 2)
                    motionA.velocity += correction
                    motionB.velocity -= correction
                    a.components.set(motionA)
                    b.components.set(motionB)
                }
            }
        }
    }
}


/// Owns the RealityKit entity graph for the 3D board: the carved slab, the
/// camera rig, lights, stones, highlight rings, and the sowing animation.
/// `Board3DView` forwards SwiftUI state here; game logic stays in
/// `MancalaGame`/`ContentView` and this class only mirrors it visually.
/// `@Observable` so views can show a loading indicator while `isBuilt` is
/// still false — building involves off-main-actor mesh/texture generation
/// that can take a visible moment, especially on first launch.
@Observable
@MainActor
final class BoardScene {
    var onPitTapped: ((Int) -> Void)?

    private let root = Entity()
    /// Orbits the whole camera rig around the board's vertical axis; the flip
    /// arc animates this so the view swings to the opposite player's seat.
    private let cameraOrbit = Entity()
    private let cameraRig = Entity()
    private let camera = PerspectiveCamera()
    private let boardRoot = Entity()
    private let iblEntity = Entity()
    private let keyLight = Entity()

    // All of the private bookkeeping below is @ObservationIgnored: `sync`
    // runs inside RealityView's `update:` closure, so any tracked property it
    // reads makes that closure re-run on the property's next mutation.
    // Observation fires `willSet` *before* the mutation executes, so a tracked
    // ledger array could be trimmed by a re-entrant `sync` between a guard
    // (`isEmpty`) and its `removeLast()` in the same statement — an
    // intermittent empty-collection trap during capture animations. None of
    // this state is rendered by SwiftUI, so nothing legitimate observes it.
    @ObservationIgnored private var stones: [[Entity]] = Array(repeating: [], count: 14)
    /// Palette index of every logical stone in every pit (uncapped, unlike the
    /// visible `stones` entities). Colors travel with the sowing/capture
    /// animations so each stone keeps one color for the whole game.
    @ObservationIgnored private var stoneColors: [[Int]] = Array(repeating: [], count: 14)
    /// Colors queued by animated drops into a pit, consumed by `applyStones`
    /// when the model's count for that pit grows.
    @ObservationIgnored private var pendingDropColors: [[Int]] = Array(repeating: [], count: 14)
    /// Colors most recently trimmed from a pit by `applyStones`, kept so an
    /// animation that starts after the model sync can still recover them.
    @ObservationIgnored private var lastRemovedColors: [[Int]] = Array(repeating: [], count: 14)
    /// Flyers that finished their drop and now rest on the slot their resting
    /// stone will occupy; `applyStones` swaps each for the real resting stone
    /// in place, so the handoff is invisible.
    @ObservationIgnored private var landedFlyers: [[ModelEntity]] = Array(repeating: [], count: 14)
    /// Rotating fallback so stones created without an animation event (initial
    /// board, reset, undo) still get varied colors.
    @ObservationIgnored private var fallbackColorCursor = 0

    private func nextFallbackColor() -> Int {
        let color = fallbackColorCursor
        fallbackColorCursor = (fallbackColorCursor + 1) % StoneFactory.palette.count
        return color
    }
    @ObservationIgnored private var highlightRings: [ModelEntity] = []
    @ObservationIgnored private var labelAnchors: [Entity] = []
    @ObservationIgnored private var labelTextEntities: [ModelEntity] = []
    @ObservationIgnored private var labelTextMaterial = UnlitMaterial()
    @ObservationIgnored private var textMeshCache: [Int: MeshResource] = [:]

    @ObservationIgnored private var lightEnvironment: EnvironmentResource?
    @ObservationIgnored private var darkEnvironment: EnvironmentResource?

    @ObservationIgnored private var playableMaterial = UnlitMaterial()
    @ObservationIgnored private var hintMaterial = UnlitMaterial()
    @ObservationIgnored private var storeMaterial = UnlitMaterial()

    /// The carved slab, kept so its finish can be swapped at runtime.
    @ObservationIgnored private var slab: ModelEntity?
    @ObservationIgnored private var appliedMaterial: BoardMaterialStyle?
    @ObservationIgnored private var materialCache: [BoardMaterialStyle: PhysicallyBasedMaterial] = [:]
    /// Count of in-flight uncached material bakes; > 0 while at least one is
    /// running, so views can show a busy state instead of an unlabeled pause.
    private var pendingMaterialBakes = 0
    var isSwitchingMaterial: Bool { pendingMaterialBakes > 0 }

    private(set) var isBuilt = false

    // Mirrored view state, so `sync` is cheap to call repeatedly.
    @ObservationIgnored private var appliedPits: [Int] = []
    @ObservationIgnored private var appliedPlayable: Set<Int> = []
    @ObservationIgnored private var appliedHinted: Int?
    @ObservationIgnored private var appliedStore: Int?
    @ObservationIgnored private var flipped = false
    @ObservationIgnored private var portrait = false
    @ObservationIgnored private var viewSize = CGSize(width: 1, height: 1)
    @ObservationIgnored private var labelsVisible = true
    @ObservationIgnored private var isDark = false
    @ObservationIgnored private var parallaxYaw: Float = 0
    @ObservationIgnored private var parallaxPitch: Float = 0
    /// 0 at rest, peaks at 1 mid-flip; dollies the camera back during the swing.
    @ObservationIgnored private var flipArc: Float = 0
    @ObservationIgnored private var flipArcTask: Task<Void, Never>?

    /// Camera elevation: a fairly high, near-top-down look at the board.
    private let basePitch: Float = -0.92 // ≈ 53° looking down
    private let fieldOfViewDegrees: Float = 40
    /// Overscan factor pulling the camera back so the near (bottom) edge, its
    /// rim, and the raised front-row stones/labels are never clipped.
    private let boardFillMargin: Float = 1.2

    /// Pass-and-play flip as a single rotation of the camera about the board's
    /// horizontal (world-X) axis: the camera arcs up over the top to the
    /// opposite seat and lands with the identical downward tilt mirrored for the
    /// other player. This is the shortest path between the two correct views, so
    /// only the camera appears to move — the board never spins. The angle is
    /// derived so the far-seat view matches a 180° orbit + 180° roll.
    private var flipRotation: Float { -(.pi + 2 * basePitch) }

    // Pending state delivered before `build` finished.
    private struct PendingSync {
        var pits: [Int]
        var playable: Set<Int>
        var hinted: Int?
        var currentStore: Int?
        var flipped: Bool
        var portrait: Bool
        var viewSize: CGSize
        var showLabels: Bool
        var dark: Bool
        var material: BoardMaterialStyle
    }
    @ObservationIgnored private var pendingSync: PendingSync?

    // MARK: - Build

    /// Builds the full entity graph (idempotent) and returns the root for
    /// `Board3DView` to add to the RealityView content.
    func buildRoot() async -> Entity {
        guard !isBuilt else {
            return root
        }
        PitIndexComponent.registerComponent()
        BoardSlabComponent.registerComponent()
        SowingMotionComponent.registerComponent()
        SowingMotionSystem.registerSystem()

        // Heavy procedural work: slab mesh, ring meshes, wood texture, and
        // both lighting environments, all generated off the main actor.
        let slabDataTask = Task.detached(priority: .userInitiated) {
            BoardMeshBuilder.slabMeshData()
        }
        let ringDataTask = Task.detached(priority: .userInitiated) {
            BoardLayout3D.wells.map { BoardMeshBuilder.ringMeshData(around: $0) }
        }

        let slabData = await slabDataTask.value
        let ringData = await ringDataTask.value

        // Slab. Built with a plain placeholder finish; the real textured
        // material is baked and applied by `applyMaterial` for the selected
        // style, so only the chosen finish is ever generated.
        do {
            let slabMesh = try await MeshResource(from: [BoardMeshBuilder.descriptor(from: slabData, name: "boardSlab")])
            var placeholder = PhysicallyBasedMaterial()
            placeholder.baseColor = .init(tint: PlatformColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 1))
            placeholder.roughness = 0.5
            let slab = ModelEntity(mesh: slabMesh, materials: [placeholder])
            #if os(visionOS)
            // Seats the slab visually on the volume's baseplate / the real
            // surface the volume is snapped to.
            slab.components.set(GroundingShadowComponent(castsShadow: true))
            // Grab surface for the rotate gesture. A box around the slab rather
            // than the carved mesh: the raised pit targets stand proud of the
            // wood, so they still win the hit test where they overlap, and the
            // bare wood between and around them becomes the handle.
            slab.components.set(BoardSlabComponent())
            slab.components.set(CollisionComponent(shapes: [
                .generateBox(
                    width: BoardLayout3D.width,
                    height: BoardLayout3D.thickness,
                    depth: BoardLayout3D.depth
                )
                .offsetBy(translation: SIMD3(0, -BoardLayout3D.thickness / 2, 0))
            ]))
            slab.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            #endif
            boardRoot.addChild(slab)
            self.slab = slab
        } catch {
            assertionFailure("Board slab generation failed: \(error)")
        }

        // Highlight rings, one per well, hidden until needed. Vertices are in
        // absolute board coordinates, so the entities sit at the origin.
        playableMaterial = makeRingMaterial(PlatformColor(red: 0.35, green: 0.80, blue: 1.0, alpha: 1), opacity: 0.85)
        hintMaterial = makeRingMaterial(PlatformColor(red: 1.0, green: 0.84, blue: 0.20, alpha: 1), opacity: 0.95)
        storeMaterial = makeRingMaterial(PlatformColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1), opacity: 0.7)
        highlightRings = []
        for data in ringData {
            do {
                let mesh = try await MeshResource(from: [BoardMeshBuilder.descriptor(from: data, name: "highlightRing")])
                let ring = ModelEntity(mesh: mesh, materials: [playableMaterial])
                ring.isEnabled = false
                boardRoot.addChild(ring)
                highlightRings.append(ring)
            } catch {
                highlightRings.append(ModelEntity())
            }
        }

        // Tap targets and count labels per well. Labels are 3D text meshes
        // (RealityView attachments are unavailable on iOS): a billboarded
        // anchor holding a dark backing pill and a white digit mesh that
        // `updateLabel` swaps whenever the count changes.
        labelAnchors = []
        labelTextEntities = []
        labelTextMaterial = UnlitMaterial(color: .white)
        var labelBackgroundMaterial = UnlitMaterial(color: .black)
        labelBackgroundMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.38))
        for (index, well) in BoardLayout3D.wells.enumerated() {
            let isStore = well.axisHalfLength > 0
            if !isStore {
                let target = Entity()
                target.position = SIMD3(well.center.x, 0, well.center.y)
                #if os(visionOS)
                // Raised, slightly oversized poke target so a fingertip
                // connects above the wood; playable by direct touch as well
                // as gaze + pinch, with gaze/proximity hover feedback.
                target.components.set(CollisionComponent(shapes: [
                    .generateSphere(radius: well.radius * 1.25)
                        .offsetBy(translation: SIMD3(0, 0.012, 0))
                ]))
                target.components.set(InputTargetComponent(allowedInputTypes: .all))
                target.components.set(HoverEffectComponent())
                #else
                target.components.set(CollisionComponent(shapes: [.generateSphere(radius: well.radius * 1.1)]))
                target.components.set(InputTargetComponent())
                #endif
                target.components.set(PitIndexComponent(index: index))
                boardRoot.addChild(target)
            }

            let labelAnchor = Entity()
            let outward: SIMD2<Float> = isStore
                ? SIMD2(well.center.x > 0 ? BoardLayout3D.labelStoreOutset : -BoardLayout3D.labelStoreOutset, 0)
                : SIMD2(0, well.center.y > 0 ? BoardLayout3D.labelPitOutset : -BoardLayout3D.labelPitOutset)
            labelAnchor.position = SIMD3(
                well.center.x + outward.x,
                BoardLayout3D.labelHeight,
                well.center.y + outward.y
            )
            labelAnchor.components.set(BillboardComponent())
            boardRoot.addChild(labelAnchor)
            labelAnchors.append(labelAnchor)

            let background = ModelEntity(
                mesh: .generatePlane(
                    width: BoardLayout3D.labelPillWidth,
                    height: BoardLayout3D.labelPillHeight,
                    cornerRadius: BoardLayout3D.labelPillHeight / 2
                ),
                materials: [labelBackgroundMaterial]
            )
            labelAnchor.addChild(background)

            let text = ModelEntity()
            text.position = SIMD3(0, 0, 0.0012)
            labelAnchor.addChild(text)
            labelTextEntities.append(text)
        }

        #if !os(visionOS)
        // Lighting: image-based light for the glass/varnish reflections plus
        // a shadow-casting key light for stone grounding. Only the currently
        // needed scheme's environment is built now; the other is constructed
        // lazily the first time the color scheme flips, keeping launch cheaper.
        // On visionOS neither is added: mixed immersion lights the board from
        // the real room, so virtual lights would double-expose it.
        if let environment = await ensureEnvironment(dark: isDark) {
            iblEntity.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.9))
            root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
        }
        root.addChild(iblEntity)

        keyLight.components.set(DirectionalLightComponent(color: .white, intensity: isDark ? 1700 : 2600))
        keyLight.components.set(DirectionalLightComponent.Shadow())
        keyLight.orientation = simd_quatf(angle: -0.95, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: 0.5, axis: SIMD3(0, 1, 0))
        root.addChild(keyLight)

        // Camera rig: pivot at the board center; parallax and the base pitch
        // both rotate the rig, so the camera orbits the board like a viewer
        // leaning around a physical object. `cameraOrbit` sits above the rig
        // and carries only the flip yaw, so the flip arc never fights the live
        // parallax writes that land on `cameraRig`. On visionOS there is no
        // camera at all — the board is anchored in the room and the viewer
        // simply moves around it.
        camera.camera.fieldOfViewInDegrees = fieldOfViewDegrees
        cameraRig.addChild(camera)
        cameraOrbit.addChild(cameraRig)
        root.addChild(cameraOrbit)
        #endif

        root.addChild(boardRoot)

        isBuilt = true
        if let pending = pendingSync {
            pendingSync = nil
            sync(
                pits: pending.pits,
                playable: pending.playable,
                hinted: pending.hinted,
                currentStore: pending.currentStore,
                flipped: pending.flipped,
                portrait: pending.portrait,
                viewSize: pending.viewSize,
                showLabels: pending.showLabels,
                dark: pending.dark,
                material: pending.material
            )
        } else {
            updateBoardOrientation(animated: false)
            updateCameraOrbit(animated: false)
            updateCamera()
            applyMaterial(.walnut)
        }
        prewarmRemainingMaterials()
        return root
    }

    private func makeRingMaterial(_ color: PlatformColor, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        material.faceCulling = .none
        return material
    }

    // MARK: - Board finish

    /// Physically based parameters that pair with each finish's base-color bake.
    private struct FinishSpec {
        let roughness: Float
        let metallic: Float
        let clearcoat: Float
        let clearcoatRoughness: Float
        let fallback: PlatformColor
        /// Translucency for glass-like finishes; `nil` keeps the slab opaque.
        var opacity: Float? = nil
    }

    private static func finishSpec(for style: BoardMaterialStyle) -> FinishSpec {
        switch style {
        case .walnut:
            FinishSpec(roughness: 0.5, metallic: 0, clearcoat: 0.35, clearcoatRoughness: 0.4,
                       fallback: PlatformColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 1))
        case .maple:
            FinishSpec(roughness: 0.55, metallic: 0, clearcoat: 0.3, clearcoatRoughness: 0.45,
                       fallback: PlatformColor(red: 0.80, green: 0.70, blue: 0.52, alpha: 1))
        case .marble:
            FinishSpec(roughness: 0.18, metallic: 0, clearcoat: 0.6, clearcoatRoughness: 0.2,
                       fallback: PlatformColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1))
        case .slate:
            FinishSpec(roughness: 0.85, metallic: 0, clearcoat: 0, clearcoatRoughness: 1.0,
                       fallback: PlatformColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1))
        case .frostedGlass:
            // Moderate roughness blurs the reflections (frosted, not clear); a
            // glossy clearcoat over the top keeps a wet sheen. Partially
            // translucent so it reads as glass rather than painted stone.
            FinishSpec(roughness: 0.42, metallic: 0, clearcoat: 0.9, clearcoatRoughness: 0.25,
                       fallback: PlatformColor(red: 0.82, green: 0.88, blue: 0.94, alpha: 1),
                       opacity: 0.6)
        }
    }

    /// Bakes the base-color image, the `TextureResource` built from it, and
    /// the assembled material for one finish.
    ///
    /// Only the base-color image bake (pure CoreGraphics/Swift) is safe to run
    /// off the main actor. `TextureResource(image:options:)` and every
    /// `PhysicallyBasedMaterial` property setter below call into RealityKit's
    /// asset manager, which asserts (and crashes with `SIGTRAP` if violated)
    /// that it's running on the main actor's queue — confirmed by a crash log
    /// with `dispatch_assert_queue_fail` inside `PhysicallyBasedMaterial
    /// .roughness.setter` when this was previously moved into a detached
    /// task. This method must stay `@MainActor`-isolated (inherited from
    /// `BoardScene`) apart from that one detached image bake.
    private func bakedMaterial(for style: BoardMaterialStyle) async -> PhysicallyBasedMaterial {
        let spec = Self.finishSpec(for: style)
        let image = await Task.detached(priority: .userInitiated) {
            BoardTextureBuilder.baseColor(for: style)
        }.value

        var material = PhysicallyBasedMaterial()
        if let image, let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) {
            material.baseColor = .init(texture: .init(texture))
        } else {
            material.baseColor = .init(tint: spec.fallback)
        }
        material.roughness = .init(floatLiteral: spec.roughness)
        material.metallic = .init(floatLiteral: spec.metallic)
        material.clearcoat = .init(floatLiteral: spec.clearcoat)
        material.clearcoatRoughness = .init(floatLiteral: spec.clearcoatRoughness)
        if let opacity = spec.opacity {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    /// Swap the slab's finish; results are cached so switching back to a
    /// style already baked (including by `prewarmRemainingMaterials`) is
    /// instant. Rapid switching is safe — a late bake only applies if its
    /// style is still selected. `isSwitchingMaterial` goes true for the
    /// duration of an uncached bake so the UI can show it's working rather
    /// than sitting on an unlabeled pause.
    private func applyMaterial(_ style: BoardMaterialStyle) {
        appliedMaterial = style
        if let cached = materialCache[style] {
            slab?.model?.materials = [cached]
            return
        }
        pendingMaterialBakes += 1
        Task { [weak self] in
            guard let self else { return }
            let material = await self.bakedMaterial(for: style)
            self.pendingMaterialBakes -= 1
            self.materialCache[style] = material
            if self.appliedMaterial == style {
                self.slab?.model?.materials = [material]
            }
        }
    }

    /// Bakes every not-yet-cached finish shortly after the board is built,
    /// paced with a short yield between each so an already-open game stays
    /// responsive while it happens in the background. Without this, the
    /// first time a player picks an unfamiliar material in Settings incurs
    /// the same bake `applyMaterial` would otherwise do inline right then —
    /// which is the freeze this sidesteps by doing the work earlier and
    /// piecemeal instead.
    private func prewarmRemainingMaterials() {
        Task { [weak self] in
            for style in BoardMaterialStyle.allCases {
                guard let self else { return }
                guard self.materialCache[style] == nil else { continue }
                let material = await self.bakedMaterial(for: style)
                self.materialCache[style] = material
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    /// Cached digit mesh for a stone count (counts repeat constantly).
    /// The font size is in scene meters — RealityKit text geometry uses the
    /// point size directly as the em size.
    private func textMesh(for count: Int) -> MeshResource {
        if let cached = textMeshCache[count] {
            return cached
        }
        let mesh = MeshResource.generateText(
            "\(count)",
            extrusionDepth: 0.001,
            font: MeshResource.Font.systemFont(ofSize: 0.014, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )
        textMeshCache[count] = mesh
        return mesh
    }

    private func updateLabel(_ index: Int, count: Int) {
        guard labelTextEntities.indices.contains(index) else { return }
        let mesh = textMesh(for: count)
        let text = labelTextEntities[index]
        text.model = ModelComponent(mesh: mesh, materials: [labelTextMaterial])
        // generateText anchors at the baseline corner; recenter on the pill.
        let bounds = mesh.bounds
        text.position = SIMD3(-bounds.center.x, -bounds.center.y, 0.0012)
    }

    // MARK: - State sync

    /// Idempotent mirror of the SwiftUI-observed state; cheap when unchanged.
    func sync(
        pits: [Int],
        playable: Set<Int>,
        hinted: Int?,
        currentStore: Int?,
        flipped: Bool,
        portrait: Bool,
        viewSize: CGSize,
        showLabels: Bool,
        dark: Bool,
        material: BoardMaterialStyle
    ) {
        guard isBuilt else {
            pendingSync = PendingSync(
                pits: pits,
                playable: playable,
                hinted: hinted,
                currentStore: currentStore,
                flipped: flipped,
                portrait: portrait,
                viewSize: viewSize,
                showLabels: showLabels,
                dark: dark,
                material: material
            )
            return
        }

        if material != appliedMaterial {
            applyMaterial(material)
        }
        applyStones(pits: pits)
        applyHighlights(playable: playable, hinted: hinted, currentStore: currentStore)

        if flipped != self.flipped {
            self.flipped = flipped
            updateCameraOrbit(animated: true)
        }
        if portrait != self.portrait {
            self.portrait = portrait
            updateBoardOrientation(animated: true)
            updateCamera()
        }
        if viewSize != self.viewSize {
            self.viewSize = viewSize
            updateCamera()
        }
        if showLabels != labelsVisible {
            labelsVisible = showLabels
            for anchor in labelAnchors {
                anchor.isEnabled = showLabels
            }
        }
        if dark != isDark {
            isDark = dark
            applyColorScheme()
        }
    }

    /// Reconcile stone entities against the game's pit counts, O(delta).
    /// Deterministic slots guarantee existing stones never reshuffle.
    private func applyStones(pits: [Int]) {
        guard pits.count == 14 else { return }
        guard pits != appliedPits else { return }
        let previous = appliedPits
        appliedPits = pits

        for index in 0..<14 {
            if previous.count != 14 || previous[index] != pits[index] {
                updateLabel(index, count: pits[index])
            }

            // Reconcile the color ledger to the logical count first: shrink
            // stashes the removed colors for a late-starting animation to
            // recover; growth consumes colors queued by animated drops, with
            // the rotating fallback covering non-animated changes.
            let logical = pits[index]
            if stoneColors[index].count > logical {
                lastRemovedColors[index] = Array(stoneColors[index][logical...])
                stoneColors[index].removeSubrange(logical...)
                pendingDropColors[index] = []
                for flyer in landedFlyers[index] {
                    flyer.removeFromParent()
                }
                landedFlyers[index] = []
            }
            while stoneColors[index].count < logical {
                let color = pendingDropColors[index].isEmpty
                    ? nextFallbackColor()
                    : pendingDropColors[index].removeFirst()
                stoneColors[index].append(color)
            }

            let target = min(logical, BoardLayout3D.visibleStoneCap)
            var current = stones[index]
            while current.count > target {
                current.removeLast().removeFromParent()
            }
            while current.count < target {
                // A flyer that already landed on this slot is swapped for the
                // resting stone in place — no grow-in, or the stone would
                // visibly pop after having just physically settled.
                let landedFlyer = landedFlyers[index].isEmpty ? nil : landedFlyers[index].removeFirst()
                landedFlyer?.removeFromParent()
                let stone = StoneFactory.makeRestingStone(
                    pitIndex: index,
                    slot: current.count,
                    colorIndex: stoneColors[index][current.count]
                )
                if landedFlyer != nil || root.scene == nil {
                    // Also placed at rest when populated before the root joins
                    // a RealityView (e.g. the initial sync): animations can't
                    // run outside a scene, so the grow-in would freeze at its
                    // tiny start scale.
                    boardRoot.addChild(stone)
                } else {
                    let restTransform = Transform(translation: stone.position)
                    stone.transform.scale = SIMD3(repeating: 0.05)
                    boardRoot.addChild(stone)
                    stone.move(to: restTransform, relativeTo: boardRoot, duration: 0.18, timingFunction: .easeOut)
                }
                current.append(stone)
            }
            stones[index] = current
        }
    }

    private func applyHighlights(playable: Set<Int>, hinted: Int?, currentStore: Int?) {
        guard playable != appliedPlayable || hinted != appliedHinted || currentStore != appliedStore else {
            return
        }
        appliedPlayable = playable
        appliedHinted = hinted
        appliedStore = currentStore

        for (index, ring) in highlightRings.enumerated() {
            if index == hinted {
                ring.model?.materials = [hintMaterial]
                ring.isEnabled = true
            } else if playable.contains(index) {
                ring.model?.materials = [playableMaterial]
                ring.isEnabled = true
            } else if index == currentStore {
                ring.model?.materials = [storeMaterial]
                ring.isEnabled = true
            } else {
                ring.isEnabled = false
            }
        }
    }

    private func applyColorScheme() {
        #if os(visionOS)
        // Real-room lighting; nothing scheme-dependent to swap.
        return
        #else
        // The opposite scheme's environment may not be built yet; construct it
        // lazily and swap the IBL in once ready (the key light updates instantly).
        Task { [weak self] in
            guard let self else { return }
            let dark = self.isDark
            if let environment = await self.ensureEnvironment(dark: dark), self.isDark == dark {
                self.iblEntity.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.9))
            }
        }
        keyLight.components.set(DirectionalLightComponent(color: .white, intensity: isDark ? 1700 : 2600))
        #endif
    }

    /// Returns the image-based lighting environment for the given scheme,
    /// building and caching it on first use. Image-based lighting is optional
    /// (it only adds reflections); if the cubemap can't be built — some
    /// simulators can't — this returns `nil` and the board renders with just
    /// the key light rather than trapping.
    private func ensureEnvironment(dark: Bool) async -> EnvironmentResource? {
        if dark, let darkEnvironment { return darkEnvironment }
        if !dark, let lightEnvironment { return lightEnvironment }
        let image = await Task.detached(priority: .userInitiated) {
            BoardTextureBuilder.environmentEquirect(dark: dark)
        }.value
        guard let image else { return nil }
        do {
            let environment = try await EnvironmentResource(equirectangular: image)
            if dark { darkEnvironment = environment } else { lightEnvironment = environment }
            return environment
        } catch {
            print("Board IBL environment unavailable, continuing without it: \(error)")
            return nil
        }
    }

    /// Portrait (-90°, so player one's store lands at the near/bottom edge)
    /// rotates the physical board to fit the taller viewport. The pass-and-play
    /// flip is handled by the camera orbit, not by spinning the board.
    private func updateBoardOrientation(animated: Bool) {
        let yaw: Float = portrait ? -.pi / 2 : 0
        let transform = Transform(rotation: simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
        if animated {
            boardRoot.move(to: transform, relativeTo: root, duration: 0.45, timingFunction: .easeInOut)
        } else {
            boardRoot.transform = transform
        }
    }

    /// Pass-and-play flip: arc the camera up and over the top of the board to
    /// the opposite player's seat via a single rotation about the world-X axis
    /// (`flipRotation`). Only the camera moves — the board never spins — and it
    /// lands with the identical downward tilt mirrored for the other player. The
    /// sweep is deliberately slow and paired with a mid-arc dolly-out (`flipArc`)
    /// so the motion is unmistakable.
    private func updateCameraOrbit(animated: Bool) {
        #if os(visionOS)
        // No camera to swing; players physically sit on opposite sides.
        return
        #else
        let transform = Transform(rotation: simd_quatf(angle: flipped ? flipRotation : 0, axis: SIMD3(1, 0, 0)))
        if animated {
            let duration = 0.8
            cameraOrbit.move(to: transform, relativeTo: root, duration: duration, timingFunction: .easeInOut)
            animateFlipArc(duration: duration)
        } else {
            cameraOrbit.transform = transform
        }
        #endif
    }

    /// Drives `flipArc` 0 → 1 → 0 across the swing so `updateCamera` pulls the
    /// camera back and lifts it at mid-arc, giving the flip a clear "fly around"
    /// read. Runs alongside the `cameraOrbit` move and composes cleanly with the
    /// live parallax writes (both go through `updateCamera`).
    private func animateFlipArc(duration: Double) {
        flipArcTask?.cancel()
        flipArcTask = Task { [weak self] in
            let steps = 40
            let stepDuration = duration / Double(steps)
            for step in 0...steps {
                if Task.isCancelled { return }
                let t = Float(step) / Float(steps)
                self?.flipArc = sin(t * .pi)
                self?.updateCamera()
                try? await Task.sleep(for: .seconds(stepDuration))
            }
            guard let self, !Task.isCancelled else { return }
            self.flipArc = 0
            self.updateCamera()
        }
    }

    // MARK: - Camera

    /// Frame the board for the current viewport and apply the parallax
    /// offsets. Cheap enough to run per motion sample.
    private func updateCamera() {
        #if !os(visionOS)
        let aspect = Float(viewSize.width / max(viewSize.height, 1))
        let vFOV = fieldOfViewDegrees * .pi / 180
        let hFOV = 2 * atan(tan(vFOV / 2) * max(aspect, 0.1))

        // Tight margins so the board fills the viewport and can travel to the
        // real screen edges under parallax rather than clipping short of them.
        let alongScreenX = (portrait ? BoardLayout3D.depth : BoardLayout3D.width) / 2 + 0.012
        let alongScreenY = (portrait ? BoardLayout3D.width : BoardLayout3D.depth) / 2 + 0.045
        // The board lies nearly flat, so its z-extent is foreshortened by the
        // camera pitch when projected to screen-vertical.
        let pitch = -(basePitch)
        let projectedY = alongScreenY * max(sin(pitch), 0.35) + 0.01
        let baseDistance = max(
            alongScreenX / tan(hFOV / 2),
            projectedY / tan(vFOV / 2),
            0.35
        )
        // Mid-flip dolly-out makes the 180° swing read as a deliberate fly-around.
        let distance = baseDistance * boardFillMargin * (1 + 0.22 * flipArc)

        camera.position = SIMD3(0, 0, distance)
        cameraRig.orientation = simd_quatf(angle: parallaxYaw, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: basePitch + parallaxPitch, axis: SIMD3(1, 0, 0))
        #endif
    }

    /// Small smoothed offsets from device motion; the rig orbits the board
    /// center so tilting the device reads as looking around the object.
    func setParallax(yaw: Float, pitch: Float) {
        guard isBuilt else { return }
        parallaxYaw = yaw
        parallaxPitch = pitch
        updateCamera()
    }

    // MARK: - Sowing animation

    /// User-adjustable multiplier for stone flight pace (1 = default);
    /// durations divide by this, so higher is faster.
    @ObservationIgnored var animationSpeed: Double = 1.0

    private func scaled(_ duration: TimeInterval) -> TimeInterval {
        duration / min(max(animationSpeed, 0.25), 4)
    }

    /// Spring parameters for the sowing follower, scaled so the cluster keeps
    /// pace when the user speeds the animation up. Damping sits at ~0.8 of
    /// critical, leaving a slight overshoot that reads as momentum.
    private var springStiffness: Float {
        let speed = Float(min(max(animationSpeed, 0.25), 4))
        return 300 * speed * speed
    }

    private var springDamping: Float {
        let speed = Float(min(max(animationSpeed, 0.25), 4))
        return 33 * speed
    }

    /// The stones currently traveling as the picked-up pile; index 0 is the
    /// bottom-center stone and the next to be released.
    @ObservationIgnored private var sowingCluster: [ModelEntity] = []
    /// Palette index of each cluster stone, parallel to `sowingCluster`.
    @ObservationIgnored private var sowingClusterColors: [Int] = []
    /// Height of the cluster's bottom layer while it floats across the board.
    private let clusterHoverHeight: Float = 0.05

    /// Hex-packed formation offset for the i-th remaining cluster stone:
    /// one center stone and up to six around it per layer, layers stacked.
    private static func clusterOffset(_ index: Int) -> SIMD3<Float> {
        let layer = index / 7
        let slot = index % 7
        let y = Float(layer) * BoardLayout3D.stoneRadius * 1.85
        guard slot > 0 else { return SIMD3(0, y, 0) }
        let angle = Float(slot - 1) * (.pi / 3) + Float(layer) * 0.45
        let radius = BoardLayout3D.stoneRadius * 2.15
        return SIMD3(cos(angle) * radius, y, sin(angle) * radius)
    }

    /// Pick up the pile: spawn one flyer per sown stone on the resting slots
    /// the game model just emptied (so the swap is seamless), then gather
    /// them into a floating clump above the source well.
    func liftSowingCluster(from: Int, count: Int) async {
        guard isBuilt, BoardLayout3D.wells.indices.contains(from), count > 0 else { return }
        for stone in sowingCluster {
            stone.removeFromParent()
        }
        sowingCluster = []
        // Claim the lifted stones' own colors. The model's sync may run before
        // or after this call, so the pit ledger may already have been trimmed —
        // in that case the colors are waiting in the removal stash.
        var lifted = stoneColors[from]
        stoneColors[from] = []
        if lifted.isEmpty {
            lifted = lastRemovedColors[from]
        }
        lastRemovedColors[from] = []
        while lifted.count < count {
            lifted.append(nextFallbackColor())
        }
        sowingClusterColors = Array(lifted.prefix(count))
        for slot in 0..<count {
            let stone = StoneFactory.makeFlyingStone(colorIndex: sowingClusterColors[slot])
            stone.position = BoardLayout3D.stoneSlot(pitIndex: from, slot: slot).position
            stone.components.set(SowingMotionComponent(
                target: stone.position,
                stiffness: springStiffness,
                damping: springDamping
            ))
            boardRoot.addChild(stone)
            sowingCluster.append(stone)
        }
        let well = BoardLayout3D.wells[from]
        moveCluster(over: well)
        try? await Task.sleep(for: .seconds(scaled(0.16)))
    }

    /// Glide the remaining clump over the next well on the path.
    func hopSowingCluster(to wellIndex: Int) async {
        guard isBuilt, BoardLayout3D.wells.indices.contains(wellIndex), !sowingCluster.isEmpty else { return }
        moveCluster(over: BoardLayout3D.wells[wellIndex])
        try? await Task.sleep(for: .seconds(scaled(0.12)))
    }

    /// Release the bottom stone of the clump into `wellIndex`. The caller
    /// then mutates the game model, and the resting stone appears via `sync`.
    /// The survivors re-pack around the gap on the next hop.
    func dropSowingStone(at wellIndex: Int) async {
        guard isBuilt, BoardLayout3D.wells.indices.contains(wellIndex), !sowingCluster.isEmpty else { return }
        let stone = sowingCluster.removeFirst()
        // Queue the dropped stone's color so the resting stone the model sync
        // creates in this pit keeps the same color.
        if !sowingClusterColors.isEmpty {
            pendingDropColors[wellIndex].append(sowingClusterColors.removeFirst())
        }
        // Hand the stone back to a plain animation for the drop so the spring
        // follower stops steering it mid-fall.
        stone.components.remove(SowingMotionComponent.self)
        await landStone(stone, into: wellIndex)
    }

    /// Drop a flyer into `wellIndex` with a gravity fall, a tumble, and one
    /// damped bounce, landing exactly on the slot its resting stone will
    /// occupy. The flyer then waits in `landedFlyers` until `applyStones`
    /// swaps it for the real resting stone in place.
    private func landStone(_ stone: ModelEntity, into wellIndex: Int) async {
        // The slot this stone will occupy once the model deposits it: current
        // logical count plus every drop already queued (its own color was
        // queued just before this call, hence the -1).
        let futureSlot = stoneColors[wellIndex].count + pendingDropColors[wellIndex].count - 1
        guard futureSlot >= 0, futureSlot < BoardLayout3D.visibleStoneCap else {
            // Pile is at its visible cap: fall into its top and vanish; only
            // the count label changes.
            let well = BoardLayout3D.wells[wellIndex]
            let target = Transform(
                scale: stone.transform.scale,
                rotation: stone.transform.rotation,
                translation: SIMD3(well.center.x, 0.012, well.center.y)
            )
            let duration = scaled(0.09)
            stone.move(to: target, relativeTo: boardRoot, duration: duration, timingFunction: .easeIn)
            try? await Task.sleep(for: .seconds(duration))
            stone.removeFromParent()
            return
        }

        let slot = BoardLayout3D.stoneSlot(pitIndex: wellIndex, slot: futureSlot)

        // The stone stays a rigid sphere through the fall and bounce — no
        // rotation or scale change mid-flight, which would morph its
        // silhouette and read as soft.
        let flightScale = stone.transform.scale
        let flightRotation = stone.transform.rotation
        let fall = scaled(0.09)
        stone.move(
            to: Transform(scale: flightScale, rotation: flightRotation, translation: slot.position),
            relativeTo: boardRoot,
            duration: fall,
            timingFunction: .easeIn
        )
        try? await Task.sleep(for: .seconds(fall))

        // One small damped bounce off the bowl, drifting a touch sideways.
        let bounceHeight = BoardLayout3D.stoneRadius * Float.random(in: 0.45...0.7)
        let drift = BoardLayout3D.stoneRadius * 0.18
        let apex = slot.position
            + slot.surfaceNormal * bounceHeight
            + SIMD3(Float.random(in: -drift...drift), 0, Float.random(in: -drift...drift))
        let rise = scaled(0.06)
        stone.move(
            to: Transform(scale: flightScale, rotation: flightRotation, translation: apex),
            relativeTo: boardRoot,
            duration: rise,
            timingFunction: .easeOut
        )
        try? await Task.sleep(for: .seconds(rise))
        // The settle nestles the sphere into its resting pebble shape — the
        // one moment squash is applied, so it reads as coming to rest.
        let settle = scaled(0.07)
        stone.move(
            to: Transform(scale: slot.scale, rotation: slot.orientation, translation: slot.position),
            relativeTo: boardRoot,
            duration: settle,
            timingFunction: .easeIn
        )
        try? await Task.sleep(for: .seconds(settle))
        landedFlyers[wellIndex].append(stone)
    }

    /// Retarget the spring follower on every cluster stone. Per-hop wobble
    /// keeps the clump reading as loose stones in hand; the spring turns each
    /// retarget into a drift rather than a snap. Wobble stays well under half
    /// the formation spacing so stones never visibly interpenetrate.
    private func moveCluster(over well: BoardLayout3D.Well) {
        let center = SIMD3(well.center.x, clusterHoverHeight, well.center.y)
        // Small enough that wobbled targets stay outside contact range; the
        // separation pass in `SowingMotionSystem` catches transients.
        let jitter = BoardLayout3D.stoneRadius * 0.12
        for (index, stone) in sowingCluster.enumerated() {
            guard var motion = stone.components[SowingMotionComponent.self] else { continue }
            let wobble = SIMD3(
                Float.random(in: -jitter...jitter),
                Float.random(in: -jitter * 0.6...jitter * 0.6),
                Float.random(in: -jitter...jitter)
            )
            motion.target = center + Self.clusterOffset(index) + wobble
            motion.stiffness = springStiffness
            motion.damping = springDamping
            stone.components.set(motion)
        }
    }

    /// Fly one stone from `from` to `to` along a low arc (used for capture
    /// sweeps). The caller removes the stone from the model first and deposits
    /// it after; the flyer claims that stone's own color from the ledger (or
    /// the removal stash if the sync already trimmed it) and queues it for the
    /// destination so the color survives the trip.
    func flyStone(from: Int, to: Int) async {
        guard isBuilt,
              BoardLayout3D.wells.indices.contains(from),
              BoardLayout3D.wells.indices.contains(to) else {
            return
        }
        // `popLast` (not check-then-`removeLast`) so a re-entrant `sync` that
        // trims the ledger between the check and the removal can never turn
        // this into an empty-collection trap — it just falls through.
        let color = lastRemovedColors[from].popLast()
            ?? stoneColors[from].popLast()
            ?? nextFallbackColor()
        pendingDropColors[to].append(color)

        let source = BoardLayout3D.wells[from].center
        let destination = BoardLayout3D.wells[to].center
        let start = SIMD3(source.x, 0.016, source.y)
        let end = SIMD3(destination.x, 0.012, destination.y)
        let apex = (start + end) / 2 + SIMD3(0, 0.055, 0)

        let stone = StoneFactory.makeFlyingStone(colorIndex: color)
        stone.position = start
        boardRoot.addChild(stone)

        let scale = stone.transform.scale
        let rotation = stone.transform.rotation
        let phaseDuration = scaled(0.10)
        stone.move(
            to: Transform(scale: scale, rotation: rotation, translation: apex),
            relativeTo: boardRoot,
            duration: phaseDuration,
            timingFunction: .easeOut
        )
        try? await Task.sleep(for: .seconds(phaseDuration))
        await landStone(stone, into: to)
    }
}
