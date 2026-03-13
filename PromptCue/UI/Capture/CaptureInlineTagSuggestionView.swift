import SwiftUI

struct CaptureInlineTagSuggestionView: View {
    let suggestions: [String]
    let selectedIndex: Int
    let onSelectSuggestion: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    onSelectSuggestion(suggestion)
                } label: {
                    tagRow(
                        title: "#\(suggestion)",
                        isSelected: index == selectedIndex
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PrimitiveTokens.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                .fill(SemanticTokens.Surface.notificationCardFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                .stroke(SemanticTokens.Border.subtle)
        }
        .shadow(
            color: Color.black.opacity(0.08),
            radius: PrimitiveTokens.Shadow.floatingControlBlur,
            y: PrimitiveTokens.Shadow.floatingControlY
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagRow(
        title: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: PrimitiveTokens.Space.xs) {
            PromptCueChip(
                fill: isSelected
                    ? SemanticTokens.Accent.primary.opacity(0.18)
                    : SemanticTokens.Surface.accentFill,
                border: isSelected
                    ? SemanticTokens.Border.emphasis
                    : SemanticTokens.Border.subtle
            ) {
                Text(title)
                    .font(PrimitiveTokens.Typography.chip)
                    .foregroundStyle(
                        isSelected
                            ? SemanticTokens.Text.accent
                            : SemanticTokens.Text.primary
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PrimitiveTokens.Space.xxs)
        .padding(.vertical, PrimitiveTokens.Space.xxxs)
        .contentShape(Rectangle())
    }
}
