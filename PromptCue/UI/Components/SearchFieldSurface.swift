import SwiftUI

enum SearchFieldSurfaceStyle {
    case quiet
    case showcase
}

// Backtick capture pattern surface.
// This is product-specific chrome, not a generic reusable search field component.
struct SearchFieldSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let style: SearchFieldSurfaceStyle
    @ViewBuilder private var content: Content
    private let shape = RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.lg, style: .continuous)

    init(
        style: SearchFieldSurfaceStyle = .quiet,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        content
            .padding(PrimitiveTokens.Space.xl)
            .frame(minHeight: PrimitiveTokens.Size.searchFieldHeight, alignment: .topLeading)
            .background {
                backgroundSurface
            }
            .clipShape(shape)
    }

    @ViewBuilder
    private var backgroundSurface: some View {
        switch style {
        case .quiet:
            if colorScheme == .light {
                quietLightBackground
            } else {
                quietDarkBackground
            }
        case .showcase:
            showcaseBackground
        }
    }

    private var quietLightBackground: some View {
        baseQuietBackground
            .overlay { quietLightSheenOverlay }
            .overlay { quietLightStrokeOverlay }
            .overlay { quietLightInnerStrokeOverlay }
            .overlay(alignment: .top) { quietLightHighlightOverlay }
            .overlay { quietLightBottomStrokeOverlay }
            .promptCueCaptureSurfaceShadow()
    }

    private var quietDarkBackground: some View {
        baseQuietBackground
            .overlay {
                shape.fill(CaptureShellChromeRecipe.quietRaisedFill(colorScheme: .dark))
            }
            .overlay {
                shape.stroke(SemanticTokens.Border.notificationCard)
            }
            .promptCuePanelShadow()
    }

    private var showcaseBackground: some View {
        shape
            .fill(SemanticTokens.MaterialStyle.elevatedGlass)
            .overlay { basePanelFillOverlay }
            .overlay { showcaseGradientOverlay }
            .overlay {
                shape.stroke(SemanticTokens.Border.subtle)
            }
            .overlay {
                shape
                    .inset(by: PrimitiveTokens.Stroke.subtle)
                    .stroke(SemanticTokens.Border.glassInner)
            }
            .overlay(alignment: .top) {
                shape
                    .stroke(SemanticTokens.Border.glassHighlight, lineWidth: PrimitiveTokens.Stroke.subtle)
                    .frame(height: PrimitiveTokens.Space.xxl)
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(height: PrimitiveTokens.Space.xl)
                    }
            }
            .promptCueGlassShadow()
    }

    private var baseQuietBackground: some View {
        shape
            .fill(SemanticTokens.MaterialStyle.floatingShell)
            .overlay { basePanelFillOverlay }
    }

    private var basePanelFillOverlay: some View {
        shape.fill(SemanticTokens.Surface.panelFill)
    }

    private var quietLightSheenOverlay: some View {
        shape.fill(CaptureShellChromeRecipe.quietLightGradient)
    }

    private var quietLightStrokeOverlay: some View {
        shape.stroke(SemanticTokens.Border.notificationCard)
    }

    private var quietLightInnerStrokeOverlay: some View {
        shape
            .inset(by: PrimitiveTokens.Stroke.subtle)
            .stroke(CaptureShellChromeRecipe.quietLightInnerStroke)
            .mask(alignment: .top) {
                Rectangle()
                    .frame(height: PrimitiveTokens.Space.xl)
            }
    }

    private var quietLightHighlightOverlay: some View {
        TopEdgeStrokeOverlay(
            shape: shape,
            color: CaptureShellChromeRecipe.quietLightHighlight,
            lineWidth: PrimitiveTokens.Stroke.subtle,
            frameHeight: PrimitiveTokens.Space.lg,
            maskHeight: PrimitiveTokens.Space.sm
        )
    }

    private var quietLightBottomStrokeOverlay: some View {
        shape
            .stroke(CaptureShellChromeRecipe.quietLightBottomStroke)
            .mask(alignment: .bottom) {
                Rectangle()
                    .frame(height: PrimitiveTokens.Space.sm)
            }
    }

    private var showcaseGradientOverlay: some View {
        shape.fill(
            LinearGradient(
                colors: [
                    SemanticTokens.Surface.glassSheen,
                    SemanticTokens.Surface.glassTint,
                    SemanticTokens.Surface.glassEdge,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
