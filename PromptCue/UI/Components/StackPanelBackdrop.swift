import SwiftUI

// Backtick stack backdrop pattern.
// This file owns atmospheric blur, density, and edge fade for the stack panel only.
struct StackPanelBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    let densityScale: Double
    let grayscaleBias: Double

    static let defaultDensityScale = 4.0
    static let defaultGrayscaleBias = 2.0

    init(
        densityScale: Double = StackPanelBackdrop.defaultDensityScale,
        grayscaleBias: Double = StackPanelBackdrop.defaultGrayscaleBias
    ) {
        self.densityScale = densityScale
        self.grayscaleBias = grayscaleBias
    }

    var body: some View {
        backdropLayers
            .mask(edgeFadeMask)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var backdropLayers: some View {
        if colorScheme == .light {
            ZStack {
                VisualEffectBackdrop(
                    material: .underWindowBackground,
                    blendingMode: .behindWindow,
                    appearanceName: .vibrantLight
                )

                VisualEffectBackdrop(
                    material: .underWindowBackground,
                    blendingMode: .withinWindow,
                    appearanceName: .vibrantLight
                )
                .opacity(primaryLightDensityOpacity)
                .mask(lightDensityMask)

                if secondaryLightDensityOpacity > 0 {
                    VisualEffectBackdrop(
                        material: .underWindowBackground,
                        blendingMode: .withinWindow,
                        appearanceName: .vibrantLight
                    )
                    .opacity(secondaryLightDensityOpacity)
                    .mask(lightDensityMask)
                }

                LinearGradient(
                    colors: [
                        lightTopTint.opacity(0.01 * atmosphereScale),
                        Color.clear,
                        lightBottomTint.opacity(0.02 * atmosphereScale),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        lightLeadingTint.opacity(0.01 * atmosphereScale),
                        lightMidTint.opacity(0.03 * atmosphereScale),
                        lightTrailingTint.opacity(0.08 * atmosphereScale),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        } else {
            ZStack {
                VisualEffectBackdrop(
                    material: .underWindowBackground,
                    blendingMode: .behindWindow,
                    appearanceName: .vibrantDark
                )

                VisualEffectBackdrop(
                    material: .hudWindow,
                    blendingMode: .withinWindow,
                    appearanceName: .vibrantDark
                )
                .opacity(primaryDarkDensityOpacity)
                .mask(darkDensityMask)

                if secondaryDarkDensityOpacity > 0 {
                    VisualEffectBackdrop(
                        material: .hudWindow,
                        blendingMode: .withinWindow,
                        appearanceName: .vibrantDark
                    )
                    .opacity(secondaryDarkDensityOpacity)
                    .mask(darkDensityMask)
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.01 * atmosphereScale),
                        Color.black.opacity(0.04 * atmosphereScale),
                        Color.black.opacity(0.10 * atmosphereScale),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.04 * atmosphereScale),
                        Color.clear,
                        Color.black.opacity(0.09 * atmosphereScale),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var lightDensityMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.04 * maskScale), location: 0.18),
                .init(color: .white.opacity(0.22 * maskScale), location: 0.42),
                .init(color: .white.opacity(0.62 * maskScale), location: 0.74),
                .init(color: .white, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var darkDensityMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.12 * maskScale), location: 0.22),
                .init(color: .white.opacity(0.58 * maskScale), location: 0.56),
                .init(color: .white, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.06 * maskScale), location: 0.16),
                .init(color: .white.opacity(0.28 * maskScale), location: 0.38),
                .init(color: .white.opacity(0.70 * maskScale), location: 0.66),
                .init(color: .white, location: 0.82),
                .init(color: .white, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var normalizedDensity: Double {
        min(4, max(0.1, densityScale))
    }

    private var primaryLightDensityOpacity: Double {
        min(1, 0.36 + (normalizedDensity * 0.34))
    }

    private var secondaryLightDensityOpacity: Double {
        min(0.78, max(0, (normalizedDensity - 1) * 0.62))
    }

    private var primaryDarkDensityOpacity: Double {
        min(1, 0.42 + (normalizedDensity * 0.40))
    }

    private var secondaryDarkDensityOpacity: Double {
        min(0.88, max(0, (normalizedDensity - 1) * 0.70))
    }

    private var atmosphereScale: Double {
        min(1.8, max(0.4, 0.55 + (normalizedDensity * 0.45)))
    }

    private var maskScale: Double {
        min(1, max(0.12, 0.18 + (normalizedDensity * 0.32)))
    }

    private var grayscaleClamped: Double {
        min(2, max(0, grayscaleBias))
    }

    private var lightLeadingTint: Color {
        Color(white: min(1, 0.90 + (grayscaleClamped * 0.10)))
    }

    private var lightMidTint: Color {
        Color(white: min(1, 0.84 + (grayscaleClamped * 0.14)))
    }

    private var lightTrailingTint: Color {
        Color(white: min(1, 0.74 + (grayscaleClamped * 0.22)))
    }

    private var lightTopTint: Color {
        Color(white: 0.98)
    }

    private var lightBottomTint: Color {
        Color(white: min(1, 0.42 + (grayscaleClamped * 0.29)))
    }
}
