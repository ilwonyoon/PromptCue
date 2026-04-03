import AppKit
import SwiftUI

enum SemanticTokens {
    enum MaterialStyle {
        static let floatingShell = Material.thinMaterial
        static let elevatedGlass = Material.regularMaterial
        static let notificationCard = Material.thickMaterial
    }

    enum Surface {
        static let panelFill = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.32),
            dark: NSColor.white.withAlphaComponent(0.16)
        )
        static let captureShellFill = adaptiveColor(
            light: PanelBackdropFamily.captureShellFillLight,
            dark: PanelBackdropFamily.captureShellFillDark
        )
        static let captureShellStroke = adaptiveColor(
            light: PanelBackdropFamily.captureShellStrokeLight,
            dark: PanelBackdropFamily.captureShellStrokeDark
        )
        static let captureShellTopHighlight = adaptiveColor(
            light: PanelBackdropFamily.captureShellTopHighlightLight,
            dark: PanelBackdropFamily.captureShellTopHighlightDark
        )
        static let captureShellScreenshotFill = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.68),
            dark: NSColor.white.withAlphaComponent(0.08)
        )
        static let captureShellScreenshotBorder = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.12)
        )
        static let captureShellScreenshotLoadingFill = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.44),
            dark: NSColor.white.withAlphaComponent(0.06)
        )
        static let cardFill = Color(nsColor: .controlBackgroundColor).opacity(PrimitiveTokens.Opacity.surface)
        static let notificationCardFill = adaptiveColor(
            light: NSColor(calibratedWhite: 0.965, alpha: 1.0),
            dark: NSColor(calibratedWhite: 0.12, alpha: 1.0)
        )
        static let notificationCardEmphasizedFill = adaptiveColor(
            light: NSColor.white,
            dark: NSColor(calibratedWhite: 0.10, alpha: 1.0)
        )
        static let notificationCardBackdrop = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.02),
            dark: NSColor.white.withAlphaComponent(0.006)
        )
        static let notificationCardHoverFill = adaptiveColor(
            light: .clear,
            dark: .clear
        )
        static let notificationStackPlateBase = adaptiveColor(
            light: NSColor.windowBackgroundColor.withAlphaComponent(0.70),
            dark: NSColor(calibratedWhite: 0.10, alpha: 0.96)
        )
        static let stackPanelBackdropTint = adaptiveColor(
            light: NSColor.underPageBackgroundColor.withAlphaComponent(0.92),
            dark: NSColor.windowBackgroundColor.withAlphaComponent(0.32)
        )
        static let stackPanelGradientTop = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.12),
            dark: NSColor.white.withAlphaComponent(0.12)
        )
        static let stackPanelGradientBottom = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.04),
            dark: NSColor.black.withAlphaComponent(0.08)
        )
        static let raisedFill = Color(nsColor: .textBackgroundColor).opacity(PrimitiveTokens.Opacity.raisedSurface)
        static let accentFill = Accent.primary.opacity(PrimitiveTokens.Opacity.faint)
        static let glassTint = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.16),
            dark: NSColor.white.withAlphaComponent(0.18)
        )
        static let glassSheen = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.34),
            dark: NSColor.white.withAlphaComponent(0.28)
        )
        static let glassEdge = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.12),
            dark: NSColor.white.withAlphaComponent(0.12)
        )
        static let previewBackdropTop = Color(nsColor: .underPageBackgroundColor)
        static let previewBackdropBottom = Color(nsColor: .windowBackgroundColor)
        static let previewOrbPrimary = Accent.primary.opacity(0.18)
        static let previewOrbSecondary = Accent.selection.opacity(0.12)
    }

    enum Text {
        static let primary = Color(nsColor: .labelColor)
        static let secondary = Color(nsColor: .secondaryLabelColor)
        static let accent = Accent.primary
        static let selection = Accent.selection
    }

    enum Border {
        static let subtle = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.08),
            dark: NSColor.white.withAlphaComponent(0.035)
        )
        static let notificationCard = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.12),
            dark: NSColor.white.withAlphaComponent(0.06)
        )
        static let notificationCardHover = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.18),
            dark: NSColor.white.withAlphaComponent(0.08)
        )
        static let emphasis = Accent.selection.opacity(PrimitiveTokens.Opacity.subtle)
        static let glassHighlight = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.52),
            dark: NSColor.white.withAlphaComponent(0.44)
        )
        static let glassInner = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.38),
            dark: NSColor.white.withAlphaComponent(0.18)
        )
    }

    enum Accent {
        static let primary = Color(nsColor: .controlAccentColor)
        static let selection = Color(nsColor: .selectedContentBackgroundColor)
    }

    enum Shadow {
        static let color = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.black.withAlphaComponent(0.20)
        )
        static let glassAmbient = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.08),
            dark: NSColor.black.withAlphaComponent(0.08)
        )
        static let panelAmbient = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.09),
            dark: NSColor.black.withAlphaComponent(PrimitiveTokens.Opacity.faint)
        )
        static let panelKey = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.12),
            dark: NSColor.black.withAlphaComponent(PrimitiveTokens.Opacity.faint)
        )
        static let captureShellAmbient = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.16),
            dark: NSColor.black.withAlphaComponent(0.28)
        )
        static let captureShellKey = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.22),
            dark: NSColor.black.withAlphaComponent(0.36)
        )
    }

    enum Classification {
        static let interactiveText = adaptiveColor(
            light: NSColor.systemBlue.withAlphaComponent(0.72),
            dark: NSColor.systemBlue.withAlphaComponent(0.68)
        )
        static let interactiveHoverText = adaptiveColor(
            light: NSColor.systemBlue.withAlphaComponent(0.90),
            dark: NSColor.systemBlue.withAlphaComponent(0.85)
        )
        static let secretText = adaptiveColor(
            light: NSColor.secondaryLabelColor.withAlphaComponent(0.50),
            dark: NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        )
        static let interactiveHoverUnderline = adaptiveColor(
            light: NSColor.systemBlue.withAlphaComponent(0.40),
            dark: NSColor.systemBlue.withAlphaComponent(0.35)
        )
    }

    static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                resolvedAdaptiveNSColor(light: light, dark: dark, appearance: appearance)
            }
        )
    }

    static func resolvedAdaptiveColor(
        light: NSColor,
        dark: NSColor,
        appearance: NSAppearance? = NSApp.effectiveAppearance
    ) -> Color {
        Color(nsColor: resolvedAdaptiveNSColor(light: light, dark: dark, appearance: appearance))
    }

    static func resolvedAdaptiveNSColor(
        light: NSColor,
        dark: NSColor,
        appearance: NSAppearance? = NSApp.effectiveAppearance
    ) -> NSColor {
        let bestMatch = appearance?.bestMatch(
            from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]
        )

        let selectedColor: NSColor
        switch bestMatch {
        case .darkAqua, .vibrantDark:
            selectedColor = dark
        default:
            selectedColor = light
        }

        guard let appearance else {
            return selectedColor
        }

        var resolvedColor = selectedColor
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = selectedColor.usingColorSpace(.deviceRGB) ?? selectedColor
        }
        return resolvedColor
    }
}
