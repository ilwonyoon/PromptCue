import SwiftUI

// Backtick stack-card pattern surface.
// Keep stack card chrome independent from stack backdrop ownership.
struct StackNotificationCardSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let isSelected: Bool
    let isEmphasized: Bool
    @ViewBuilder private var content: Content

    init(
        isSelected: Bool = false,
        isEmphasized: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isEmphasized = isEmphasized
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)

        let cardBody = content
            .padding(PrimitiveTokens.Size.notificationCardPadding)
            .background {
                shape
                    .fill(backgroundFill)
                    .overlay {
                        shape.fill(chromeOverlay)
                    }
                    .overlay {
                        shape.fill(SemanticTokens.Surface.notificationCardHoverFill)
                            .opacity(isEmphasized ? 1 : 0)
                    }
                    .overlay(alignment: .top) {
                        TopEdgeStrokeOverlay(
                            shape: shape,
                            color: topHighlight,
                            lineWidth: PrimitiveTokens.Stroke.subtle,
                            frameHeight: PrimitiveTokens.Space.sm,
                            maskHeight: PrimitiveTokens.Space.sm
                        )
                        .opacity(showsElevatedChrome ? 1 : 0)
                    }
            }
            .overlay {
                shape
                    .stroke(borderColor, lineWidth: isSelected ? 2.0 : PrimitiveTokens.Stroke.subtle)
            }
            .clipShape(shape)

        cardBody.shadow(
            color: showsElevatedChrome
                ? SemanticTokens.Shadow.color.opacity(PrimitiveTokens.Opacity.soft)
                : .clear,
            radius: PrimitiveTokens.Shadow.notificationCardBlur,
            x: PrimitiveTokens.Shadow.zeroX,
            y: PrimitiveTokens.Shadow.notificationCardY
        )
    }

    private var backgroundFill: Color {
        if isSelected {
            return SemanticTokens.Surface.notificationCardEmphasizedFill
        }

        if isEmphasized {
            return SemanticTokens.Surface.notificationCardEmphasizedFill
        }

        return SemanticTokens.Surface.notificationCardFill
    }

    private var chromeOverlay: Color {
        StackNotificationCardChromeRecipe.chromeOverlay(colorScheme: colorScheme)
    }

    private var topHighlight: Color {
        StackNotificationCardChromeRecipe.topHighlight(colorScheme: colorScheme)
    }

    private var borderColor: Color {
        if isSelected {
            switch colorScheme {
            case .light:
                return Color.black.opacity(0.5)
            case .dark:
                return Color.white.opacity(0.7)
            @unknown default:
                return Color.white.opacity(0.7)
            }
        }

        if isEmphasized {
            return SemanticTokens.Border.notificationCardHover
        }

        switch colorScheme {
        case .light:
            return SemanticTokens.Border.notificationCard.opacity(0.92)
        case .dark:
            return SemanticTokens.Border.notificationCard.opacity(0.82)
        @unknown default:
            return SemanticTokens.Border.notificationCard.opacity(0.82)
        }
    }

    private var showsElevatedChrome: Bool {
        isSelected || isEmphasized
    }
}
