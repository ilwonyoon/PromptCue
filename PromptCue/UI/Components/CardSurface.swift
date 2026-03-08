import SwiftUI

enum CardSurfaceStyle: Equatable {
    case standard
    case notification
}

struct CardSurface<Content: View>: View {
    let isSelected: Bool
    let style: CardSurfaceStyle
    @ViewBuilder private var content: Content

    init(
        isSelected: Bool = false,
        style: CardSurfaceStyle = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.style = style
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
        let surface = content
            .padding(contentPadding)
            .background(
                Group {
                    if style == .notification {
                        shape
                            .fill(SemanticTokens.MaterialStyle.notificationCard)
                            .overlay {
                                shape.fill(SemanticTokens.Surface.notificationCardBackdrop)
                            }
                            .overlay {
                                shape.fill(backgroundFill)
                            }
                    } else {
                        shape.fill(backgroundFill)
                    }
                }
            )
            .overlay {
                shape
                    .stroke(
                        borderColor,
                        lineWidth: isSelected ? PrimitiveTokens.Stroke.emphasis : PrimitiveTokens.Stroke.subtle
                    )
            }

        Group {
            if style == .notification {
                surface.promptCueNotificationCardShadow()
            } else {
                surface.promptCueCardShadow()
            }
        }
    }

    private var contentPadding: CGFloat {
        switch style {
        case .standard:
            return PrimitiveTokens.Size.cardPadding
        case .notification:
            return PrimitiveTokens.Size.notificationCardPadding
        }
    }

    private var backgroundFill: Color {
        if isSelected {
            return SemanticTokens.Surface.accentFill
        }

        switch style {
        case .standard:
            return SemanticTokens.Surface.cardFill
        case .notification:
            return SemanticTokens.Surface.notificationCardFill
        }
    }

    private var borderColor: Color {
        if isSelected {
            return SemanticTokens.Border.emphasis
        }

        switch style {
        case .standard:
            return SemanticTokens.Border.subtle
        case .notification:
            return SemanticTokens.Border.notificationCard
        }
    }

}
