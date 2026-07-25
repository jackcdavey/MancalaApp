import CoreGraphics
import Foundation
import simd

/// Deterministic pseudo-random generator so per-stone squash, rotation, and
/// scatter jitter are stable for a given (pit, slot) across the whole session.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unitFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}

/// Scene-space description of the carved mancala board. Units are meters,
/// the top face of the slab is the y = 0 plane, +x runs along the board's
/// long axis (player one's store at +x), and +z is toward player one.
///
/// This is the single source of truth shared by the mesh builder, the
/// texture baker (ambient-occlusion bake), stone placement, and tap targets.
enum BoardLayout3D {
    static let width: Float = 0.66
    static let depth: Float = 0.28
    static let thickness: Float = 0.045
    static let cornerRadius: Float = 0.03

    static let pitRadius: Float = 0.036
    static let pitDepth: Float = 0.020
    static let pitSpacingX: Float = 0.082
    static let pitRowZ: Float = 0.062
    static let storeRadius: Float = 0.038
    static let storeDepth: Float = 0.022
    static let storeX: Float = 0.284
    static let storeHalfLength: Float = 0.058

    static let stoneRadius: Float = 0.0105
    /// Beyond this many stones a well stops adding visible stones; the count
    /// label carries the truth (the 2D board similarly caps at 18).
    static let visibleStoneCap = 24

    static var maxWellDepth: Float { max(pitDepth, storeDepth) }

    struct Well {
        /// Center in the top-face plane (x, z).
        let center: SIMD2<Float>
        /// Half-length of the capsule axis along z. Zero for circular pits.
        let axisHalfLength: Float
        let radius: Float
        let depth: Float
    }

    /// Indexed 0...13 to match `MancalaGame.pits`:
    /// 0–5 player one pits (near row, +z, left to right),
    /// 6 player one store (right end),
    /// 7–12 player two pits (far row, -z, right to left — sowing order),
    /// 13 player two store (left end).
    static let wells: [Well] = {
        var wells: [Well] = []
        for i in 0..<6 {
            let x = -pitSpacingX * 2.5 + pitSpacingX * Float(i)
            wells.append(Well(center: [x, pitRowZ], axisHalfLength: 0, radius: pitRadius, depth: pitDepth))
        }
        wells.append(Well(center: [storeX, 0], axisHalfLength: storeHalfLength, radius: storeRadius, depth: storeDepth))
        for i in 0..<6 {
            let x = pitSpacingX * 2.5 - pitSpacingX * Float(i)
            wells.append(Well(center: [x, -pitRowZ], axisHalfLength: 0, radius: pitRadius, depth: pitDepth))
        }
        wells.append(Well(center: [-storeX, 0], axisHalfLength: storeHalfLength, radius: storeRadius, depth: storeDepth))
        return wells
    }()

    /// Distance from `p` to the well's center (pits) or axis segment
    /// (stores), normalized so 1 lands exactly on the rim.
    static func normalizedDistance(_ p: SIMD2<Float>, to well: Well) -> Float {
        var d = p - well.center
        d.y -= min(max(d.y, -well.axisHalfLength), well.axisHalfLength)
        return simd_length(d) / well.radius
    }

    /// Carve depth contributed by one well: a cos² bowl, so the profile is
    /// C1-continuous (zero slope) at the rim and spherical-ish at the center.
    static func depth(at p: SIMD2<Float>, of well: Well) -> Float {
        let q = normalizedDistance(p, to: well)
        guard q < 1 else { return 0 }
        let c = cos(q * Float.pi / 2)
        return well.depth * c * c
    }

    /// Total carve depth at `p`. Wells never overlap, so max is exact.
    static func wellDepth(at p: SIMD2<Float>) -> Float {
        var deepest: Float = 0
        for well in wells {
            // Cheap reject before the exact distance test.
            let reach = well.radius + well.axisHalfLength
            if abs(p.x - well.center.x) > reach || abs(p.y - well.center.y) > reach {
                continue
            }
            deepest = max(deepest, depth(at: p, of: well))
        }
        return deepest
    }

    /// Top-surface height (y): 0 on the flat face, negative inside wells.
    static func height(at p: SIMD2<Float>) -> Float {
        -wellDepth(at: p)
    }

    /// Smooth-shading normal from central differences of the analytic height
    /// field, so shading quality is independent of mesh tessellation.
    static func surfaceNormal(at p: SIMD2<Float>, eps: Float = 0.0012) -> SIMD3<Float> {
        let hx = height(at: p + SIMD2(eps, 0)) - height(at: p - SIMD2(eps, 0))
        let hz = height(at: p + SIMD2(0, eps)) - height(at: p - SIMD2(0, eps))
        return simd_normalize(SIMD3(-hx / (2 * eps), 1, -hz / (2 * eps)))
    }

    // MARK: - Stone placement

    struct StoneSlot {
        /// Resting position of the stone's center, in board space.
        let position: SIMD3<Float>
        let scale: SIMD3<Float>
        let orientation: simd_quatf
        /// Bowl surface directly below the stone, for contact shadows.
        let surfaceY: Float
        let surfaceNormal: SIMD3<Float>
    }

    /// Deterministic resting slot for stone number `slot` in well `pitIndex`.
    /// Slots use a golden-angle spiral so adding stone k never moves stones
    /// 0..<k (same stability property as the 2D board's scatter table).
    static func stoneSlot(pitIndex: Int, slot: Int) -> StoneSlot {
        let well = wells[pitIndex]
        let isStore = well.axisHalfLength > 0
        let layerCapacity = isStore ? 16 : 9
        let layer = slot / layerCapacity
        let indexInLayer = slot % layerCapacity

        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(pitIndex &* 7919 &+ slot &* 977 &+ 131)))
        let goldenAngle: Float = 2.3999632
        let theta = Float(indexInLayer) * goldenAngle
            + Float(pitIndex) * 1.71
            + Float(layer) * 0.9
            + rng.unitFloat() * 0.45
        let spread = well.radius * 0.62
        let radial = spread * sqrt((Float(indexInLayer) + 0.5) / Float(layerCapacity))
        var offset = SIMD2<Float>(cos(theta), sin(theta)) * radial
        if isStore {
            // Stretch the spiral lengthwise so store stones fill the trough.
            offset.y *= (well.axisHalfLength + spread) / spread
        }

        let p = well.center + offset
        let squashY = 0.66 + rng.unitFloat() * 0.14
        let scaleX = 0.92 + rng.unitFloat() * 0.20
        let scaleZ = 0.92 + rng.unitFloat() * 0.20
        let yaw = rng.unitFloat() * 2 * Float.pi

        let surfaceY = height(at: p)
        let restY = surfaceY
            + stoneRadius * squashY * 0.85
            + Float(layer) * stoneRadius * 1.25

        return StoneSlot(
            position: SIMD3(p.x, restY, p.y),
            scale: SIMD3(scaleX, squashY, scaleZ),
            orientation: simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)),
            surfaceY: surfaceY,
            surfaceNormal: surfaceNormal(at: p)
        )
    }
}
