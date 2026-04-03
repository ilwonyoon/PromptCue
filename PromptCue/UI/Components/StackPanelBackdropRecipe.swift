import SwiftUI

// Backtick stack backdrop recipe.
// Owns density, grayscale, mask, and tint math so StackPanelBackdrop remains a
// pure composition surface.
enum StackPanelBackdropRecipe {
    static let defaultDensityScale = 1.8
    static let defaultGrayscaleBias = 0.0

    private static var cardColumnLeadingRatio: Double {
        StackLayoutMetrics.cardColumnLeadingRatio()
    }

    static func normalizedDensity(_ densityScale: Double) -> Double {
        min(4, max(0.1, densityScale))
    }

    static func grayscaleClamped(_ grayscaleBias: Double) -> Double {
        min(2, max(0, grayscaleBias))
    }

    static func primaryLightDensityOpacity(_ densityScale: Double) -> Double {
        let density = normalizedDensity(densityScale)
        return min(0.78, 0.22 + (density * 0.16))
    }

    static func secondaryLightDensityOpacity(_ densityScale: Double) -> Double {
        let density = normalizedDensity(densityScale)
        return min(0.34, max(0, (density - 1) * 0.18))
    }

    static func mergedLightDensityOpacity(_ densityScale: Double) -> Double {
        min(0.86, primaryLightDensityOpacity(densityScale) + (secondaryLightDensityOpacity(densityScale) * 0.58))
    }

    static func primaryDarkDensityOpacity(_ densityScale: Double) -> Double {
        let density = normalizedDensity(densityScale)
        return min(0.56, 0.08 + (density * 0.14))
    }

    static func secondaryDarkDensityOpacity(_ densityScale: Double) -> Double {
        let density = normalizedDensity(densityScale)
        return min(0.24, max(0, (density - 1) * 0.12))
    }

    static func mergedDarkDensityOpacity(_ densityScale: Double) -> Double {
        min(0.62, primaryDarkDensityOpacity(densityScale) + (secondaryDarkDensityOpacity(densityScale) * 0.62))
    }

    static func atmosphereScale(_ densityScale: Double) -> Double {
        let density = normalizedDensity(densityScale)
        return min(1.1, max(0.25, 0.35 + (density * 0.22)))
    }

    static func maskScale(_ densityScale: Double) -> Double {
        let density = normalizedDensity(densityScale)
        return min(0.85, max(0.18, 0.18 + (density * 0.20)))
    }

    static func lightLeadingTint(_ grayscaleBias: Double) -> Color {
        PanelBackdropFamily.lightLeadingTint(grayscaleBias)
    }

    static func lightMidTint(_ grayscaleBias: Double) -> Color {
        PanelBackdropFamily.lightMidTint(grayscaleBias)
    }

    static func lightTrailingTint(_ grayscaleBias: Double) -> Color {
        PanelBackdropFamily.lightTrailingTint(grayscaleBias)
    }

    static var lightTopTint: Color {
        PanelBackdropFamily.lightTopTint
    }

    static func lightBottomTint(_ grayscaleBias: Double) -> Color {
        PanelBackdropFamily.lightBottomTint(grayscaleBias)
    }

    static func lightDensityMask(maskScale: Double) -> LinearGradient {
        let cardLead = cardColumnLeadingRatio
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: max(0.04, cardLead - 0.10)),
                .init(color: .white.opacity(0.16 * maskScale), location: max(0.08, cardLead - 0.04)),
                .init(color: .white.opacity(0.72 * maskScale), location: max(0.14, cardLead + 0.08)),
                .init(color: .white, location: max(0.22, cardLead + 0.18)),
                .init(color: .white, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func lightAtmosphereMask(maskScale: Double) -> LinearGradient {
        let cardLead = cardColumnLeadingRatio
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.12 * maskScale), location: max(0.05, cardLead - 0.06)),
                .init(color: .white.opacity(0.58 * maskScale), location: max(0.11, cardLead + 0.06)),
                .init(color: .white.opacity(0.92 * maskScale), location: max(0.18, cardLead + 0.16)),
                .init(color: .white, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func darkDensityMask(maskScale: Double) -> LinearGradient {
        let cardLead = cardColumnLeadingRatio
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.20 * maskScale), location: max(0.04, cardLead * 0.30)),
                .init(color: .white.opacity(0.78 * maskScale), location: max(0.10, cardLead * 0.62)),
                .init(color: .white.opacity(0.94 * maskScale), location: max(0.15, cardLead - 0.01)),
                .init(color: .white, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func edgeFadeMask(maskScale: Double) -> LinearGradient {
        let cardLead = cardColumnLeadingRatio
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.10 * maskScale), location: max(0.025, cardLead * 0.18)),
                .init(color: .white.opacity(0.40 * maskScale), location: max(0.06, cardLead * 0.42)),
                .init(color: .white.opacity(0.82 * maskScale), location: max(0.11, cardLead - 0.02)),
                .init(color: .white, location: max(0.15, cardLead + 0.02)),
                .init(color: .white, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
