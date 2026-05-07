import SwiftUI

struct OnboardingLanePickerView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        OnboardingStepChrome(progress: nil) {
            OnboardingListLayout {
                Text("Where do you want to start?")
                    .font(OnboardingStyle.Typography.title)
                    .foregroundStyle(SemanticTokens.Text.primary)
            } listContent: {
                LaneCard(
                    title: "Connect AI memory",
                    summary: "Your AI tools share one memory you control.",
                    symbol: "network",
                    isFeatured: true,
                    action: { state.selectLane(.lane1SharedMemory) }
                )

                LaneCard(
                    title: "Capture & Stack",
                    summary: "Dump prompts with ⌘+` while coding.",
                    symbol: "square.stack",
                    isFeatured: false,
                    action: { state.selectLane(.lane2CaptureStack) }
                )
            }
        } footer: {
            HStack {
                Spacer()
                Button("Skip") {
                    state.selectLane(.skipped)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .font(OnboardingStyle.Typography.subheadline)
                Spacer()
            }
        }
    }
}

private struct LaneCard: View {
    let title: String
    let summary: String
    let symbol: String
    let isFeatured: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(OnboardingStyle.Accent.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(OnboardingStyle.Accent.primary.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(OnboardingStyle.Typography.headline)
                            .foregroundStyle(SemanticTokens.Text.primary)
                        if isFeatured {
                            Text("Recommended")
                                .font(OnboardingStyle.Typography.caption.weight(.semibold))
                                .foregroundStyle(OnboardingStyle.Accent.primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(OnboardingStyle.Accent.primary.opacity(0.12))
                                )
                        }
                    }
                    Text(summary)
                        .font(OnboardingStyle.Typography.subheadline)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(OnboardingStyle.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(SemanticTokens.Text.secondary.opacity(0.6))
            }
            .onboardingCard(isHovering: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
