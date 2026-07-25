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
    /// Same palette as the 2D board's `stoneColor(for:)`.
    static let palette: [SIMD3<Float>] = [
        SIMD3(0.13, 0.42, 0.92), // blue
        SIMD3(0.95, 0.55, 0.16), // orange
        SIMD3(0.14, 0.62, 0.56), // teal
        SIMD3(0.84, 0.22, 0.34), // red
        SIMD3(0.55, 0.42, 0.86)  // purple
    ]

    /// Soft darkening disc under each resting stone. Baked AO plus the
    /// directional shadow usually suffice; flip this off if it reads heavy.
    static let useContactShadowDiscs = true

    private static var sphereMesh: MeshResource?
    private static var discMesh: MeshResource?
    private static var materials: [PhysicallyBasedMaterial] = []
    private static var discMaterial: UnlitMaterial?

    static func prepare() {
        guard sphereMesh == nil else { return }
        sphereMesh = .generateSphere(radius: BoardLayout3D.stoneRadius)

        let discDiameter = BoardLayout3D.stoneRadius * 2.4
        discMesh = .generatePlane(width: discDiameter, depth: discDiameter, cornerRadius: discDiameter / 2)

        materials = palette.map { rgb in
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: PlatformColor(
                red: CGFloat(rgb.x),
                green: CGFloat(rgb.y),
                blue: CGFloat(rgb.z),
                alpha: 1
            ))
            material.roughness = 0.06
            material.metallic = 0.0
            material.specular = 1.0
            material.clearcoat = 1.0
            material.clearcoatRoughness = 0.08
            // A hint of translucency reads as glass; true refraction isn't
            // available in PhysicallyBasedMaterial.
            material.blending = .transparent(opacity: .init(floatLiteral: 0.94))
            material.faceCulling = .back
            return material
        }

        var disc = UnlitMaterial(color: PlatformColor.black)
        disc.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        discMaterial = disc
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
