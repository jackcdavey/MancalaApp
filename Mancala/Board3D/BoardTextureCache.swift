import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// On-disk cache of the procedural base-color bakes from `BoardTextureBuilder`.
///
/// Every finish is generated from fixed seeds, so a given style always bakes
/// to the same pixels — yet that bake is a multi-hundred-millisecond CPU pass
/// at 2048×1024, and without this it re-ran on every launch, putting the
/// "Applying material…" overlay up before the first game each time. Decoding
/// the PNG written by an earlier launch is a small fraction of that.
///
/// Entries live in Caches, so the system may purge them; a miss just falls
/// back to baking. They're keyed by app build as well as style and size, so
/// a build that changes a generator never reads a stale bake from the last
/// one — old builds' files are swept on the first write.
nonisolated enum BoardTextureCache {
    private static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appendingPathComponent("BoardTextures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let buildTag: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version)-\(build)"
    }()

    private static func url(for style: BoardMaterialStyle, width: Int, height: Int) -> URL? {
        directory?.appendingPathComponent("\(buildTag)_\(style.rawValue)_\(width)x\(height).png")
    }

    /// The cached bake for this style, fully decoded, or `nil` on a miss.
    static func image(for style: BoardMaterialStyle, width: Int, height: Int) -> CGImage? {
        guard let url = url(for: style, width: width, height: height),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        // Decode now, on the caller's background task, rather than lazily on
        // the main actor when RealityKit first reads the pixels.
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              image.width == width, image.height == height else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return image
    }

    static func store(_ image: CGImage, for style: BoardMaterialStyle) {
        guard let dir = directory,
              let url = url(for: style, width: image.width, height: image.height) else { return }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return }
        // Atomic, so a launch killed mid-write never leaves a truncated PNG.
        try? data.write(to: url, options: .atomic)
        removeOtherBuilds(in: dir)
    }

    private static func removeOtherBuilds(in dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where !file.lastPathComponent.hasPrefix("\(buildTag)_") {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
