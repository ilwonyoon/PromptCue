import SwiftUI

struct OnboardingFlowStoryView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        OnboardingStepChrome(progress: (current: 4, total: 4)) {
            VStack(spacing: PrimitiveTokens.Space.md) {
                Text("Your day with Backtick")
                    .font(OnboardingStyle.Typography.title)
                    .foregroundStyle(SemanticTokens.Text.primary)

                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                    StoryStep(number: "1", text: "You're coding in Cursor / VSCode / wherever.")
                    StoryStep(number: "2", text: "A prompt idea pops. Hit ⌘+` — drop, gone in <1s.")
                    StoryStep(number: "3", text: "Later, ⌘+2 opens Stack. Copy. Paste. Move on.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PrimitiveTokens.Space.md)
                .background(
                    RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                        .fill(SemanticTokens.Surface.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                        .stroke(SemanticTokens.Border.notificationCard, lineWidth: 1)
                )

                HStack(spacing: PrimitiveTokens.Space.lg) {
                    OnboardingShortcutBadge(keys: ["⌘", "`"], caption: "Capture")
                    OnboardingShortcutBadge(keys: ["⌘", "2"], caption: "Stack")
                }
                .frame(maxWidth: .infinity)
            }
        } footer: {
            VStack(spacing: PrimitiveTokens.Space.xs) {
                Button("Done") {
                    state.finish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Try Lane 1 instead — connect AI memory") {
                    state.advanceTo(.lane1PickMainAI)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .font(OnboardingStyle.Typography.subheadline)
            }
        }
    }
}

private struct StoryStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: PrimitiveTokens.Space.xs) {
            Text(number)
                .font(PrimitiveTokens.Typography.codeStrong)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .frame(width: 16, alignment: .leading)

            Text(text)
                .font(OnboardingStyle.Typography.subheadline)
                .foregroundStyle(SemanticTokens.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
