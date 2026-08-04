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
    static func baseColor(for style: BoardMaterialStyle, width: Int = 2048, height: Int = 1024, wells: Bool = true) -> CGImage? {
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
                width: width, height: height, wells: wells
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
                width: width, height: height, wells: wells
            )
        case .terracotta:
            return terracottaBaseColor(width: width, height: height, wells: wells)
        case .marble:
            return marbleBaseColor(width: width, height: height, wells: wells)
        case .malachite:
            return malachiteBaseColor(width: width, height: height, wells: wells)
        case .slate:
            return slateBaseColor(width: width, height: height, wells: wells)
        case .obsidian:
            return obsidianBaseColor(width: width, height: height, wells: wells)
        case .brushedBrass:
            return brushedBrassBaseColor(width: width, height: height, wells: wells)
        case .frostedGlass:
            return frostedGlassBaseColor(width: width, height: height, wells: wells)
        }
    }

    private static func woodBaseColor(palette: WoodPalette, width: Int, height: Int, wells: Bool) -> CGImage? {
        let grainNoise = ValueNoise(seed: 0xB0A2D)
        let streakNoise = ValueNoise(seed: 0x5EED5)
        let fineNoise = ValueNoise(seed: 0xC1A55)
        let field = wells ? sharedDepthField : nil
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

    /// Unglazed terracotta: warm fired clay, uneven in tone the way a kiln
    /// leaves it, gritty with the sand in its body, and faintly ringed where a
    /// wheel would have thrown it.
    private static func terracottaBaseColor(width: Int, height: Int, wells: Bool) -> CGImage? {
        let clayNoise = ValueNoise(seed: 0x7E44A)
        let gritNoise = ValueNoise(seed: 0xC1A47)
        let field = wells ? sharedDepthField : nil
        let maxDepth = BoardLayout3D.maxWellDepth

        let base = SIMD3<Float>(0.600, 0.325, 0.215)
        let pale = SIMD3<Float>(0.765, 0.505, 0.355)

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)
            let pz = (v - 0.5) * BoardLayout3D.depth
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                let px = (u - 0.5) * BoardLayout3D.width

                // Blotchy firing at two scales. One alone leaves the clay
                // looking painted rather than fired.
                let broad = clayNoise.fbm(px * 14, pz * 14, octaves: 3)
                let local = clayNoise.fbm(px * 46, pz * 46, octaves: 2)
                // Throwing rings across the short axis, wobbled so they don't
                // read as machined.
                let wobble = clayNoise.fbm(px * 3, pz * 12) * 2.2
                let rings = sin(pz * 130 + wobble) * 0.5 + 0.5
                // Sand in the clay body: a fine even grain, and the odd darker
                // pit where a grain has burnt out.
                let grain = (gritNoise.fbm(px * 380, pz * 380, octaves: 2) - 0.5) * 0.085
                let pitting = max(gritNoise.fbm(px * 120 + 17, pz * 120, octaves: 2) - 0.60, 0) * 0.45

                var color = simd_mix(
                    base,
                    pale,
                    SIMD3(repeating: min(max(broad * 0.80 + local * 0.18 + rings * 0.18 - 0.10, 0), 1))
                )
                color += SIMD3(repeating: grain - pitting)

                color *= bakedAO(field: field, u: u, v: v, maxDepth: maxDepth)

                writePixel(&pixels, x: x, y: y, width: width, color: color)
            }
        }
        return makeCGImage(pixels: pixels, width: width, height: height)
    }

    /// Polished marble: near-white base crossed by thin veins carved with
    /// domain-warped `sin` turbulence.
    private static func marbleBaseColor(width: Int, height: Int, wells: Bool) -> CGImage? {
        let warpNoise = ValueNoise(seed: 0x9A12B)
        let mottleNoise = ValueNoise(seed: 0x33F0D)
        let field = wells ? sharedDepthField : nil
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

    /// Malachite: deep green stone banded in concentric rings. The mineral
    /// grows in rounded botryoidal masses, so the bands here are drawn as
    /// distance from a handful of scattered centres rather than as straight
    /// veins — no two sets of rings share a centre, which is what makes it read
    /// as malachite rather than as contour lines.
    private static func malachiteBaseColor(width: Int, height: Int, wells: Bool) -> CGImage? {
        let warpNoise = ValueNoise(seed: 0x4A11E)
        let grainNoise = ValueNoise(seed: 0x2B7C3)
        let field = wells ? sharedDepthField : nil
        let maxDepth = BoardLayout3D.maxWellDepth

        let pale = SIMD3<Float>(0.315, 0.600, 0.420)
        let deep = SIMD3<Float>(0.055, 0.215, 0.150)

        /// A rounded mass of the mineral. Each one bands at its own rate, so
        /// the board doesn't come out looking like a set of matching targets.
        struct Botryoid {
            let centre: SIMD2<Float>
            let frequency: Float
        }
        // Kept coarse on purpose: a board is only two thirds of a metre across,
        // and rings any tighter than this stop reading as stone and start
        // reading as stripes, drowning the wells and the stones sitting in them.
        let masses = [
            Botryoid(centre: SIMD2(-0.27, 0.05), frequency: 140),
            Botryoid(centre: SIMD2(-0.13, -0.08), frequency: 205),
            Botryoid(centre: SIMD2(0.02, 0.07), frequency: 120),
            Botryoid(centre: SIMD2(0.16, -0.06), frequency: 180),
            Botryoid(centre: SIMD2(0.29, 0.09), frequency: 155)
        ]

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)
            let pz = (v - 0.5) * BoardLayout3D.depth
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                let px = (u - 0.5) * BoardLayout3D.width

                // Sampled through a drift rather than straight, so the joins
                // between masses wander the way a mineral's do instead of
                // meeting in the dead-straight creases a plain nearest-centre
                // test leaves behind.
                let drift = SIMD2(
                    warpNoise.fbm(px * 6 + 11, pz * 6) - 0.5,
                    warpNoise.fbm(px * 6, pz * 6 + 23) - 0.5
                ) * 0.09
                let point = SIMD2(px, pz) + drift

                var nearest = Float.greatestFiniteMagnitude
                var phase: Float = 0
                for mass in masses {
                    let distance = simd_length(point - mass.centre)
                    if distance < nearest {
                        nearest = distance
                        phase = distance * mass.frequency
                    }
                }

                let warp = warpNoise.fbm(px * 9, pz * 9, octaves: 4)
                // Band spacing wanders within each mass too — evenly ruled
                // rings read as machined.
                let spacing = 1 + (warpNoise.fbm(px * 4 + 31, pz * 4) - 0.5) * 0.5
                let bands = sin(phase * spacing + warp * 9)
                // Sharpened so the pale bands stay narrow against the dark
                // ground, the way the light layers do in the real stone.
                let banding = powf(bands * 0.5 + 0.5, 3.0)
                let grain = (grainNoise.fbm(px * 30, pz * 30, octaves: 2) - 0.5) * 0.06

                var color = simd_mix(deep, pale, SIMD3(repeating: min(max(banding + grain, 0), 1)))

                color *= bakedAO(field: field, u: u, v: v, maxDepth: maxDepth)

                writePixel(&pixels, x: x, y: y, width: width, color: color)
            }
        }
        return makeCGImage(pixels: pixels, width: width, height: height)
    }

    /// Matte slate: dark, low-contrast stone with subtle cloudy mottling and
    /// faint lighter flecks.
    private static func slateBaseColor(width: Int, height: Int, wells: Bool) -> CGImage? {
        let cloudNoise = ValueNoise(seed: 0x5171E)
        let fleckNoise = ValueNoise(seed: 0x7EC24)
        let field = wells ? sharedDepthField : nil
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

    /// Obsidian: volcanic glass, all but black. Its colour carries almost
    /// nothing — the finish reads by its reflections instead (see the near-zero
    /// roughness in `BoardScene`) — so the base is a faint violet sheen along
    /// the shell-shaped fracture lines and black everywhere else.
    private static func obsidianBaseColor(width: Int, height: Int, wells: Bool) -> CGImage? {
        let warpNoise = ValueNoise(seed: 0x0B51D)
        let dustNoise = ValueNoise(seed: 0x3D0FF)
        let field = wells ? sharedDepthField : nil
        let maxDepth = BoardLayout3D.maxWellDepth

        let base = SIMD3<Float>(0.042, 0.042, 0.052)
        let sheen = SIMD3<Float>(0.088, 0.078, 0.118)

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)
            let pz = (v - 0.5) * BoardLayout3D.depth
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                let px = (u - 0.5) * BoardLayout3D.width

                let warp = warpNoise.fbm(px * 6, pz * 6, octaves: 5) * 7
                let flow = sin((px * 22 + pz * 9) + warp)
                // The sheen is confined to the flow lines themselves and falls
                // away fast either side, so it reads as banding in the glass
                // rather than as a purple haze over it.
                let away = powf(min(abs(flow), 1), 0.6)
                let dust = (dustNoise.fbm(px * 50, pz * 50, octaves: 2) - 0.5) * 0.012

                var color = simd_mix(sheen, base, SIMD3(repeating: away))
                color += SIMD3(repeating: dust)

                color *= bakedAO(field: field, u: u, v: v, maxDepth: maxDepth)

                writePixel(&pixels, x: x, y: y, width: width, color: color)
            }
        }
        return makeCGImage(pixels: pixels, width: width, height: height)
    }

    /// Brushed brass: warm metal, grained along the board's length. The
    /// streaks come from sampling noise slowly along `x` and very fast across
    /// `z`, which stretches it into lines rather than mottle; a broad sweep
    /// underneath keeps it from reading as a uniform sheet.
    private static func brushedBrassBaseColor(width: Int, height: Int, wells: Bool) -> CGImage? {
        let brushNoise = ValueNoise(seed: 0xB2A55)
        let sweepNoise = ValueNoise(seed: 0x9F0E1)
        let field = wells ? sharedDepthField : nil
        let maxDepth = BoardLayout3D.maxWellDepth

        let light = SIMD3<Float>(0.865, 0.695, 0.345)
        let dark = SIMD3<Float>(0.520, 0.385, 0.145)

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)
            let pz = (v - 0.5) * BoardLayout3D.depth
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                let px = (u - 0.5) * BoardLayout3D.width

                let fine = brushNoise.fbm(px * 3, pz * 900, octaves: 2)
                let coarse = brushNoise.fbm(px * 1.5, pz * 220, octaves: 2)
                let sweep = (sweepNoise.fbm(px * 2.5, pz * 2.5, octaves: 3) - 0.5) * 0.22

                let polish = min(max(fine * 0.45 + coarse * 0.35 + sweep + 0.12, 0), 1)
                var color = simd_mix(dark, light, SIMD3(repeating: polish))

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
    private static func frostedGlassBaseColor(width: Int, height: Int, wells: Bool) -> CGImage? {
        let cloudNoise = ValueNoise(seed: 0x6F203)
        let speckNoise = ValueNoise(seed: 0x1CE55)
        let field = wells ? sharedDepthField : nil
        let maxDepth = BoardLayout3D.maxWellDepth

        let base = SIMD3<Float>(0.82, 0.88, 0.94)

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
    private static func bakedAO(field: DepthField?, u: Float, v: Float, maxDepth: Float) -> Float {
        // No field means a flat sample: material only, no pits to shade.
        guard let field else { return 1 }
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
