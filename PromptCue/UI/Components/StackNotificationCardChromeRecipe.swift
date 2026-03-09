import SwiftUI

// Backtick stack-card chrome recipe.
// This keeps stack-card appearance decisions owned by the stack-card surface,
// instead of leaking the math back into feature views or generic token layers.
enum StackNotificationCardChromeRecipe {
    static func chromeOverlay(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.white.opacity(0.10)
        case .dark:
            return Color.white.opacity(0.055)
        @unknown default:
            return Color.white.opacity(0.055)
        }
    }

    static func topHighlight(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Border.glassHighlight.opacity(0.24)
        case .dark:
            return SemanticTokens.Border.glassHighlight.opacity(0.14)
        @unknown default:
            return SemanticTokens.Border.glassHighlight.opacity(0.14)
        }
    }
}
