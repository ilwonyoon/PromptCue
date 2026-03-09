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
            radius: PrimitiveTokens.Shadow.panelKeyBlur,
            x: 0,
            y: PrimitiveTokens.Shadow.panelKeyY
        )
    }

    func promptCuePanelShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color,
            radius: PrimitiveTokens.Shadow.panelKeyBlur,
            x: 0,
            y: PrimitiveTokens.Shadow.panelKeyY
        )
    }

    func promptCueCardShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color,
            radius: PrimitiveTokens.Shadow.cardAmbientBlur,
            x: 0,
            y: PrimitiveTokens.Shadow.cardAmbientY
        )
    }

    func promptCueNotificationCardShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color.opacity(PrimitiveTokens.Opacity.soft),
            radius: PrimitiveTokens.Shadow.notificationKeyBlur,
            x: 0,
            y: PrimitiveTokens.Shadow.notificationKeyY
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
