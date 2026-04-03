import AppKit
import SwiftUI

// Backtick stack-card pattern surface.
// Keep stack card chrome independent from stack backdrop ownership.
struct StackNotificationCardSurface<Content: View>: View {
    let isSelected: Bool
    let isEmphasized: Bool
    let contentPadding: EdgeInsets
    let cornerRadius: CGFloat
    @ViewBuilder private var content: Content

    init(
        isSelected: Bool = false,
        isEmphasized: Bool = false,
        contentPadding: EdgeInsets = EdgeInsets(
            top: StackLayoutMetrics.cardContentInset,
            leading: StackLayoutMetrics.cardContentInset,
            bottom: StackLayoutMetrics.cardContentInset,
            trailing: StackLayoutMetrics.cardContentInset
        ),
        cornerRadius: CGFloat = PrimitiveTokens.Radius.md,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isEmphasized = isEmphasized
        self.contentPadding = contentPadding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        CardSurface(
            backgroundFill: backgroundFill,
            borderColor: borderColor,
            borderLineWidth: isSelected ? 2.0 : PrimitiveTokens.Stroke.subtle,
            contentPadding: contentPadding,
            cornerRadius: cornerRadius
        ) {
            content
        }
    }

    private var backgroundFill: Color {
        if isSelected {
            return SemanticTokens.Surface.notificationCardEmphasizedFill
        }

        if isEmphasized {
            return SemanticTokens.Surface.notificationCardEmphasizedFill
        }

        return SemanticTokens.Surface.notificationCardFill
    }

    private var defaultBorderColor: Color {
        SemanticTokens.Border.subtle
    }

    private var borderColor: Color {
        if isSelected {
            return SemanticTokens.adaptiveColor(
                light: NSColor.black.withAlphaComponent(0.5),
                dark: NSColor.white.withAlphaComponent(0.7)
            )
        }

        if isEmphasized {
            return SemanticTokens.Border.notificationCardHover
        }

        return defaultBorderColor
    }
}
