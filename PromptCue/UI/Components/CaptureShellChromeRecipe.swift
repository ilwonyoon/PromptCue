import AppKit
import SwiftUI

// Backtick capture shell recipe.
// Owns product-specific chrome values for the capture surface without pushing
// runtime sizing concerns into the token layers.
//
// All colors are adaptive — they resolve at draw time via NSColor's
// appearance callback, eliminating dependence on SwiftUI's
// @Environment(\.colorScheme) propagation.
enum CaptureShellChromeRecipe {
    // glassSheen: light white@0.34, dark white@0.28
    // raisedFill: textBackgroundColor @ raisedSurface(0.92)
    static let quietRaisedFill = SemanticTokens.adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.34 * 0.76),
        dark: NSColor.textBackgroundColor.withAlphaComponent(0.92 * 0.18)
    )

    // Gradient stops pre-built as static lets so NSColor(name:) closures
    // are allocated once, not on every SwiftUI body evaluation.
    // glassSheen: light white@0.34, dark white@0.28
    // glassTint:  light white@0.16, dark white@0.18
    private static let quietSheenTop = SemanticTokens.adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.34 * 0.74),
        dark: NSColor.white.withAlphaComponent(0.28 * 0.18)
    )
    private static let quietSheenMid = SemanticTokens.adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.16 * 0.22),
        dark: NSColor.white.withAlphaComponent(0.18 * 0.12)
    )

    static var quietSheenGradient: LinearGradient {
        LinearGradient(
            colors: [quietSheenTop, quietSheenMid, .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // notificationCard border: light black@0.12, dark white@0.06
    // glassInner:  light white@0.38, dark white@0.18
    static let quietStroke = SemanticTokens.adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.white.withAlphaComponent(0.18 * 0.58)
    )

    // glassInner:     light white@0.38, dark white@0.18
    // glassHighlight: light white@0.52, dark white@0.44
    static let quietInnerStroke = SemanticTokens.adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.38 * 0.82),
        dark: NSColor.white.withAlphaComponent(0.44 * 0.24)
    )

    static let quietTopHighlight = SemanticTokens.adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.52 * 0.82),
        dark: NSColor.white.withAlphaComponent(0.44 * 0.36)
    )

    static let quietBottomStroke = SemanticTokens.adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.12 * 0.28),
        dark: NSColor.white.withAlphaComponent(0.06 * 0.22)
    )
}
