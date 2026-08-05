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

    /// A synchronous peek at the cache.
    ///
    /// The picker reads this while building its body, so a style baked earlier
    /// in the session draws on the very first frame. Going through the `async`
    /// path instead would always miss that frame and only appear once the
    /// resulting state change landed — which is exactly what made the tiles
    /// look like they were waiting for the user to do something.
    static func cached(_ style: BoardMaterialStyle) -> CGImage? {
        cache[style]
    }

    /// Bakes everything not already cached, all at once.
    ///
    /// Concurrently rather than one after another: these are seven independent
    /// per-pixel noise loops, and in a Debug build (`-Onone`) each is slow
    /// enough that doing them in series is the difference between a blink and
    /// a wait. `body` reports each image as it lands so tiles fill in as they
    /// finish rather than all at the end.
    static func bakeMissing(
        _ styles: [BoardMaterialStyle],
        onEach: @MainActor (BoardMaterialStyle, CGImage) -> Void
    ) async {
        let pending = styles.filter { cache[$0] == nil }
        guard !pending.isEmpty else { return }

        let (width, height) = (Self.width, Self.height)

        await withTaskGroup(of: (BoardMaterialStyle, CGImage?).self) { group in
            for style in pending {
                group.addTask(priority: .userInitiated) {
                    // `wells: false` leaves out the baked pit occlusion. On the
                    // board those shadows are the point; in a 62pt tile they
                    // shrink to grey smudges that read as dirt on the sample
                    // rather than as pits.
                    let image = BoardTextureBuilder.baseColor(
                        for: style,
                        width: width,
                        height: height,
                        wells: false
                    )
                    return (style, image)
                }
            }

            for await (style, image) in group {
                guard let image else { continue }
                cache[style] = image
                onEach(style, image)
            }
        }
    }
}
