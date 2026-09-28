import CoreGraphics
import Foundation
import ImageIO

/// Resolves the `path` prop shared by `file-image` and `file-preview` nodes:
/// either an absolute filesystem path or a `file://` URL string. Non-file
/// schemes return nil — remote URLs belong to `link` nodes.
enum LUIFilePath {
    static func url(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if let url = URL(string: path), url.scheme != nil {
            return url.isFileURL ? url : nil
        }
        return URL(fileURLWithPath: path)
    }
}

/// Loads `file-image` pixels. Decoding happens off the main actor through
/// `CGImageSourceCreateThumbnailAtIndex` — the file is never rasterized at
/// native size — and thumbnails are cached by "<max-pixel-size>|<path>" in an
/// NSCache (~32MB cost limit, 32 items).
enum LUIFileImageLoader {
    static let defaultMaxPixelSize = 1024

    private actor Cache {
        private let images = NSCache<NSString, CGImage>()

        init() {
            images.totalCostLimit = 32 * 1024 * 1024
            images.countLimit = 32
        }

        func image(for key: String) -> CGImage? {
            images.object(forKey: key as NSString)
        }

        func store(_ image: CGImage, for key: String) {
            images.setObject(
                image,
                forKey: key as NSString,
                cost: image.bytesPerRow * image.height
            )
        }
    }

    private static let cache = Cache()

    static func thumbnail(path: String, maxPixelSize: Int) async -> CGImage? {
        guard let url = LUIFilePath.url(path) else { return nil }
        let key = "\(maxPixelSize)|\(path)"
        if let cached = await cache.image(for: key) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            decodeThumbnail(url: url, maxPixelSize: maxPixelSize)
        }.value
        if let decoded {
            await cache.store(decoded, for: key)
        }
        return decoded
    }

    private static func decodeThumbnail(url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            sourceOptions
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        )
    }
}
