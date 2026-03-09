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
            quietBackground
        case .showcase:
            showcaseBackground
        }
    }

    private var quietBackground: some View {
        baseQuietBackground
            .overlay {
                shape.fill(CaptureShellChromeRecipe.quietRaisedFill(colorScheme: colorScheme))
            }
            .overlay {
                shape.fill(CaptureShellChromeRecipe.quietSheenGradient(colorScheme: colorScheme))
            }
            .overlay {
                shape.stroke(CaptureShellChromeRecipe.quietStroke(colorScheme: colorScheme))
            }
            .overlay {
                shape
                    .inset(by: PrimitiveTokens.Stroke.subtle)
                    .stroke(CaptureShellChromeRecipe.quietInnerStroke(colorScheme: colorScheme))
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(height: PrimitiveTokens.Space.xl)
                    }
            }
            .overlay(alignment: .top) {
                TopEdgeStrokeOverlay(
                    shape: shape,
                    color: CaptureShellChromeRecipe.quietTopHighlight(colorScheme: colorScheme),
                    lineWidth: PrimitiveTokens.Stroke.subtle,
                    frameHeight: PrimitiveTokens.Space.lg,
                    maskHeight: PrimitiveTokens.Space.sm
                )
            }
            .overlay {
                shape
                    .stroke(CaptureShellChromeRecipe.quietBottomStroke(colorScheme: colorScheme))
                    .mask(alignment: .bottom) {
                        Rectangle()
                            .frame(height: PrimitiveTokens.Space.sm)
                    }
            }
            .promptCueCaptureSurfaceShadow()
    }

    private var showcaseBackground: some View {
        shape
            .fill(SemanticTokens.MaterialStyle.elevatedGlass)
            .overlay { basePanelFillOverlay }
            .overlay { shape.fill(ShowcaseGlassChrome.gradientOverlay) }
            .overlay {
                shape.stroke(SemanticTokens.Border.subtle)
            }
            .overlay {
                shape
                    .inset(by: PrimitiveTokens.Stroke.subtle)
                    .stroke(ShowcaseGlassChrome.innerStroke)
            }
            .overlay(alignment: .top) {
                shape
                    .stroke(ShowcaseGlassChrome.topHighlight, lineWidth: PrimitiveTokens.Stroke.subtle)
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
}
