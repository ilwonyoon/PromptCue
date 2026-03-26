import AppKit
import SwiftUI

// Backtick copied-stack recipe.
// Owns the collapsed copied-section plate math so CardStackView can compose it
// without carrying local opacity and shade decisions inline.
//
// All colors are adaptive — they resolve at draw time via NSColor's
// appearance callback, eliminating dependence on SwiftUI's
// @Environment(\.colorScheme) propagation.
enum CopiedStackRecipe {
    static let frontToMiddleGap: CGFloat = PrimitiveTokens.Space.sm
    static let middleToBackGap: CGFloat = 8

    static func collapsedBackPlateIndices(for cardCount: Int) -> [Int] {
        switch cardCount {
        case ...1:
            return []
        case 2:
            return [1]
        default:
            return [2, 1]
        }
    }

    static func collapsedBottomPadding(for indices: [Int]) -> CGFloat {
        (indices.map(collapsedVerticalOffset(for:)).max() ?? 0) + PrimitiveTokens.Space.sm
    }

    static func collapsedVerticalOffset(for index: Int) -> CGFloat {
        switch index {
        case 1:
            return frontToMiddleGap
        case 2:
            return frontToMiddleGap + middleToBackGap
        default:
            return frontToMiddleGap + middleToBackGap + (CGFloat(index - 2) * middleToBackGap)
        }
    }

    static func backPlateCornerRadius(for index: Int) -> CGFloat {
        PrimitiveTokens.Radius.md
    }

    static func collapsedHorizontalInset(for index: Int) -> CGFloat {
        switch index {
        case 1:
            return PrimitiveTokens.Space.sm
        case 2:
            return PrimitiveTokens.Space.xl
        default:
            return PrimitiveTokens.Space.xl + (CGFloat(index - 2) * PrimitiveTokens.Space.sm)
        }
    }

    static let headerTextColor = SemanticTokens.adaptiveColor(
        light: NSColor.labelColor.withAlphaComponent(0.74),
        dark: NSColor.secondaryLabelColor.withAlphaComponent(0.78)
    )

    static let previewTextColor = SemanticTokens.adaptiveColor(
        light: NSColor.labelColor.withAlphaComponent(0.78),
        dark: NSColor.secondaryLabelColor.withAlphaComponent(0.62)
    )

    // Returns the full border color (base × per-index opacity baked in)
    // so callers no longer need to combine a base token with a separate opacity.
    static func backPlateBorder(index: Int) -> Color {
        let opacity: Double
        switch index {
        case 1: opacity = 0.32
        case 2: opacity = 0.24
        default: opacity = 0.20
        }
        return SemanticTokens.Border.notificationCard.opacity(opacity)
    }

    // Returns the full fill color (base × per-index opacity baked in).
    static func backPlateFill(index: Int) -> Color {
        SemanticTokens.Surface.notificationCardFill
    }

    static func backPlateShade(index: Int) -> Color {
        .clear
    }

    static func backPlateShadowColor(index: Int) -> Color {
        SemanticTokens.adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.12),
            dark: NSColor.black.withAlphaComponent(0.12)
        )
    }

    static func backPlateShadowRadius(index: Int) -> CGFloat {
        4
    }

    static func backPlateShadowYOffset(index: Int) -> CGFloat {
        4
    }

    /// Extra top inset to compensate for upward shadow bleed from the front card.
    /// The front card shadow(radius: 4, y: 4) bleeds ~3pt above the layout top.
    /// Update this if backPlateShadowRadius or backPlateShadowYOffset changes.
    static let collapsedTopShadowCompensation: CGFloat = 3
}
