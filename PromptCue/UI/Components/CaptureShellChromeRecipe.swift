import SwiftUI

// Backtick capture shell recipe.
// Owns product-specific chrome values for the capture surface without pushing
// runtime sizing concerns into the token layers.
enum CaptureShellChromeRecipe {
    static func quietRaisedFill(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Surface.glassSheen.opacity(0.82)
        case .dark:
            return SemanticTokens.Surface.raisedFill.opacity(PrimitiveTokens.Opacity.faint)
        @unknown default:
            return SemanticTokens.Surface.raisedFill.opacity(PrimitiveTokens.Opacity.faint)
        }
    }

    static var quietLightGradient: LinearGradient {
        LinearGradient(
            colors: [
                SemanticTokens.Surface.glassSheen.opacity(0.82),
                SemanticTokens.Surface.glassTint.opacity(0.22),
                SemanticTokens.Surface.glassEdge.opacity(0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var quietLightInnerStroke: Color {
        SemanticTokens.Border.glassInner.opacity(0.82)
    }

    static var quietLightHighlight: Color {
        SemanticTokens.Border.glassHighlight.opacity(0.82)
    }

    static var quietLightBottomStroke: Color {
        SemanticTokens.Border.notificationCard.opacity(0.28)
    }
}
