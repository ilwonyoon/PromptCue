import SwiftUI

// Backtick capture shell recipe.
// Owns product-specific chrome values for the capture surface without pushing
// runtime sizing concerns into the token layers.
enum CaptureShellChromeRecipe {
    static func quietRaisedFill(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Surface.glassSheen.opacity(0.76)
        case .dark:
            return SemanticTokens.Surface.raisedFill.opacity(0.18)
        @unknown default:
            return SemanticTokens.Surface.raisedFill.opacity(0.18)
        }
    }

    static func quietSheenGradient(colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .light:
            return LinearGradient(
                colors: [
                    SemanticTokens.Surface.glassSheen.opacity(0.74),
                    SemanticTokens.Surface.glassTint.opacity(0.22),
                    SemanticTokens.Surface.glassEdge.opacity(0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .dark:
            return LinearGradient(
                colors: [
                    SemanticTokens.Surface.glassSheen.opacity(0.18),
                    SemanticTokens.Surface.glassTint.opacity(0.12),
                    SemanticTokens.Surface.glassEdge.opacity(0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        @unknown default:
            return LinearGradient(
                colors: [
                    SemanticTokens.Surface.glassSheen.opacity(0.18),
                    SemanticTokens.Surface.glassTint.opacity(0.12),
                    SemanticTokens.Surface.glassEdge.opacity(0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    static func quietStroke(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Border.notificationCard
        case .dark:
            return SemanticTokens.Border.glassInner.opacity(0.58)
        @unknown default:
            return SemanticTokens.Border.glassInner.opacity(0.58)
        }
    }

    static func quietInnerStroke(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Border.glassInner.opacity(0.82)
        case .dark:
            return SemanticTokens.Border.glassHighlight.opacity(0.24)
        @unknown default:
            return SemanticTokens.Border.glassHighlight.opacity(0.24)
        }
    }

    static func quietTopHighlight(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Border.glassHighlight.opacity(0.82)
        case .dark:
            return SemanticTokens.Border.glassHighlight.opacity(0.36)
        @unknown default:
            return SemanticTokens.Border.glassHighlight.opacity(0.36)
        }
    }

    static func quietBottomStroke(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Border.notificationCard.opacity(0.28)
        case .dark:
            return SemanticTokens.Border.notificationCard.opacity(0.22)
        @unknown default:
            return SemanticTokens.Border.notificationCard.opacity(0.22)
        }
    }
}
