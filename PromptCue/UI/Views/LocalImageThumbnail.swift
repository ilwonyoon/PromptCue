import AppKit
import ImageIO
import SwiftUI

struct LocalImageThumbnail: View {
    private static let fileManager = FileManager.default
    private static let imageCache = NSCache<NSURL, NSImage>()
    private static let loadDelaysNanos: [UInt64] = [80_000_000, 160_000_000, 280_000_000, 460_000_000, 760_000_000, 1_120_000_000]
    private enum LoadState {
        case idle
        case loading
    }

    let url: URL
    let width: CGFloat?
    let height: CGFloat
    @State private var image: NSImage?
    @State private var loadedURL: URL?
    @State private var loadState: LoadState = .idle

    init(
        url: URL,
        width: CGFloat? = nil,
        height: CGFloat = PrimitiveTokens.Size.thumbnailHeight
    ) {
        self.url = url
        self.width = width
        self.height = height
        let resolvedURL = url.standardizedFileURL
        _image = State(initialValue: Self.imageCache.object(forKey: resolvedURL as NSURL))
        _loadedURL = State(initialValue: resolvedURL)
    }

    var body: some View {
        let resolvedURL = url.standardizedFileURL

        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                    .fill(SemanticTokens.Surface.accentFill)
                    .overlay {
                        Image(systemName: "photo")
                            .font(PrimitiveTokens.Typography.iconLabel)
                            .foregroundStyle(SemanticTokens.Text.accent)
                    }
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                .fill(Self.thumbnailBackdropColor)
        )
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                .stroke(Self.thumbnailBorderColor)
        }
        .allowsHitTesting(false)
        .task(id: resolvedURL.path) {
            await loadImage(from: resolvedURL)
        }
    }

    // notificationCardBackdrop: light black@0.02, dark white@0.006
    private static let thumbnailBackdropColor = SemanticTokens.adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.02 * 0.75),
        dark: NSColor.white.withAlphaComponent(0.006)
    )

    // notificationCard border: light black@0.12, dark → subtle
    // subtle: light black@0.08, dark separatorColor@soft
    private static let thumbnailBorderColor = SemanticTokens.adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.12 * 0.9),
        dark: NSColor.separatorColor.withAlphaComponent(0.65)
    )

    @MainActor
    private func loadImage(from resolvedURL: URL) async {
        if loadedURL != resolvedURL {
            loadedURL = resolvedURL
            image = nil

            if let cachedImage = Self.imageCache.object(forKey: resolvedURL as NSURL) {
                image = cachedImage
                return
            }
        }

        if image != nil {
            return
        }

        if loadState == .loading {
            return
        }

        loadState = .loading
        let targetPixelSize = max((width ?? 320) * 2, height * 2)
        defer {
            loadState = .idle
        }

        for attempt in 0..<Self.loadDelaysNanos.count {
            guard !Task.isCancelled else {
                return
            }

            guard let readableURL = readableURL(for: resolvedURL) else {
                let delayNanos = Self.loadDelaysNanos[min(attempt, Self.loadDelaysNanos.count - 1)]
                try? await Task.sleep(nanoseconds: delayNanos)
                continue
            }

            let decodedImage = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                if let thumbnail = Self.decodeThumbnail(from: readableURL, maxPixelSize: targetPixelSize) {
                    return thumbnail
                }
                return Self.decodeImageAsFallback(from: readableURL)
            }.value

            guard !Task.isCancelled else {
                return
            }

            if let decodedImage {
                Self.imageCache.setObject(decodedImage, forKey: resolvedURL as NSURL)
                self.image = decodedImage
                return
            }

            let delayNanos = Self.loadDelaysNanos[min(attempt, Self.loadDelaysNanos.count - 1)]
            try? await Task.sleep(nanoseconds: delayNanos)
        }
    }

    private func readableURL(for resolvedURL: URL) -> URL? {
        if let managedURL = ManagedScreenshotAccess.readableURL(for: resolvedURL.path) {
            return managedURL
        }

        guard Self.fileManager.fileExists(atPath: resolvedURL.path) else {
            return nil
        }

        return resolvedURL
    }

    nonisolated private static func decodeThumbnail(from url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded(.up))),
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    nonisolated private static func decodeImageAsFallback(from url: URL) -> NSImage? {
        return NSImage(contentsOf: url)
    }
}
