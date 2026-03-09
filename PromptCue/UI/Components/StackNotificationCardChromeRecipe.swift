import SwiftUI

// Backtick stack-card chrome recipe.
// This keeps stack-card appearance decisions owned by the stack-card surface,
// instead of leaking the math back into feature views or generic token layers.
enum StackNotificationCardChromeRecipe {
    static func chromeOverlay(colorScheme: ColorScheme) -> Color {
        NotificationCardChromeRecipe.overlayFill(colorScheme: colorScheme)
    }

    static func topHighlight(colorScheme: ColorScheme) -> Color {
        NotificationCardChromeRecipe.topHighlight(colorScheme: colorScheme)
    }
}
