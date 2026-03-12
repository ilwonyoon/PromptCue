import AppKit
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
        .id(resolvedURL.path)
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
            loadedURL = resolvedURL
            image = nil
            return
        }

        if loadedURL != resolvedURL {
            loadedURL = resolvedURL
            image = Self.imageCache.object(forKey: resolvedURL as NSURL)
        }

        if image != nil {
            return
        }

        let imageData = await Task.detached(priority: .userInitiated) { () -> Data? in
            try? Data(contentsOf: readableURL)
        }.value

        guard !Task.isCancelled else {
            return
        }

        if let image = imageData.flatMap(NSImage.init(data:)) {
            Self.imageCache.setObject(image, forKey: resolvedURL as NSURL)
            self.image = image
        } else {
            self.image = nil
        }
    }
}
