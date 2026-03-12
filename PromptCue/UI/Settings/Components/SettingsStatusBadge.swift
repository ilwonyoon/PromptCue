import SwiftUI

struct SettingsStatusBadge: View {
    enum Tone {
        case neutral
        case accent
        case success
        case warning
        case danger
    }

    let title: String
    let tone: Tone

    var body: some View {
        HStack(spacing: PrimitiveTokens.Space.xxxs) {
            Circle()
                .fill(tone.dotColor)
                .frame(
                    width: SettingsTokens.Layout.statusBadgeDotSize,
                    height: SettingsTokens.Layout.statusBadgeDotSize
                )

            Text(title)
                .font(SettingsTokens.Typography.supportingStrong)
                .foregroundStyle(tone.foregroundColor)
        }
        .padding(.horizontal, PrimitiveTokens.Space.xs)
        .padding(.vertical, PrimitiveTokens.Space.xxxs)
        .background(tone.fillColor)
        .clipShape(Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(tone.borderColor, lineWidth: PrimitiveTokens.Stroke.subtle)
        }
    }
}

private extension SettingsStatusBadge.Tone {
    var dotColor: Color {
        switch self {
        case .neutral:
            return SettingsSemanticTokens.Text.secondary
        case .accent:
            return Color(nsColor: .systemBlue)
        case .success:
            return Color(nsColor: .systemGreen)
        case .warning:
            return Color(nsColor: .systemOrange)
        case .danger:
            return Color(nsColor: .systemRed)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .neutral:
            return SettingsSemanticTokens.Text.secondary
        case .accent, .success, .warning, .danger:
            return SettingsSemanticTokens.Text.primary
        }
    }

    var fillColor: Color {
        switch self {
        case .neutral:
            return SettingsSemanticTokens.Surface.statusBadgeNeutralFill
        case .accent:
            return Color(nsColor: .systemBlue).opacity(0.12)
        case .success:
            return Color(nsColor: .systemGreen).opacity(0.12)
        case .warning:
            return Color(nsColor: .systemOrange).opacity(0.14)
        case .danger:
            return Color(nsColor: .systemRed).opacity(0.12)
        }
    }

    var borderColor: Color {
        switch self {
        case .neutral:
            return SettingsSemanticTokens.Border.formGroup
        case .accent:
            return Color(nsColor: .systemBlue).opacity(0.22)
        case .success:
            return Color(nsColor: .systemGreen).opacity(0.22)
        case .warning:
            return Color(nsColor: .systemOrange).opacity(0.22)
        case .danger:
            return Color(nsColor: .systemRed).opacity(0.22)
        }
    }
}
