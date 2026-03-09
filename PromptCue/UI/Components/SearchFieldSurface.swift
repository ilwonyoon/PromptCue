import SwiftUI

enum SearchFieldSurfaceStyle {
    case quiet
    case showcase
}

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
                shape
                    .fill(SemanticTokens.MaterialStyle.floatingShell)
                    .overlay {
                        shape.fill(SemanticTokens.Surface.panelFill)
                    }
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    SemanticTokens.Surface.glassSheen.opacity(0.82),
                                    SemanticTokens.Surface.glassTint.opacity(0.22),
                                    SemanticTokens.Surface.glassEdge.opacity(0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .overlay {
                        shape.stroke(SemanticTokens.Border.notificationCard)
                    }
                    .overlay {
                        shape
                            .inset(by: PrimitiveTokens.Stroke.subtle)
                            .stroke(SemanticTokens.Border.glassInner.opacity(0.82))
                            .mask(alignment: .top) {
                                Rectangle()
                                    .frame(height: PrimitiveTokens.Space.xl)
                            }
                    }
                    .overlay(alignment: .top) {
                        shape
                            .stroke(
                                SemanticTokens.Border.glassHighlight.opacity(0.82),
                                lineWidth: PrimitiveTokens.Stroke.subtle
                            )
                            .frame(height: PrimitiveTokens.Space.lg)
                            .mask(alignment: .top) {
                                Rectangle()
                                    .frame(height: PrimitiveTokens.Space.sm)
                            }
                    }
                    .overlay {
                        shape
                            .stroke(SemanticTokens.Border.notificationCard.opacity(0.28))
                            .mask(alignment: .bottom) {
                                Rectangle()
                                    .frame(height: PrimitiveTokens.Space.sm)
                            }
                    }
                    .promptCueCaptureSurfaceShadow()
            } else {
                shape
                    .fill(SemanticTokens.MaterialStyle.floatingShell)
                    .overlay {
                        shape.fill(SemanticTokens.Surface.panelFill)
                    }
                    .overlay {
                        shape.fill(SemanticTokens.Surface.raisedFill.opacity(PrimitiveTokens.Opacity.faint))
                    }
                    .overlay {
                        shape.stroke(SemanticTokens.Border.notificationCard)
                    }
                    .promptCuePanelShadow()
            }
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
