import SwiftUI

struct OnboardingCaptureView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        OnboardingStepChrome(progress: (current: 2, total: 4)) {
            VStack(spacing: PrimitiveTokens.Space.md) {
                OnboardingMentalModelCard(
                    headline: "Capture — friction-zero dump",
                    summary: "You're coding, you're in flow, and a prompt pops in your head. Hit ⌘+` and dump it. Don't break your flow.",
                    bullets: [
                        "\"Why does this hook re-render twice?\"",
                        "\"Refactor: extract the useState chain\"",
                        "(paste from terminal — error logs, snippets)"
                    ]
                )

                OnboardingShortcutBadge(
                    keys: ["⌘", "`"],
                    caption: "Press from anywhere — Cursor, VSCode, terminal, browser."
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

                Button("Continue to Stack") {
                    state.advanceTo(.lane2Stack)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
