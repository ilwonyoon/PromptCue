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
                    .stroke(borderColor, lineWidth: isSelected ? PrimitiveTokens.Stroke.emphasis : PrimitiveTokens.Stroke.subtle)
            }
            .clipShape(shape)

        if showsElevatedChrome {
            cardBody
                .compositingGroup()
                .shadow(
                    color: SemanticTokens.Shadow.color.opacity(PrimitiveTokens.Opacity.soft),
                    radius: PrimitiveTokens.Shadow.notificationCardBlur,
                    x: PrimitiveTokens.Shadow.zeroX,
                    y: PrimitiveTokens.Shadow.notificationCardY
                )
        } else {
            cardBody
                .drawingGroup()
        }
    }

    private var backgroundFill: Color {
        if isSelected {
            return SemanticTokens.Surface.accentFill
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
            return SemanticTokens.Border.emphasis
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
