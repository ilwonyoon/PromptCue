import SwiftUI

extension View {
    func promptCueGlassShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.glassAmbient,
            radius: PrimitiveTokens.Shadow.panelBlur,
            x: 0,
            y: PrimitiveTokens.Shadow.panelY
        )
    }

    func promptCuePanelShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color,
            radius: PrimitiveTokens.Shadow.panelBlur,
            x: 0,
            y: PrimitiveTokens.Shadow.panelY
        )
    }

    func promptCueCardShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color,
            radius: PrimitiveTokens.Shadow.cardBlur,
            x: 0,
            y: PrimitiveTokens.Shadow.cardY
        )
    }

    func promptCueNotificationCardShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color.opacity(PrimitiveTokens.Opacity.soft),
            radius: PrimitiveTokens.Shadow.notificationCardBlur,
            x: 0,
            y: PrimitiveTokens.Shadow.notificationCardY
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
