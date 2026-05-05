import SwiftUI

struct OnboardingConnectCodeView: View {
    @ObservedObject var state: OnboardingState
    @State private var didLaunchTerminal = false

    private var client: MCPConnectorClient {
        state.selectedClient ?? .claudeCode
    }

    private var clientTitle: String {
        client.title
    }

    private var clientStatus: MCPConnectorClientStatus? {
        state.connector?.inspection.status(for: client)
    }

    private var readiness: MCPConnectorReadinessState? {
        guard let connector = state.connector,
              let status = clientStatus else { return nil }
        return connector.readinessState(for: status)
    }

    private var statusLine: String {
        guard let readiness else { return "Detecting…" }
        switch readiness {
        case .unavailable: return "MCP server isn't running."
        case .installRequired: return "\(clientTitle) not installed."
        case .needsSetup:
            return didLaunchTerminal ? "Finish the command in Terminal." : "Not registered yet."
        case .configured: return "Registered. Open \(clientTitle) to verify."
        case .checking: return "Verifying…"
        case .connected: return "Connected."
        case .needsRefresh: return "Reconnect needed."
        case .needsAttention: return "Connection failed."
        }
    }

    private var isConnected: Bool {
        readiness == .connected
    }

    var body: some View {
        OnboardingStepChrome(progress: (current: 2, total: 2)) {
            OnboardingHeroLayout {
                OnboardingClientIcon(client: client, size: PrimitiveTokens.Alert.iconSize)
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            } heading: {
                Text("Connect \(clientTitle)")
                    .font(OnboardingStyle.Typography.title)
                    .foregroundStyle(SemanticTokens.Text.primary)

                HStack(spacing: 6) {
                    StatusDot(readiness: readiness)
                    Text(statusLine)
                        .font(OnboardingStyle.Typography.subheadline)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                }
            }
        } footer: {
            HStack(spacing: PrimitiveTokens.Space.sm) {
                Button("Back") {
                    state.advanceTo(.lane1PickMainAI)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .font(OnboardingStyle.Typography.body)

                Spacer()

                primaryButton
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isConnected {
            Button("Continue") {
                state.advanceTo(.lane1FirstDoc)
            }
            .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(OnboardingStyle.Accent.primary)
            .keyboardShortcut(.defaultAction)
        } else if didLaunchTerminal {
            Button("I've connected — continue") {
                state.advanceTo(.lane1FirstDoc)
            }
            .buttonStyle(.bordered)
                .controlSize(.large)
        } else {
            Button("Open Terminal & connect") {
                let didLaunch = state.connector?.launchAddCommandInTerminal(for: client) ?? false
                if didLaunch {
                    didLaunchTerminal = true
                }
            }
            .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(OnboardingStyle.Accent.primary)
            .keyboardShortcut(.defaultAction)
            .disabled(state.connector == nil || readiness == .installRequired)
        }
    }
}

private struct StatusDot: View {
    let readiness: MCPConnectorReadinessState?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch readiness {
        case .connected:
            return .green
        case .checking, .configured:
            return .orange
        case .needsAttention, .needsRefresh:
            return .red
        case .none, .needsSetup, .installRequired, .unavailable:
            return SemanticTokens.Text.secondary
        }
    }
}
