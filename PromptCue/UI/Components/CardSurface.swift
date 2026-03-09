import SwiftUI

enum CardSurfaceStyle: Equatable {
    case standard
    case notification
}

struct CardSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let isSelected: Bool
    let isEmphasized: Bool
    let style: CardSurfaceStyle
    @ViewBuilder private var content: Content

    init(
        isSelected: Bool = false,
        isEmphasized: Bool = false,
        style: CardSurfaceStyle = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isEmphasized = isEmphasized
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
                        notificationBackground(for: shape)
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
            .clipShape(shape)

        Group {
            if style == .notification {
                surface.promptCueNotificationCardShadow()
            } else {
                surface.promptCueCardShadow()
            }
        }
    }

    @ViewBuilder
    private func notificationBackground(for shape: RoundedRectangle) -> some View {
        if colorScheme == .light {
            shape
                .fill(SemanticTokens.MaterialStyle.notificationCard)
                .overlay {
                    shape.fill(backgroundFill)
                }
                .overlay {
                    if isEmphasized {
                        shape.fill(SemanticTokens.Surface.notificationCardHoverFill)
                    }
                }
                .overlay(alignment: .top) {
                    TopEdgeStrokeOverlay(
                        shape: shape,
                        color: NotificationCardChromeRecipe.genericTopHighlight(colorScheme: colorScheme),
                        lineWidth: PrimitiveTokens.Stroke.subtle,
                        frameHeight: PrimitiveTokens.Space.sm,
                        maskHeight: PrimitiveTokens.Space.sm
                    )
                }
        } else {
            shape
                .fill(SemanticTokens.MaterialStyle.notificationCard)
                .overlay {
                    shape.fill(NotificationCardChromeRecipe.overlayFill(colorScheme: colorScheme))
                }
                .overlay {
                    shape.fill(backgroundFill)
                }
                .overlay {
                    if isEmphasized {
                        shape.fill(SemanticTokens.Surface.notificationCardHoverFill)
                    }
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

        if isEmphasized, style == .notification {
            return SemanticTokens.Border.notificationCardHover
        }

        switch style {
        case .standard:
            return SemanticTokens.Border.subtle
        case .notification:
            return SemanticTokens.Border.notificationCard
        }
    }

}
