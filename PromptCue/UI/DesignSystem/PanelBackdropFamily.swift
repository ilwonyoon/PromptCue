import AppKit
import SwiftUI

// Shared panel-backdrop family for Backtick.
// Capture and stack should feel related without becoming visually identical.
enum PanelBackdropFamily {
    static func normalizedBias(_ grayscaleBias: Double) -> Double {
        min(2, max(0, grayscaleBias))
    }

    static func lightLeadingTint(_ grayscaleBias: Double) -> Color {
        Color(white: min(1, 0.985 + (normalizedBias(grayscaleBias) * 0.007)))
    }

    static func lightMidTint(_ grayscaleBias: Double) -> Color {
        Color(white: min(1, 0.978 + (normalizedBias(grayscaleBias) * 0.008)))
    }

    static func lightTrailingTint(_ grayscaleBias: Double) -> Color {
        Color(white: min(1, 0.968 + (normalizedBias(grayscaleBias) * 0.012)))
    }

    static var lightTopTint: Color {
        Color(white: 0.995)
    }

    static func lightBottomTint(_ grayscaleBias: Double) -> Color {
        Color(white: min(1, 0.955 + (normalizedBias(grayscaleBias) * 0.015)))
    }

    static var captureShellFillLight: NSColor {
        NSColor(calibratedWhite: 0.97, alpha: 0.92)
    }

    static var captureShellFillDark: NSColor {
        NSColor(calibratedWhite: 0.17, alpha: 0.94)
    }

    static var captureShellStrokeLight: NSColor {
        NSColor.black.withAlphaComponent(0.10)
    }

    static var captureShellStrokeDark: NSColor {
        NSColor.white.withAlphaComponent(0.08)
    }

    static var captureShellTopHighlightLight: NSColor {
        NSColor.white.withAlphaComponent(0.80)
    }

    static var captureShellTopHighlightDark: NSColor {
        NSColor.white.withAlphaComponent(0.05)
    }
}
