import SwiftUI

extension View {
    func promptCueCaptureSurfaceShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.panelAmbient.opacity(0.72),
            radius: PrimitiveTokens.Shadow.captureAmbientBlur,
            x: 0,
            y: PrimitiveTokens.Shadow.captureAmbientY
        )
        .shadow(
            color: SemanticTokens.Shadow.panelKey.opacity(0.32),
            radius: PrimitiveTokens.Shadow.captureKeyBlur,
            x: 0,
            y: PrimitiveTokens.Shadow.captureKeyY
        )
    }

    func promptCueGlassShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.glassAmbient,
            radius: 10,
            x: 0,
            y: 2
        )
    }

    func promptCuePanelShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color,
            radius: 10,
            x: 0,
            y: 2
        )
    }

    func promptCueCardShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color,
            radius: 14,
            x: 0,
            y: 8
        )
    }

    func promptCueNotificationCardShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color.opacity(PrimitiveTokens.Opacity.soft),
            radius: 10,
            x: 0,
            y: 4
        )
    }

    func promptCueFloatingControlShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color,
            radius: PrimitiveTokens.Space.xs,
            x: 0,
            y: PrimitiveTokens.Space.xxxs
        )
    }
}
