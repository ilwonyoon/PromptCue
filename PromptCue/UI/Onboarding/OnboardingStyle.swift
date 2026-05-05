import SwiftUI

/// iOS-native styling primitives for onboarding only. The rest of the app
/// keeps its BW monochrome treatment per CLAUDE.md; onboarding is the
/// first-impression surface where Apple-feeling color, type, and spacing
/// help users orient before they enter the minimal core UI.
enum OnboardingStyle {
    enum Spacing {
        // Vertical rhythm — onboarding picks one of these per gap, no
        // arbitrary integers in views.
        static let titleToBody: CGFloat = PrimitiveTokens.Space.xs       // 8
        static let stackedItems: CGFloat = PrimitiveTokens.Space.xs + 2  // 10
        static let heroToTitle: CGFloat = PrimitiveTokens.Space.md       // 16
        static let sectionBlock: CGFloat = PrimitiveTokens.Space.lg + 4  // 24
        static let sectionGap: CGFloat = PrimitiveTokens.Space.lg * 2    // 40
        static let edgePadding: CGFloat = PrimitiveTokens.Space.lg + 8   // 28
        static let cardInner: CGFloat = PrimitiveTokens.Space.md         // 16
    }

    enum Radius {
        static let card: CGFloat = 14
        static let button: CGFloat = 12
        static let icon: CGFloat = 18
    }

    /// Onboarding reuses the project's PrimitiveTokens.Typography scale.
    /// Backtick's design system caps display text at 15pt — chrome stays
    /// compact and macOS-native.
    ///
    /// Headings sit at 15pt **medium**, not semibold. The project's
    /// `panelTitle` (15pt semibold) is sized for dense Settings panels
    /// where it competes with surrounding text; in an onboarding hero
    /// where the title stands alone the same weight reads heavier than
    /// in Settings. `bodyStrong` keeps the rhythm without the visual
    /// thickness.
    enum Typography {
        // Hero / step heading — single big label per screen, can carry weight.
        static let largeTitle = PrimitiveTokens.Typography.bodyStrong  // 15pt medium
        static let title = PrimitiveTokens.Typography.bodyStrong       // 15pt medium

        // List row title — sits next to a descriptor and an icon, so it
        // should match Settings/Reminders list rows: body sized, semibold-
        // ish but not large. Using metaStrong (13pt semibold) keeps the
        // row tight and matches Backtick's compact chrome.
        static let headline = PrimitiveTokens.Typography.metaStrong    // 13pt semibold
        static let body = PrimitiveTokens.Typography.body              // 15pt regular
        static let subheadline = PrimitiveTokens.Typography.meta       // 13pt regular
        static let footnote = PrimitiveTokens.Typography.meta          // 13pt regular
        static let caption = PrimitiveTokens.Typography.metaMedium     // 13pt medium
    }

    enum Surface {
        /// Window-level background — slightly tinted neutral, like
        /// `systemGroupedBackground` on iOS.
        static let groupedBackground = SemanticTokens.adaptiveColor(
            light: NSColor(white: 0.95, alpha: 1.0),
            dark: NSColor(white: 0.10, alpha: 1.0)
        )

        /// Card / inset list row background.
        static let card = SemanticTokens.adaptiveColor(
            light: NSColor.white,
            dark: NSColor(white: 0.16, alpha: 1.0)
        )

        /// Highlighted (hover) card.
        static let cardHover = SemanticTokens.adaptiveColor(
            light: NSColor(white: 0.97, alpha: 1.0),
            dark: NSColor(white: 0.20, alpha: 1.0)
        )
    }

    enum Accent {
        /// System accent — used for primary actions in onboarding.
        /// Core UI keeps BW; onboarding gets controlAccentColor for an
        /// Apple-native feel on its first-impression surfaces.
        static let primary = Color(nsColor: .controlAccentColor)
    }
}

// MARK: - Reusable view modifiers

struct OnboardingCardStyle: ViewModifier {
    var isHovering: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.vertical, OnboardingStyle.Spacing.cardInner - 2)
            .padding(.horizontal, OnboardingStyle.Spacing.cardInner)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OnboardingStyle.Radius.card, style: .continuous)
                    .fill(isHovering
                          ? OnboardingStyle.Surface.cardHover
                          : OnboardingStyle.Surface.card)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func onboardingCard(isHovering: Bool = false) -> some View {
        modifier(OnboardingCardStyle(isHovering: isHovering))
    }
}

// MARK: - Primary CTA wrappers
//
// We delegate to the system `.borderedProminent` + `.controlSize(.large)`
// styles so macOS 26 (Tahoe) gets its native Liquid Glass treatment for
// free, while older macOS releases still get an appropriate prominent
// button. Accent tint is overridable via `.tint(...)`.

struct OnboardingPrimaryButton<Label: View>: View {
    let action: () -> Void
    let labelView: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.labelView = label()
    }

    var body: some View {
        Button(action: action) {
            labelView
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(OnboardingStyle.Accent.primary)
    }
}

extension OnboardingPrimaryButton where Label == Text {
    init(_ title: String, action: @escaping () -> Void) {
        self.init(action: action) { Text(title) }
    }
}

struct OnboardingSecondaryButton<Label: View>: View {
    let action: () -> Void
    let labelView: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.labelView = label()
    }

    var body: some View {
        Button(action: action) {
            labelView
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

extension OnboardingSecondaryButton where Label == Text {
    init(_ title: String, action: @escaping () -> Void) {
        self.init(action: action) { Text(title) }
    }
}
