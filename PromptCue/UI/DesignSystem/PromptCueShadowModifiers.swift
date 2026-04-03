import SwiftUI

extension View {
    func promptCueCaptureSurfaceShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.captureShellAmbient.opacity(PrimitiveTokens.Shadow.captureAmbientOpacity),
            radius: PrimitiveTokens.Shadow.captureAmbientBlur,
            x: PrimitiveTokens.Shadow.zeroX,
            y: PrimitiveTokens.Shadow.captureAmbientY
        )
        .shadow(
            color: SemanticTokens.Shadow.captureShellKey.opacity(PrimitiveTokens.Shadow.captureKeyOpacity),
            radius: PrimitiveTokens.Shadow.captureKeyBlur,
            x: PrimitiveTokens.Shadow.zeroX,
            y: PrimitiveTokens.Shadow.captureKeyY
        )
    }

    func promptCueGlassShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.glassAmbient,
            radius: PrimitiveTokens.Shadow.glassBlur,
            x: PrimitiveTokens.Shadow.zeroX,
            y: PrimitiveTokens.Shadow.glassY
        )
    }

    func promptCuePanelShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color,
            radius: PrimitiveTokens.Shadow.panelBlur,
            x: PrimitiveTokens.Shadow.zeroX,
            y: PrimitiveTokens.Shadow.panelY
        )
    }

    func promptCueCardShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color,
            radius: PrimitiveTokens.Shadow.raisedCardBlur,
            x: PrimitiveTokens.Shadow.zeroX,
            y: PrimitiveTokens.Shadow.raisedCardY
        )
    }

    func promptCueFloatingControlShadow() -> some View {
        shadow(
            color: SemanticTokens.Shadow.color,
            radius: PrimitiveTokens.Shadow.floatingControlBlur,
            x: PrimitiveTokens.Shadow.zeroX,
            y: PrimitiveTokens.Shadow.floatingControlY
        )
    }
}
