import SwiftUI

struct OnboardingPickMainAIView: View {
    @ObservedObject var state: OnboardingState

    private var inspection: MCPConnectorInspection? {
        state.connector?.inspection
    }

    private func detected(_ client: MCPConnectorClient) -> Bool {
        inspection?.status(for: client).isClientAvailable ?? false
    }

    private var defaultClient: MCPConnectorClient {
        for candidate in [MCPConnectorClient.claudeDesktop, .claudeCode, .codex] {
            if detected(candidate) {
                return candidate
            }
        }
        return .claudeDesktop
    }

    var body: some View {
        OnboardingStepChrome(progress: (current: 1, total: 2)) {
            OnboardingListLayout {
                Text("Which AI do you use most?")
                    .font(OnboardingStyle.Typography.title)
                    .foregroundStyle(SemanticTokens.Text.primary)
            } listContent: {
                ClientTile(
                    client: .claudeDesktop,
                    title: "Claude Desktop",
                    descriptor: detected(.claudeDesktop) ? "Detected" : "Not installed",
                    isAvailable: detected(.claudeDesktop),
                    isRecommended: defaultClient == .claudeDesktop,
                    action: { state.selectClient(.claudeDesktop) }
                )
                ClientTile(
                    client: .claudeCode,
                    title: "Claude Code",
                    descriptor: detected(.claudeCode) ? "Detected" : "Not installed",
                    isAvailable: detected(.claudeCode),
                    isRecommended: defaultClient == .claudeCode,
                    action: { state.selectClient(.claudeCode) }
                )
                ClientTile(
                    client: .codex,
                    title: "Codex CLI",
                    descriptor: detected(.codex) ? "Detected" : "Not installed",
                    isAvailable: detected(.codex),
                    isRecommended: defaultClient == .codex,
                    action: { state.selectClient(.codex) }
                )
                ClientTile(
                    client: nil,
                    kind: .chatGPT,
                    title: "ChatGPT",
                    descriptor: "Advanced setup",
                    isAvailable: true,
                    isRecommended: false,
                    action: { state.advanceTo(.lane1ConnectChatGPT) }
                )
            }
        } footer: {
            HStack {
                Spacer()
                Button("Skip") {
                    state.skipFromAnyStep()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .font(OnboardingStyle.Typography.subheadline)
                Spacer()
            }
        }
    }
}

private struct ClientTile: View {
    let client: MCPConnectorClient?
    let kind: OnboardingClientKind?
    let title: String
    let descriptor: String
    let isAvailable: Bool
    let isRecommended: Bool
    let action: () -> Void

    init(
        client: MCPConnectorClient?,
        kind: OnboardingClientKind? = nil,
        title: String,
        descriptor: String,
        isAvailable: Bool,
        isRecommended: Bool,
        action: @escaping () -> Void
    ) {
        self.client = client
        self.kind = kind ?? OnboardingClientKind(client)
        self.title = title
        self.descriptor = descriptor
        self.isAvailable = isAvailable
        self.isRecommended = isRecommended
        self.action = action
    }

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                OnboardingClientIcon(kind: kind, size: 36)
                    .opacity(isAvailable ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(OnboardingStyle.Typography.headline)
                            .foregroundStyle(isAvailable
                                             ? SemanticTokens.Text.primary
                                             : SemanticTokens.Text.secondary)
                        if isRecommended {
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
                    Text(descriptor)
                        .font(OnboardingStyle.Typography.subheadline)
                        .foregroundStyle(SemanticTokens.Text.secondary)
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
