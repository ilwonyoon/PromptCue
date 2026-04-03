import AppKit
import SwiftUI

// Backtick stack-card chrome recipe.
// This keeps stack-card appearance decisions owned by the stack-card surface,
// instead of leaking the math back into feature views or generic token layers.
//
// All colors are adaptive — they resolve at draw time via NSColor's
// appearance callback, eliminating dependence on SwiftUI's
// @Environment(\.colorScheme) propagation.
enum StackNotificationCardChromeRecipe {
    static let chromeOverlay = SemanticTokens.adaptiveColor(
        light: .clear,
        dark: .clear
    )

    static let topHighlight = SemanticTokens.adaptiveColor(
        light: .clear,
        dark: .clear
    )
}
