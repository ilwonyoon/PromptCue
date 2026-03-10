import SwiftUI

// Backtick stack backdrop pattern.
// This file owns atmospheric blur, density, and edge fade for the stack panel only.
struct StackPanelBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    let densityScale: Double
    let grayscaleBias: Double

    static let defaultDensityScale = StackPanelBackdropRecipe.defaultDensityScale
    static let defaultGrayscaleBias = StackPanelBackdropRecipe.defaultGrayscaleBias

    init(
        densityScale: Double = StackPanelBackdrop.defaultDensityScale,
        grayscaleBias: Double = StackPanelBackdrop.defaultGrayscaleBias
    ) {
        self.densityScale = densityScale
        self.grayscaleBias = grayscaleBias
    }

    var body: some View {
        backdropLayers
            .mask(StackPanelBackdropRecipe.edgeFadeMask(maskScale: maskScale))
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
                    appearanceName: nil
                )

                VisualEffectBackdrop(
                    material: .underWindowBackground,
                    blendingMode: .withinWindow,
                    appearanceName: nil
                )
                .opacity(StackPanelBackdropRecipe.mergedLightDensityOpacity(densityScale))
                .mask(StackPanelBackdropRecipe.lightDensityMask(maskScale: maskScale))

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.010 * atmosphereScale),
                        Color.white.opacity(0.006 * atmosphereScale),
                        Color.white.opacity(0.018 * atmosphereScale),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(StackPanelBackdropRecipe.lightAtmosphereMask(maskScale: maskScale))

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.014 * atmosphereScale),
                        Color.clear,
                        Color.black.opacity(0.008 * atmosphereScale),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask(StackPanelBackdropRecipe.lightAtmosphereMask(maskScale: maskScale))
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
                .opacity(StackPanelBackdropRecipe.mergedDarkDensityOpacity(densityScale))
                .mask(StackPanelBackdropRecipe.darkDensityMask(maskScale: maskScale))

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.004 * atmosphereScale),
                        Color.black.opacity(0.012 * atmosphereScale),
                        Color.black.opacity(0.032 * atmosphereScale),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.012 * atmosphereScale),
                        Color.clear,
                        Color.black.opacity(0.03 * atmosphereScale),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var atmosphereScale: Double {
        StackPanelBackdropRecipe.atmosphereScale(densityScale)
    }

    private var maskScale: Double {
        StackPanelBackdropRecipe.maskScale(densityScale)
    }
}
