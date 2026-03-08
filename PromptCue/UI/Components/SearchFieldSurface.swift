import SwiftUI

enum SearchFieldSurfaceStyle {
    case quiet
    case showcase
}

struct SearchFieldSurface<Content: View>: View {
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
            .frame(minHeight: PrimitiveTokens.Size.searchFieldHeight)
            .background {
                backgroundSurface
            }
    }

    @ViewBuilder
    private var backgroundSurface: some View {
        switch style {
        case .quiet:
            shape
                .fill(SemanticTokens.MaterialStyle.floatingShell)
                .overlay {
                    shape.fill(SemanticTokens.Surface.panelFill)
                }
                .overlay {
                    shape.fill(SemanticTokens.Surface.raisedFill.opacity(PrimitiveTokens.Opacity.faint))
                }
                .overlay {
                    shape.stroke(SemanticTokens.Border.subtle)
                }
                .promptCuePanelShadow()
        case .showcase:
            shape
                .fill(SemanticTokens.MaterialStyle.elevatedGlass)
                .overlay {
                    shape.fill(SemanticTokens.Surface.panelFill)
                }
                .overlay {
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
    }
}
