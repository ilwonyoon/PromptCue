import AppKit
import SwiftUI

enum SettingsSemanticTokens {
    enum Text {
        static let primary = Color(nsColor: .labelColor)
        static let secondary = Color(nsColor: .secondaryLabelColor)
        static let selected = Color.white
    }

    enum Surface {
        static let sidebarBackground = adaptiveColor(
            light: NSColor(srgbRed: 225.0 / 255.0, green: 224.0 / 255.0, blue: 223.0 / 255.0, alpha: 1.0),
            dark: NSColor(srgbRed: 43.0 / 255.0, green: 42.0 / 255.0, blue: 39.0 / 255.0, alpha: 1.0)
        )
        static let sidebarBackgroundTopTint = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.16),
            dark: NSColor.white.withAlphaComponent(0.05)
        )
        static let sidebarBackgroundBottomShade = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.02),
            dark: NSColor.black.withAlphaComponent(0.18)
        )
        static let sidebarHoverFill = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.055),
            dark: NSColor.white.withAlphaComponent(0.085)
        )
        static let contentBackground = adaptiveColor(
            light: NSColor.textBackgroundColor,
            dark: NSColor(srgbRed: 31.0 / 255.0, green: 31.0 / 255.0, blue: 30.0 / 255.0, alpha: 1.0)
        )
        static let formGroupFill = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.018),
            dark: NSColor.white.withAlphaComponent(0.05)
        )
        static let inlinePanelFill = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.60),
            dark: NSColor.white.withAlphaComponent(0.06)
        )
        static let sidebarIconHighlight = adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.22),
            dark: NSColor.white.withAlphaComponent(0.16)
        )
        static let sidebarIconShade = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.08),
            dark: NSColor.black.withAlphaComponent(0.14)
        )
        static let statusBadgeNeutralFill = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.05),
            dark: NSColor.white.withAlphaComponent(0.07)
        )
    }

    enum Border {
        static let paneDivider = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.05),
            dark: NSColor.white.withAlphaComponent(0.08)
        )
        static let formGroup = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.05),
            dark: NSColor.white.withAlphaComponent(0.08)
        )
        static let rowSeparator = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.05),
            dark: NSColor.white.withAlphaComponent(0.08)
        )
        static let sidebarIconStroke = adaptiveColor(
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.12)
        )
    }

    enum Accent {
        static let selection = Color(nsColor: .selectedContentBackgroundColor)
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                switch appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]) {
                case .darkAqua, .vibrantDark:
                    return dark
                default:
                    return light
                }
            }
        )
    }
}
