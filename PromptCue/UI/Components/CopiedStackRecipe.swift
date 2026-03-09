import SwiftUI

// Backtick copied-stack recipe.
// Owns the collapsed copied-section plate math so CardStackView can compose it
// without carrying local opacity and shade decisions inline.
enum CopiedStackRecipe {
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
        CGFloat(indices.max() ?? 0) * PrimitiveTokens.Space.xs + PrimitiveTokens.Space.sm
    }

    static func headerTextColor(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Text.primary.opacity(0.74)
        case .dark:
            return SemanticTokens.Text.secondary.opacity(0.78)
        @unknown default:
            return SemanticTokens.Text.secondary.opacity(0.78)
        }
    }

    static func previewTextColor(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return SemanticTokens.Text.primary.opacity(0.78)
        case .dark:
            return SemanticTokens.Text.secondary.opacity(0.62)
        @unknown default:
            return SemanticTokens.Text.secondary.opacity(0.62)
        }
    }

    static func backPlateBorderOpacity(index: Int, colorScheme: ColorScheme) -> Double {
        switch colorScheme {
        case .light:
            switch index {
            case 1: return 0.32
            case 2: return 0.24
            default: return 0.20
            }
        case .dark:
            switch index {
            case 1: return 0.34
            case 2: return 0.26
            default: return 0.22
            }
        @unknown default:
            return 0.22
        }
    }

    static func backPlateFillOpacity(index: Int, colorScheme: ColorScheme) -> Double {
        switch colorScheme {
        case .light:
            switch index {
            case 1: return 0.26
            case 2: return 0.20
            default: return 0.18
            }
        case .dark:
            switch index {
            case 1: return 0.56
            case 2: return 0.46
            default: return 0.40
            }
        @unknown default:
            return 0.40
        }
    }

    static func backPlateShade(index: Int, colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            switch index {
            case 1: return Color.black.opacity(0.02)
            case 2: return Color.black.opacity(0.04)
            default: return Color.black.opacity(0.05)
            }
        case .dark:
            switch index {
            case 1: return Color.black.opacity(0.14)
            case 2: return Color.black.opacity(0.22)
            default: return Color.black.opacity(0.26)
            }
        @unknown default:
            return Color.black.opacity(0.26)
        }
    }
}
