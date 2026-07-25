import RealityKit
import simd

/// Builds the procedural geometry for the 3D board: the carved slab and the
/// highlight rings that outline playable/hinted wells. All heavy vertex work
/// happens in plain arrays so it can run off the main actor; only the final
/// `MeshResource` creation touches RealityKit.
enum BoardMeshBuilder {
    struct MeshData: Sendable {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
    }

    static func descriptor(from data: MeshData, name: String) -> MeshDescriptor {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(data.positions)
        descriptor.normals = MeshBuffer(data.normals)
        descriptor.textureCoordinates = MeshBuffer(data.uvs)
        descriptor.primitives = .triangles(data.indices)
        return descriptor
    }

    // MARK: - Slab

    /// Half-width of the rounded-rectangle footprint at a given z, so grid
    /// rows conform exactly to the outline (no cracks against the skirt).
    static func halfWidth(atZ z: Float) -> Float {
        let halfW = BoardLayout3D.width / 2
        let halfD = BoardLayout3D.depth / 2
        let r = BoardLayout3D.cornerRadius
        let intoCorner = abs(z) - (halfD - r)
        guard intoCorner > 0 else { return halfW }
        let dz = min(intoCorner, r)
        return halfW - r + sqrt(max(0, r * r - dz * dz))
    }

    /// Outward outline normal of the rounded rectangle at boundary point `p`.
    private static func outlineNormal(at p: SIMD2<Float>) -> SIMD2<Float> {
        let halfW = BoardLayout3D.width / 2
        let halfD = BoardLayout3D.depth / 2
        let r = BoardLayout3D.cornerRadius
        let inner = SIMD2<Float>(
            min(max(p.x, -(halfW - r)), halfW - r),
            min(max(p.y, -(halfD - r)), halfD - r)
        )
        let d = p - inner
        let len = simd_length(d)
        guard len > 1e-6 else { return SIMD2(0, p.y >= 0 ? 1 : -1) }
        return d / len
    }

    /// The carved slab: displaced top grid + extruded skirt + bottom cap.
    static func slabMeshData(columns: Int = 220, rows: Int = 100) -> MeshData {
        var data = MeshData()
        let width = BoardLayout3D.width
        let depth = BoardLayout3D.depth
        let thickness = BoardLayout3D.thickness

        // Top surface: boundary-conforming grid, heights and normals from the
        // analytic field so pit rims shade smoothly at any tessellation.
        for row in 0...rows {
            let tz = Float(row) / Float(rows)
            let z = (tz - 0.5) * depth
            let hw = halfWidth(atZ: z)
            for column in 0...columns {
                let tx = Float(column) / Float(columns)
                let x = (tx - 0.5) * 2 * hw
                let p = SIMD2<Float>(x, z)
                data.positions.append(SIMD3(x, BoardLayout3D.height(at: p), z))
                data.normals.append(BoardLayout3D.surfaceNormal(at: p))
                data.uvs.append(SIMD2(x / width + 0.5, z / depth + 0.5))
            }
        }
        let stride = UInt32(columns + 1)
        for row in 0..<rows {
            for column in 0..<columns {
                let a = UInt32(row) * stride + UInt32(column)
                let b = a + 1
                let c = a + stride
                let d = c + 1
                data.indices.append(contentsOf: [a, d, b, a, c, d])
            }
        }

        // Perimeter loop of the top grid, in order: far edge (+x direction),
        // right edge, near edge (-x direction), left edge.
        var loop: [SIMD2<Float>] = []
        func gridPoint(_ column: Int, _ row: Int) -> SIMD2<Float> {
            let v = data.positions[row * (columns + 1) + column]
            return SIMD2(v.x, v.z)
        }
        for column in 0...columns { loop.append(gridPoint(column, 0)) }
        for row in 1...rows { loop.append(gridPoint(columns, row)) }
        for column in std_reversed(0...(columns - 1)) { loop.append(gridPoint(column, rows)) }
        for row in std_reversed(1...(rows - 1)) { loop.append(gridPoint(0, row)) }

        // Skirt: the loop extruded down, duplicated vertices so the top edge
        // stays crisp while the outline itself shades smoothly around corners.
        let skirtBase = UInt32(data.positions.count)
        for p in loop {
            let n = outlineNormal(at: p)
            let normal3 = SIMD3(n.x, 0, n.y)
            let u = (p.x / width + 0.5) * 0.999
            data.positions.append(SIMD3(p.x, 0, p.y))
            data.normals.append(normal3)
            data.uvs.append(SIMD2(u, 0.001))
            data.positions.append(SIMD3(p.x, -thickness, p.y))
            data.normals.append(normal3)
            data.uvs.append(SIMD2(u, 0.12))
        }
        let loopCount = UInt32(loop.count)
        for k in 0..<loopCount {
            let next = (k + 1) % loopCount
            let top0 = skirtBase + k * 2
            let bottom0 = top0 + 1
            let top1 = skirtBase + next * 2
            let bottom1 = top1 + 1
            data.indices.append(contentsOf: [top0, bottom1, bottom0, top0, top1, bottom1])
        }

        // Bottom cap: fan from the center (the rounded rect is convex).
        let bottomBase = UInt32(data.positions.count)
        data.positions.append(SIMD3(0, -thickness, 0))
        data.normals.append(SIMD3(0, -1, 0))
        data.uvs.append(SIMD2(0.5, 0.5))
        for p in loop {
            data.positions.append(SIMD3(p.x, -thickness, p.y))
            data.normals.append(SIMD3(0, -1, 0))
            data.uvs.append(SIMD2(p.x / width + 0.5, p.y / depth + 0.5))
        }
        for k in 0..<loopCount {
            let next = (k + 1) % loopCount
            data.indices.append(contentsOf: [bottomBase, bottomBase + 1 + k, bottomBase + 1 + next])
        }

        return data
    }

    static func slabMesh() async throws -> MeshResource {
        let data = await Task.detached(priority: .userInitiated) {
            slabMeshData()
        }.value
        return try await MeshResource(from: [descriptor(from: data, name: "boardSlab")])
    }

    // MARK: - Highlight rings

    /// Outline of a well scaled by `scale` (1 = the rim), sampled with a
    /// fixed segment structure so inner/outer rings pair up one-to-one.
    private static func wellOutline(_ well: BoardLayout3D.Well, scale: Float) -> [SIMD2<Float>] {
        let r = well.radius * scale
        let halfLength = well.axisHalfLength
        var points: [SIMD2<Float>] = []
        let arcSegments = 24
        let edgeSegments = halfLength > 0 ? 12 : 0

        for k in 0..<arcSegments {
            let phi = Float(k) / Float(arcSegments) * Float.pi
            points.append(well.center + SIMD2(r * cos(phi), halfLength + r * sin(phi)))
        }
        for k in 0..<edgeSegments {
            let t = Float(k) / Float(edgeSegments)
            points.append(well.center + SIMD2(-r, halfLength - 2 * halfLength * t))
        }
        for k in 0..<arcSegments {
            let phi = Float.pi + Float(k) / Float(arcSegments) * Float.pi
            points.append(well.center + SIMD2(r * cos(phi), -halfLength + r * sin(phi)))
        }
        for k in 0..<edgeSegments {
            let t = Float(k) / Float(edgeSegments)
            points.append(well.center + SIMD2(r, -halfLength + 2 * halfLength * t))
        }
        return points
    }

    /// A thin annulus straddling the well rim, draped over the carved surface
    /// and lifted slightly to avoid z-fighting. Rendered unlit + double-sided,
    /// positioned in board space (vertices are absolute, entity sits at origin).
    static func ringMeshData(
        around well: BoardLayout3D.Well,
        innerScale: Float = 0.90,
        outerScale: Float = 1.07,
        lift: Float = 0.0014
    ) -> MeshData {
        var data = MeshData()
        let inner = wellOutline(well, scale: innerScale)
        let outer = wellOutline(well, scale: outerScale)
        let count = inner.count

        for k in 0..<count {
            for p in [inner[k], outer[k]] {
                data.positions.append(SIMD3(p.x, BoardLayout3D.height(at: p) + lift, p.y))
                data.normals.append(SIMD3(0, 1, 0))
                data.uvs.append(SIMD2(0, 0))
            }
        }
        for k in 0..<UInt32(count) {
            let next = (k + 1) % UInt32(count)
            let i0 = k * 2
            let o0 = i0 + 1
            let i1 = next * 2
            let o1 = i1 + 1
            data.indices.append(contentsOf: [i0, o0, o1, i0, o1, i1])
        }
        return data
    }

    static func ringMesh(around well: BoardLayout3D.Well) async throws -> MeshResource {
        try await MeshResource(from: [descriptor(from: ringMeshData(around: well), name: "highlightRing")])
    }
}

/// `(0...n).reversed()` with a type Swift's inference keeps simple.
private func std_reversed(_ range: ClosedRange<Int>) -> [Int] {
    Array(range.reversed())
}
