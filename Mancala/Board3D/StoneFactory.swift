import RealityKit
import simd

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformColor = NSColor
#endif

/// Builds the glass gem stones: one shared sphere mesh, five shared
/// physically-based glass materials matching the app's stone palette, and
/// deterministic per-slot placement so piles never reshuffle.
@MainActor
enum StoneFactory {
    /// Name given to the sphere inside each stone container, so a set change
    /// can find it again without relying on child order.
    static let modelName = "stone-model"

    /// The set every stone is currently built from. `BoardScene` drives this
    /// through `apply(set:)`; nothing else should write it.
    private(set) static var activeSet: StoneSetStyle = .classic

    /// Soft darkening disc under each resting stone. Baked AO plus the
    /// directional shadow usually suffice; flip this off if it reads heavy.
    static let useContactShadowDiscs = true

    private static var sphereMesh: MeshResource?
    private static var discMesh: MeshResource?
    private static var materials: [PhysicallyBasedMaterial] = []
    private static var discMaterial: UnlitMaterial?

    /// Switches sets and drops the cached materials. Returns true when
    /// something actually changed, so the caller knows whether it needs to
    /// re-skin the stones already on the board.
    @discardableResult
    static func apply(set style: StoneSetStyle) -> Bool {
        guard style != activeSet || materials.isEmpty else { return false }
        activeSet = style
        materials = []
        prepare()
        return true
    }

    static func prepare() {
        // Meshes are set-independent, so they're built once; materials are
        // rebuilt whenever `apply(set:)` has cleared them.
        if sphereMesh == nil {
            sphereMesh = .generateSphere(radius: BoardLayout3D.stoneRadius)

            let discDiameter = BoardLayout3D.stoneRadius * 2.4
            discMesh = .generatePlane(width: discDiameter, depth: discDiameter, cornerRadius: discDiameter / 2)

            var disc = UnlitMaterial(color: PlatformColor.black)
            disc.blending = .transparent(opacity: .init(floatLiteral: 0.22))
            discMaterial = disc
        }

        guard materials.isEmpty else { return }

        let finish = activeSet.finish
        materials = activeSet.tints.map { tint in
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: PlatformColor(
                red: CGFloat(tint.red),
                green: CGFloat(tint.green),
                blue: CGFloat(tint.blue),
                alpha: 1
            ))
            material.roughness = .init(floatLiteral: finish.roughness)
            material.metallic = .init(floatLiteral: finish.metallic)
            material.specular = 1.0
            material.clearcoat = .init(floatLiteral: finish.clearcoat)
            material.clearcoatRoughness = .init(floatLiteral: finish.clearcoatRoughness)
            // Below 1 reads as glass; true refraction isn't available in
            // PhysicallyBasedMaterial.
            material.blending = .transparent(opacity: .init(floatLiteral: finish.opacity))
            material.faceCulling = .back
            return material
        }
    }

    /// Re-skins a stone container built by `makeRestingStone` — used when the
    /// set changes under stones that are already on the board, which is
    /// cheaper and less disruptive than tearing them down and regrowing them.
    static func reskin(_ container: Entity, colorIndex: Int) {
        prepare()
        guard let model = container.findEntity(named: modelName) as? ModelEntity else { return }
        model.model?.materials = [material(forColorIndex: colorIndex)]
    }

    static func material(forColorIndex index: Int) -> PhysicallyBasedMaterial {
        prepare()
        return materials[((index % materials.count) + materials.count) % materials.count]
    }

    /// A stone resting in its deterministic slot. The returned container is
    /// axis-aligned at the slot position; squash/rotation live on the child
    /// model so the contact-shadow disc stays flat against the bowl.
    /// `colorIndex` is the stone's own persistent color, tracked by the
    /// scene's ledger — never derived from the slot, so a stone keeps its
    /// color no matter which pile position it lands in.
    static func makeRestingStone(pitIndex: Int, slot: Int, colorIndex: Int) -> Entity {
        prepare()
        guard let sphereMesh else { return Entity() }

        let slotInfo = BoardLayout3D.stoneSlot(pitIndex: pitIndex, slot: slot)
        let container = Entity()
        container.position = slotInfo.position

        let model = ModelEntity(mesh: sphereMesh, materials: [material(forColorIndex: colorIndex)])
        model.name = modelName
        model.scale = slotInfo.scale
        model.orientation = slotInfo.orientation
        container.addChild(model)

        if useContactShadowDiscs, let discMesh, let discMaterial {
            let disc = ModelEntity(mesh: discMesh, materials: [discMaterial])
            disc.position = SIMD3(0, slotInfo.surfaceY - slotInfo.position.y + 0.0008, 0)
            disc.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: slotInfo.surfaceNormal)
            container.addChild(disc)
        }
        return container
    }

    /// The transient stone that arcs between wells during sowing/capture.
    /// Uniformly scaled on purpose: a rotating non-uniform ellipsoid changes
    /// silhouette every frame and reads as soft, while a sphere stays rigid
    /// under any rotation. The landing settle morphs it into its resting
    /// squash at the end.
    static func makeFlyingStone(colorIndex: Int) -> ModelEntity {
        prepare()
        guard let sphereMesh else { return ModelEntity() }
        return ModelEntity(mesh: sphereMesh, materials: [material(forColorIndex: colorIndex)])
    }
}
