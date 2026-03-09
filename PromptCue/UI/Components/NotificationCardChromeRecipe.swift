import SwiftUI

// Shared notification-card chrome recipe.
// Reused by both generic notification surfaces and the Backtick stack-card surface.
enum NotificationCardChromeRecipe {
    static func overlayFill(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.015)
        case .dark:
            return SemanticTokens.Surface.notificationCardBackdrop
        @unknown default:
            return SemanticTokens.Surface.notificationCardBackdrop
        }
    }

    static func topHighlight(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Border.glassHighlight.opacity(0.16)
        case .dark:
            return SemanticTokens.Border.glassHighlight.opacity(0.08)
        @unknown default:
            return SemanticTokens.Border.glassHighlight.opacity(0.08)
        }
    }

    static func genericTopHighlight(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Border.glassHighlight.opacity(0.18)
        case .dark:
            return SemanticTokens.Border.glassHighlight.opacity(0.08)
        @unknown default:
            return SemanticTokens.Border.glassHighlight.opacity(0.08)
        }
    }
}
