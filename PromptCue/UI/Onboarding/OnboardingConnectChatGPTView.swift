import SwiftUI

struct OnboardingConnectChatGPTView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        OnboardingStepChrome(progress: (current: 2, total: 2)) {
            OnboardingHeroLayout {
                OnboardingClientIcon(kind: .chatGPT, size: PrimitiveTokens.Alert.iconSize)
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            } heading: {
                Text("ChatGPT needs advanced setup")
                    .font(OnboardingStyle.Typography.title)
                    .foregroundStyle(SemanticTokens.Text.primary)

                Text("ChatGPT only connects over a public HTTPS tunnel (ngrok or Cloudflare). Set it up in Settings → Connectors when you're ready.")
                    .font(OnboardingStyle.Typography.subheadline)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 380)
            }
        } footer: {
            HStack(spacing: PrimitiveTokens.Space.sm) {
                Button("Skip") {
                    state.skipFromAnyStep()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .font(OnboardingStyle.Typography.body)

                Spacer()

                Button("Pick another AI") {
                    state.advanceTo(.lane1PickMainAI)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(OnboardingStyle.Accent.primary)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct BulletRow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundStyle(SemanticTokens.Text.secondary)
            Text(text)
                .font(OnboardingStyle.Typography.footnote)
                .foregroundStyle(SemanticTokens.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
