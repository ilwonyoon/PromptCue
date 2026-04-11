import SwiftUI

enum SearchFieldSurfaceStyle {
    case quiet
    case captureShell
    case showcase
}

// Backtick capture pattern surface.
// This is product-specific chrome, not a generic reusable search field component.
struct SearchFieldSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let style: SearchFieldSurfaceStyle
    let contentPadding: EdgeInsets
    @ViewBuilder private var content: Content
    private let shape = RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.lg, style: .continuous)

    init(
        style: SearchFieldSurfaceStyle = .quiet,
        contentPadding: EdgeInsets = EdgeInsets(
            top: PrimitiveTokens.Space.xl,
            leading: PrimitiveTokens.Space.xl,
            bottom: PrimitiveTokens.Space.xl,
            trailing: PrimitiveTokens.Space.xl
        ),
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundSurface

            content
                .padding(contentPadding)
                .frame(minHeight: PrimitiveTokens.Size.searchFieldHeight, alignment: .topLeading)
                .clipShape(shape)
        }
    }

    @ViewBuilder
    private var backgroundSurface: some View {
        switch style {
        case .quiet:
            quietBackground
        case .captureShell:
            captureShellBackground
        case .showcase:
            showcaseBackground
        }
    }

    private var captureShellBackground: some View {
        ZStack {
            VisualEffectBackdrop(
                material: colorScheme == .dark ? .menu : .underWindowBackground,
                blendingMode: .withinWindow
            )
            .clipShape(shape)

            shape
                .fill(SemanticTokens.Surface.captureShellFill)

            shape
                .stroke(SemanticTokens.Surface.captureShellStroke, lineWidth: PrimitiveTokens.Stroke.subtle)

            TopEdgeStrokeOverlay(
                shape: shape,
                color: SemanticTokens.Surface.captureShellTopHighlight,
                lineWidth: PrimitiveTokens.Stroke.subtle,
                frameHeight: PrimitiveTokens.Space.lg,
                maskHeight: PrimitiveTokens.Space.sm
            )
        }
        .promptCueCaptureSurfaceShadow()
    }

    @ViewBuilder
    private var quietBackground: some View {
        if colorScheme == .dark {
            quietDarkBackground
        } else {
            quietLightBackground
        }
    }

    private var quietLightBackground: some View {
        baseQuietBackground
            .overlay {
                shape.fill(CaptureShellChromeRecipe.quietRaisedFill)
            }
            .overlay {
                shape.fill(CaptureShellChromeRecipe.quietSheenGradient)
            }
            .overlay {
                shape.stroke(CaptureShellChromeRecipe.quietStroke)
            }
            .overlay {
                shape
                    .inset(by: PrimitiveTokens.Stroke.subtle)
                    .stroke(CaptureShellChromeRecipe.quietInnerStroke)
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(height: PrimitiveTokens.Space.xl)
                    }
            }
            .overlay(alignment: .top) {
                TopEdgeStrokeOverlay(
                    shape: shape,
                    color: CaptureShellChromeRecipe.quietTopHighlight,
                    lineWidth: PrimitiveTokens.Stroke.subtle,
                    frameHeight: PrimitiveTokens.Space.lg,
                    maskHeight: PrimitiveTokens.Space.sm
                )
            }
            .overlay {
                shape
                    .stroke(CaptureShellChromeRecipe.quietBottomStroke)
                    .mask(alignment: .bottom) {
                        Rectangle()
                            .frame(height: PrimitiveTokens.Space.sm)
                    }
            }
            .promptCueCaptureSurfaceShadow()
    }

    private var quietDarkBackground: some View {
        shape.fill(SemanticTokens.Surface.notificationCardFill)
            .overlay {
                shape.stroke(SemanticTokens.Border.notificationCard)
            }
            .promptCuePanelShadow()
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
