import AppKit
import SwiftUI

enum SemanticTokens {
    enum MaterialStyle {
        static let floatingShell = Material.thinMaterial
        static let elevatedGlass = Material.regularMaterial
        static let notificationCard = Material.thickMaterial
    }

    enum Surface {
        static let panelFill = Color.white.opacity(0.16)
        static let cardFill = Color(nsColor: .controlBackgroundColor).opacity(PrimitiveTokens.Opacity.surface)
        static let notificationCardFill = Color(nsColor: .windowBackgroundColor).opacity(0.80)
        static let notificationCardBackdrop = Color(nsColor: .windowBackgroundColor).opacity(0.34)
        static let stackPanelBackdropTint = Color(nsColor: .windowBackgroundColor).opacity(0.32)
        static let stackPanelGradientTop = Color.white.opacity(0.12)
        static let stackPanelGradientBottom = Color.black.opacity(0.08)
        static let raisedFill = Color(nsColor: .textBackgroundColor).opacity(PrimitiveTokens.Opacity.raisedSurface)
        static let accentFill = Accent.primary.opacity(PrimitiveTokens.Opacity.faint)
        static let glassTint = Color.white.opacity(0.18)
        static let glassSheen = Color.white.opacity(0.28)
        static let glassEdge = Color.white.opacity(0.12)
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
        static let subtle = Color(nsColor: .separatorColor).opacity(PrimitiveTokens.Opacity.soft)
        static let notificationCard = Color.white.opacity(0.14)
        static let emphasis = Accent.selection.opacity(PrimitiveTokens.Opacity.subtle)
        static let glassHighlight = Color.white.opacity(0.44)
        static let glassInner = Color.white.opacity(0.18)
    }

    enum Accent {
        static let primary = Color(nsColor: .controlAccentColor)
        static let selection = Color(nsColor: .selectedContentBackgroundColor)
    }

    enum Shadow {
        static let color = Color.black.opacity(PrimitiveTokens.Opacity.faint)
        static let glassAmbient = Color.black.opacity(0.08)
    }
}
