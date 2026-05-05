import SwiftUI

struct OnboardingKeycap: View {
    let label: String
    var size: CGFloat = 32

    var body: some View {
        Text(label)
            .font(.system(size: size * 0.45, weight: .medium, design: .monospaced))
            .foregroundStyle(SemanticTokens.Text.primary)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SemanticTokens.Surface.raisedFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(SemanticTokens.Border.notificationCard, lineWidth: 1)
            )
    }
}

struct OnboardingShortcutBadge: View {
    let keys: [String]
    let caption: String?

    init(keys: [String], caption: String? = nil) {
        self.keys = keys
        self.caption = caption
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    OnboardingKeycap(label: key)

                    if index < keys.count - 1 {
                        Text("+")
                            .font(.caption)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                    }
                }
            }

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(SemanticTokens.Text.secondary)
            }
        }
    }
}
