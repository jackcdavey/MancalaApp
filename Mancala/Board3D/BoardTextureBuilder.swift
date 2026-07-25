import CoreGraphics
import Foundation
import simd

/// Generates the board's textures procedurally at launch (the app ships no
/// image assets for the 3D board): a walnut wood-grain base color with the
/// wells' ambient occlusion baked in, and a small equirectangular environment
/// image used for image-based lighting so the glass stones pick up bright
/// window-like reflections.
enum BoardTextureBuilder {
    // MARK: - Value noise

    private struct ValueNoise {
        private var permutation: [Int]

        init(seed: UInt64) {
            var table = Array(0..<256)
            var rng = SplitMix64(seed: seed)
            for i in (1..<256).reversed() {
                let j = Int(rng.next() % UInt64(i + 1))
                table.swapAt(i, j)
            }
            permutation = table + table
        }

        private func lattice(_ x: Int, _ y: Int) -> Float {
            Float(permutation[(permutation[x & 255] + y) & 255]) / 255
        }

        func noise(_ x: Float, _ y: Float) -> Float {
            let x0 = Int(floor(x)), y0 = Int(floor(y))
            let fx = x - floor(x), fy = y - floor(y)
            let sx = fx * fx * (3 - 2 * fx)
            let sy = fy * fy * (3 - 2 * fy)
            let n00 = lattice(x0, y0), n10 = lattice(x0 + 1, y0)
            let n01 = lattice(x0, y0 + 1), n11 = lattice(x0 + 1, y0 + 1)
            let a = n00 + (n10 - n00) * sx
            let b = n01 + (n11 - n01) * sx
            return a + (b - a) * sy
        }

        func fbm(_ x: Float, _ y: Float, octaves: Int = 3) -> Float {
            var total: Float = 0
            var amplitude: Float = 0.5
            var fx = x, fy = y
            for _ in 0..<octaves {
                total += noise(fx, fy) * amplitude
                fx *= 2.03
                fy *= 2.03
                amplitude *= 0.5
            }
            return total
        }
    }

    /// Coarse pre-sampled copy of the well depth field: ambient occlusion is
    /// low-frequency, and sampling a grid keeps the 2M-texel bake fast.
    private struct DepthField {
        let columns: Int
        let rows: Int
        let values: [Float]

        init(columns: Int = 512, rows: Int = 256) {
            self.columns = columns
            self.rows = rows
            var values = [Float](repeating: 0, count: (columns + 1) * (rows + 1))
            for row in 0...rows {
                let z = (Float(row) / Float(rows) - 0.5) * BoardLayout3D.depth
                for column in 0...columns {
                    let x = (Float(column) / Float(columns) - 0.5) * BoardLayout3D.width
                    values[row * (columns + 1) + column] = BoardLayout3D.wellDepth(at: SIMD2(x, z))
                }
            }
            self.values = values
        }

        /// Bilinear depth sample; u, v in [0, 1] over the board footprint.
        func depth(u: Float, v: Float) -> Float {
            let fx = min(max(u, 0), 1) * Float(columns)
            let fy = min(max(v, 0), 1) * Float(rows)
            let x0 = min(Int(fx), columns - 1), y0 = min(Int(fy), rows - 1)
            let sx = fx - Float(x0), sy = fy - Float(y0)
            let stride = columns + 1
            let n00 = values[y0 * stride + x0], n10 = values[y0 * stride + x0 + 1]
            let n01 = values[(y0 + 1) * stride + x0], n11 = values[(y0 + 1) * stride + x0 + 1]
            let a = n00 + (n10 - n00) * sx
            let b = n01 + (n11 - n01) * sx
            return a + (b - a) * sy
        }

        /// Magnitude of the depth gradient, for rim darkening.
        func gradientMagnitude(u: Float, v: Float) -> Float {
            let du: Float = 1.5 / Float(columns)
            let dv: Float = 1.5 / Float(rows)
            let gx = (depth(u: u + du, v: v) - depth(u: u - du, v: v)) / (2 * du * BoardLayout3D.width)
            let gz = (depth(u: u, v: v + dv) - depth(u: u, v: v - dv)) / (2 * dv * BoardLayout3D.depth)
            return sqrt(gx * gx + gz * gz)
        }
    }

    /// Ambient occlusion is low-frequency and identical for every finish, so the
    /// depth field is sampled once and shared across all base-color bakes rather
    /// than rebuilt each time a material is generated.
    private static let sharedDepthField = DepthField()

    private static func makeCGImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    // MARK: - Board base color with baked ambient occlusion

    /// Tunable look for the two wood finishes; the same generator produces both.
    private struct WoodPalette {
        let light: SIMD3<Float>
        let dark: SIMD3<Float>
        /// Ring frequency along the short axis (higher = tighter grain).
        let ringFrequency: Float
        /// How much the grain wanders sideways.
        let waveStrength: Float
        /// Baseline lightness offset; higher reads as paler, straighter wood.
        let mixBias: Float
        /// Amplitude of the fine cross-grain streaking.
        let streakStrength: Float
    }

    /// The board mesh uses a planar UV map of the same (x, z) domain as the
    /// well depth field, so multiplying occlusion into the base color here
    /// gives physically plausible soft shadowing inside every pit with zero
    /// custom shader work.
    ///
    /// The grain's crispness comes from the high-frequency detail baked into the
    /// generator (see `woodBaseColor`), not raw pixel count, so a 2048×1024 bake
    /// reads sharp while staying cheap enough to keep launch and material swaps
    /// responsive.
    static func baseColor(for style: BoardMaterialStyle, width: Int = 2048, height: Int = 1024) -> CGImage? {
        switch style {
        case .walnut:
            return woodBaseColor(
                palette: WoodPalette(
                    light: SIMD3(0.52, 0.345, 0.205),
                    dark: SIMD3(0.32, 0.195, 0.108),
                    ringFrequency: 300,
                    waveStrength: 8,
                    mixBias: 0.12,
                    streakStrength: 0.18
                ),
                width: width, height: height
            )
        case .maple:
            return woodBaseColor(
                palette: WoodPalette(
                    light: SIMD3(0.88, 0.78, 0.60),
                    dark: SIMD3(0.70, 0.575, 0.395),
                    ringFrequency: 220,
                    waveStrength: 4,
                    mixBias: 0.30,
                    streakStrength: 0.13
                ),
                width: width, height: height
            )
        case .marble:
            return marbleBaseColor(width: width, height: height)
        case .slate:
            return slateBaseColor(width: width, height: height)
        case .frostedGlass:
            return frostedGlassBaseColor(width: width, height: height)
        }
    }

    private static func woodBaseColor(palette: WoodPalette, width: Int, height: Int) -> CGImage? {
        let grainNoise = ValueNoise(seed: 0xB0A2D)
        let streakNoise = ValueNoise(seed: 0x5EED5)
        let fineNoise = ValueNoise(seed: 0xC1A55)
        let field = sharedDepthField
        let maxDepth = BoardLayout3D.maxWellDepth

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)
            let pz = (v - 0.5) * BoardLayout3D.depth
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                let px = (u - 0.5) * BoardLayout3D.width

                // Grain lines run along the board's long axis: rings vary
                // across z, waviness driven by noise along x.
                let wave = grainNoise.fbm(px * 9, pz * 40) * palette.waveStrength
                let ring = sin(pz * palette.ringFrequency + wave)
                // A finer secondary ring set inserts crisp sub-grain between the
                // main lines so the wood doesn't read as a few soft bands.
                let fineRing = sin(pz * palette.ringFrequency * 2.7 + wave * 1.3)
                var bands = powf(ring * 0.5 + 0.5, 1.5) * 0.82
                    + powf(fineRing * 0.5 + 0.5, 3.0) * 0.18
                // Sharpen the tonal transition so grain lines read crisp.
                bands = min(max((bands - 0.5) * 1.35 + 0.5, 0), 1)
                let fineStreak = (streakNoise.fbm(px * 10, pz * 240) - 0.5) * palette.streakStrength
                // Crisp high-frequency pore detail so the grain doesn't read soft.
                let pores = (fineNoise.fbm(px * 40, pz * 520, octaves: 2) - 0.5) * 0.10
                let drift = (grainNoise.fbm(px * 3 + 40, pz * 3) - 0.5) * 0.12
                var color = simd_mix(
                    palette.light,
                    palette.dark,
                    SIMD3(repeating: min(max(bands * 0.62 + fineStreak + pores + drift + palette.mixBias, 0), 1))
                )

                color *= bakedAO(field: field, u: u, v: v, maxDepth: maxDepth)

                writePixel(&pixels, x: x, y: y, width: width, color: color)
            }
        }
        return makeCGImage(pixels: pixels, width: width, height: height)
    }

    /// Polished marble: near-white base crossed by thin veins carved with
    /// domain-warped `sin` turbulence.
    private static func marbleBaseColor(width: Int, height: Int) -> CGImage? {
        let warpNoise = ValueNoise(seed: 0x9A12B)
        let mottleNoise = ValueNoise(seed: 0x33F0D)
        let field = sharedDepthField
        let maxDepth = BoardLayout3D.maxWellDepth

        let base = SIMD3<Float>(0.90, 0.905, 0.925)
        let vein = SIMD3<Float>(0.34, 0.35, 0.40)

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)
            let pz = (v - 0.5) * BoardLayout3D.depth
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                let px = (u - 0.5) * BoardLayout3D.width

                let warp = warpNoise.fbm(px * 5, pz * 5, octaves: 5) * 6
                let m = sin((px * 26 + pz * 12) + warp)
                // |m| ≈ 0 along the vein centres → dark, thin lines.
                let veinMix = 1 - powf(min(abs(m), 1), 0.32)
                let mottle = (mottleNoise.fbm(px * 3, pz * 3) - 0.5) * 0.05
                var color = simd_mix(base, vein, SIMD3(repeating: min(max(veinMix * 0.85, 0), 1)))
                color += SIMD3(repeating: mottle)

                color *= bakedAO(field: field, u: u, v: v, maxDepth: maxDepth)

                writePixel(&pixels, x: x, y: y, width: width, color: color)
            }
        }
        return makeCGImage(pixels: pixels, width: width, height: height)
    }

    /// Matte slate: dark, low-contrast stone with subtle cloudy mottling and
    /// faint lighter flecks.
    private static func slateBaseColor(width: Int, height: Int) -> CGImage? {
        let cloudNoise = ValueNoise(seed: 0x5171E)
        let fleckNoise = ValueNoise(seed: 0x7EC24)
        let field = sharedDepthField
        let maxDepth = BoardLayout3D.maxWellDepth

        let base = SIMD3<Float>(0.155, 0.170, 0.190)

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)
            let pz = (v - 0.5) * BoardLayout3D.depth
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                let px = (u - 0.5) * BoardLayout3D.width

                let cloud = (cloudNoise.fbm(px * 6, pz * 6, octaves: 4) - 0.5) * 0.09
                let fleck = max(fleckNoise.fbm(px * 40, pz * 40, octaves: 2) - 0.62, 0) * 0.22
                var color = base + SIMD3(repeating: cloud + fleck)

                color *= bakedAO(field: field, u: u, v: v, maxDepth: maxDepth)

                writePixel(&pixels, x: x, y: y, width: width, color: color)
            }
        }
        return makeCGImage(pixels: pixels, width: width, height: height)
    }

    /// Frosted glass: a cool, milky pale-blue base with soft diffuse mottling
    /// (the sand-blasted look). The PBR spec in `BoardScene` pairs this with a
    /// translucent blend and a glossy clearcoat; the baked well AO keeps the pits
    /// reading as carved even through the translucency.
    private static func frostedGlassBaseColor(width: Int, height: Int) -> CGImage? {
        let cloudNoise = ValueNoise(seed: 0x6F203)
        let speckNoise = ValueNoise(seed: 0x1CE55)
        let field = sharedDepthField
        let maxDepth = BoardLayout3D.maxWellDepth

        // Kept well below white: the app background behind the RealityView is
        // a flat cream, so the translucent blend in `BoardScene` shows mostly
        // that — the tint has to be saturated enough to survive the blend and
        // the specular wash, or the slab reads as solid white.
        let base = SIMD3<Float>(0.44, 0.60, 0.76)

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)
            let pz = (v - 0.5) * BoardLayout3D.depth
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                let px = (u - 0.5) * BoardLayout3D.width

                let cloud = (cloudNoise.fbm(px * 8, pz * 8, octaves: 4) - 0.5) * 0.10
                let speck = (speckNoise.fbm(px * 60, pz * 60, octaves: 2) - 0.5) * 0.05
                var color = base + SIMD3(repeating: cloud + speck)

                color *= bakedAO(field: field, u: u, v: v, maxDepth: maxDepth)

                writePixel(&pixels, x: x, y: y, width: width, color: color)
            }
        }
        return makeCGImage(pixels: pixels, width: width, height: height)
    }

    /// Baked ambient occlusion shared by every finish: darker toward the bottom
    /// of each well, plus extra rim contact darkening from the depth gradient,
    /// so pits read as carved regardless of material.
    private static func bakedAO(field: DepthField, u: Float, v: Float, maxDepth: Float) -> Float {
        let depth = field.depth(u: u, v: v)
        let rim = min(field.gradientMagnitude(u: u, v: v) * 0.4, 1) * 0.12
        return max(1 - 0.55 * powf(depth / maxDepth, 0.8) - rim, 0.22)
    }

    private static func writePixel(_ pixels: inout [UInt8], x: Int, y: Int, width: Int, color: SIMD3<Float>) {
        let offset = (y * width + x) * 4
        pixels[offset] = UInt8(min(max(color.x, 0), 1) * 255)
        pixels[offset + 1] = UInt8(min(max(color.y, 0), 1) * 255)
        pixels[offset + 2] = UInt8(min(max(color.z, 0), 1) * 255)
    }

    // MARK: - Environment (image-based lighting)

    /// Small equirectangular environment: a soft graded sky with a few bright
    /// elongated "window" blobs. The blobs become the specular highlights on
    /// the glass stones and the sheen on the varnished wood.
    static func environmentEquirect(dark: Bool, width: Int = 256, height: Int = 128) -> CGImage? {
        struct Blob {
            let u: Float
            let v: Float
            let sigmaU: Float
            let sigmaV: Float
            let strength: Float
        }
        let blobs = [
            Blob(u: 0.22, v: 0.24, sigmaU: 0.030, sigmaV: 0.10, strength: 1.0),
            Blob(u: 0.58, v: 0.20, sigmaU: 0.045, sigmaV: 0.12, strength: 0.9),
            Blob(u: 0.86, v: 0.30, sigmaU: 0.022, sigmaV: 0.07, strength: 0.7)
        ]

        let zenith: SIMD3<Float> = dark ? SIMD3(0.10, 0.11, 0.16) : SIMD3(0.62, 0.66, 0.74)
        let horizon: SIMD3<Float> = dark ? SIMD3(0.16, 0.14, 0.17) : SIMD3(0.82, 0.76, 0.66)
        let floor: SIMD3<Float> = dark ? SIMD3(0.05, 0.045, 0.05) : SIMD3(0.30, 0.25, 0.21)
        let blobGain: Float = dark ? 0.85 : 1.0

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)
            var color: SIMD3<Float>
            if v < 0.5 {
                color = simd_mix(zenith, horizon, SIMD3(repeating: v / 0.5))
            } else {
                color = simd_mix(horizon, floor, SIMD3(repeating: min((v - 0.5) / 0.25, 1)))
            }
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                var lit = color
                for blob in blobs {
                    var du = abs(u - blob.u)
                    du = min(du, 1 - du) // wrap around the seam
                    let dv = (v - blob.v) / blob.sigmaV
                    let dn = du / blob.sigmaU
                    lit += SIMD3(repeating: exp(-(dn * dn + dv * dv)) * blob.strength * blobGain)
                }
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(min(max(lit.x, 0), 1) * 255)
                pixels[offset + 1] = UInt8(min(max(lit.y, 0), 1) * 255)
                pixels[offset + 2] = UInt8(min(max(lit.z, 0), 1) * 255)
            }
        }
        return makeCGImage(pixels: pixels, width: width, height: height)
    }
}
