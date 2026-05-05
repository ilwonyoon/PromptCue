import SwiftUI

struct OnboardingStackView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        OnboardingStepChrome(progress: (current: 3, total: 4)) {
            VStack(spacing: PrimitiveTokens.Space.md) {
                OnboardingMentalModelCard(
                    headline: "Stack — today's queue",
                    summary: "Capture dumps things in. Stack is where you decide what to do with them — copy to paste, or hand the whole thing to your AI.",
                    bullets: [
                        "Auto-clears every 8 hours — it's not a notebook",
                        "For long-term context, that's Memory",
                        "Brand line: \"Stack for today. Memory for everything else.\""
                    ]
                )

                OnboardingShortcutBadge(
                    keys: ["⌘", "2"],
                    caption: "Toggle Stack from anywhere."
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, PrimitiveTokens.Space.xs)
            }
        } footer: {
            HStack(spacing: PrimitiveTokens.Space.sm) {
                Button("Skip") {
                    state.skipFromAnyStep()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Continue") {
                    state.advanceTo(.lane2FlowStory)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
