import CoreGraphics
import SwiftUI

/// Small previews of the real board finishes, for the Customize picker.
///
/// Baked from `BoardTextureBuilder` rather than drawn by hand, so a finish can
/// never look one way in the picker and another on the board — the swatch *is*
/// the texture, just at a fraction of the resolution.
///
/// The bake is a per-pixel noise loop, so it runs off the main actor. That is
/// the one part of the material pipeline safe to detach: setting
/// `PhysicallyBasedMaterial` properties off-main traps (see
/// `BoardScene.bakedMaterial(for:)`, which splits the work the same way).
///
/// Results are cached for the life of the process. Reopening Customize is then
/// free, which matters because the picker is a place people flick back and
/// forth in.
@MainActor
enum BoardMaterialSwatch {
    /// Small enough that nine bakes are unnoticeable, large enough that grain,
    /// veining, and brushed metal still read. The generators work in normalised
    /// UV, so a smaller render is the same pattern at lower detail rather than
    /// a different-looking one.
    private static let width = 220
    private static let height = 110

    private static var cache: [BoardMaterialStyle: CGImage] = [:]

    static func cached(_ style: BoardMaterialStyle) -> CGImage? {
        cache[style]
    }

    /// Bakes `style` if it isn't cached yet, and returns it either way.
    static func image(for style: BoardMaterialStyle) async -> CGImage? {
        if let cached = cache[style] {
            return cached
        }

        let (width, height) = (Self.width, Self.height)
        let image = await Task.detached(priority: .userInitiated) {
            // `wells: false` leaves out the baked pit occlusion. On the board
            // those shadows are the point; in a 62pt tile they shrink to grey
            // smudges that read as dirt on the sample rather than as pits.
            BoardTextureBuilder.baseColor(for: style, width: width, height: height, wells: false)
        }.value

        if let image {
            cache[style] = image
        }
        return image
    }
}
