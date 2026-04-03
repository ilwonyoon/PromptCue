import SwiftUI

// Backtick copied-stack recipe.
// Owns the collapsed copied-section plate math so CardStackView can compose it
// without carrying local opacity and shade decisions inline.
// Only owns collapsed copied-stack geometry and depth. The visible front card
// should use the same surface treatment as a normal stack card.
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

    static func collapsedLeadingInset(for index: Int) -> CGFloat {
        StackLayoutMetrics.copiedBackPlateLeadingInset(for: index)
    }

    static func backPlateBorder(index: Int) -> Color {
        SemanticTokens.Border.notificationCard
    }

    static func backPlateFill(index: Int) -> Color {
        SemanticTokens.Surface.notificationCardFill
    }

    static func backPlateShade(index: Int) -> Color {
        .clear
    }

    static func backPlateShadowColor(index: Int) -> Color {
        switch index {
        case 1:
            return SemanticTokens.adaptiveColor(
                light: .black.withAlphaComponent(0.12),
                dark: .black.withAlphaComponent(0.18)
            )
        default:
            return SemanticTokens.adaptiveColor(
                light: .black.withAlphaComponent(0.08),
                dark: .black.withAlphaComponent(0.12)
            )
        }
    }

    static func backPlateShadowRadius(index: Int) -> CGFloat {
        switch index {
        case 1: return 8
        default: return 6
        }
    }

    static func backPlateShadowYOffset(index: Int) -> CGFloat {
        switch index {
        case 1: return 6
        default: return 4
        }
    }

    /// Extra top inset to compensate for upward shadow bleed from the front card.
    /// The front card shadow(radius: 4, y: 4) bleeds ~3pt above the layout top.
    /// Update this if backPlateShadowRadius or backPlateShadowYOffset changes.
    static let collapsedTopShadowCompensation: CGFloat = 3
}
