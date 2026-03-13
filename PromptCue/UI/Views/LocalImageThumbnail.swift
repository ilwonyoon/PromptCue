import AppKit
import ImageIO
import SwiftUI

struct LocalImageThumbnail: View {
    @Environment(\.colorScheme) private var colorScheme
    private static let imageCache = NSCache<NSURL, NSImage>()
    let url: URL
    let width: CGFloat?
    let height: CGFloat
    @State private var image: NSImage?
    @State private var loadedURL: URL?

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
                .fill(thumbnailBackdropColor)
        )
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                .stroke(thumbnailBorderColor)
        }
        .allowsHitTesting(false)
        .task(id: resolvedURL.path) {
            await loadImage(from: resolvedURL)
        }
    }

    private var thumbnailBackdropColor: Color {
        if colorScheme == .light {
            return SemanticTokens.Surface.notificationCardBackdrop.opacity(0.75)
        }

        return SemanticTokens.Surface.notificationCardBackdrop
    }

    private var thumbnailBorderColor: Color {
        if colorScheme == .light {
            return SemanticTokens.Border.notificationCard.opacity(0.9)
        }

        return SemanticTokens.Border.subtle
    }

    @MainActor
    private func loadImage(from resolvedURL: URL) async {
        guard let readableURL = ManagedScreenshotAccess.readableURL(for: resolvedURL.path) else {
            return
        }

        if loadedURL != resolvedURL {
            loadedURL = resolvedURL
            if let cachedImage = Self.imageCache.object(forKey: resolvedURL as NSURL) {
                image = cachedImage
            }
        }

        if image != nil {
            return
        }

        let targetPixelSize = max((width ?? 320) * 2, height * 2)
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
        }
    }

    private static func decodeThumbnail(from url: URL, maxPixelSize: CGFloat) -> NSImage? {
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

    private static func decodeImageAsFallback(from url: URL) -> NSImage? {
        return NSImage(contentsOf: url)
    }
}
