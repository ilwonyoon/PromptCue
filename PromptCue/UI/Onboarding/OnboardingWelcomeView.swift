import SwiftUI

struct OnboardingWelcomeView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        OnboardingStepChrome(progress: nil) {
            OnboardingHeroLayout {
                heroIcon
            } heading: {
                Text("Backtick")
                    .font(OnboardingStyle.Typography.largeTitle)
                    .foregroundStyle(SemanticTokens.Text.primary)

                Text("Memory your AI tools share.")
                    .font(OnboardingStyle.Typography.body)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .multilineTextAlignment(.center)
            }
        } footer: {
            HStack(spacing: PrimitiveTokens.Space.sm) {
                Spacer()

                Button("Skip") {
                    state.skipFromAnyStep()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .font(OnboardingStyle.Typography.body)

                Button("Continue") {
                    state.goToLanePicker()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(OnboardingStyle.Accent.primary)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var heroIcon: some View {
        Group {
            if let nsImage = NSImage(named: "BacktickAppIcon") {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(OnboardingStyle.Accent.primary)
                    .padding(PrimitiveTokens.Space.lg)
                    .background(
                        RoundedRectangle(cornerRadius: OnboardingStyle.Radius.icon, style: .continuous)
                            .fill(OnboardingStyle.Surface.card)
                    )
            }
        }
        .frame(width: PrimitiveTokens.Alert.iconSize, height: PrimitiveTokens.Alert.iconSize)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}
