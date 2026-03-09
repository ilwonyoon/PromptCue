import AppKit
import SwiftUI

struct LocalImageThumbnail: View {
    @Environment(\.colorScheme) private var colorScheme
    let url: URL
    let width: CGFloat?
    let height: CGFloat
    @State private var image: NSImage?

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
        .task(id: url) {
            await loadImage()
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
    private func loadImage() async {
        image = nil

        let imageData = await Task.detached(priority: .userInitiated) { () -> Data? in
            ScreenshotDirectoryResolver.withAccessIfNeeded(to: url) { scopedURL in
                try? Data(contentsOf: scopedURL)
            }
        }.value

        guard !Task.isCancelled else {
            return
        }

        image = imageData.flatMap(NSImage.init(data:))
    }
}
