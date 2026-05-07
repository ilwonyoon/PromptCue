import SwiftUI

struct OnboardingConnectDesktopView: View {
    @ObservedObject var state: OnboardingState
    @State private var showAdvanced = false
    @State private var didLaunchTerminal = false
    @State private var didApplyConfig = false
    @State private var backupPath: String?
    @State private var applyError: String?

    private var status: MCPConnectorClientStatus? {
        state.connector?.inspection.status(for: .claudeDesktop)
    }

    private var readiness: MCPConnectorReadinessState? {
        guard let connector = state.connector,
              let status else { return nil }
        return connector.readinessState(for: status)
    }

    private var isConnected: Bool {
        readiness == .connected
    }

    private var hasLaunchSpec: Bool {
        state.connector?.inspection.launchSpec != nil
    }

    var body: some View {
        OnboardingStepChrome(progress: (current: 2, total: 2)) {
            OnboardingHeroLayout {
                OnboardingClientIcon(client: .claudeDesktop, size: PrimitiveTokens.Alert.iconSize)
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            } heading: {
                Text("Connect Claude Desktop")
                    .font(OnboardingStyle.Typography.title)
                    .foregroundStyle(SemanticTokens.Text.primary)

                Text(statusLine)
                    .font(OnboardingStyle.Typography.subheadline)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            } bodyContent: {
                VStack(spacing: PrimitiveTokens.Space.xs) {
                    advancedDisclosure
                    if let applyError {
                        Text(applyError)
                            .font(OnboardingStyle.Typography.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
        } footer: {
            footerButtons
        }
    }

    private var statusLine: String {
        if isConnected { return "Connected." }
        if didLaunchTerminal { return "Finish in Terminal, then quit & reopen Claude (⌘Q)." }
        if didApplyConfig { return "Config applied. Quit & reopen Claude (⌘Q)." }
        return "Backtick will add itself to Claude's config — pick how to run it."
    }

    @ViewBuilder
    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            advancedSection
                .padding(.top, 8)
        } label: {
            Text("Apply silently (no Terminal)")
                .font(OnboardingStyle.Typography.subheadline)
                .foregroundStyle(SemanticTokens.Text.secondary)
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Button(didApplyConfig ? "Applied ✓" : "Apply silently") {
                    applyConfigDirectly()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!hasLaunchSpec || didApplyConfig)
            }

            if didApplyConfig, let backupPath {
                Text("Backup: \(backupPath)")
                    .font(PrimitiveTokens.Typography.code)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
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

    @ViewBuilder
    private var primaryButton: some View {
        if didLaunchTerminal || didApplyConfig {
            Button(isConnected ? "Continue" : "I've restarted Claude — continue") {
                state.advanceTo(.lane1FirstDoc)
            }
            .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(OnboardingStyle.Accent.primary)
            .keyboardShortcut(.defaultAction)
        } else {
            Button("Open Terminal & install") {
                runTerminalInstall()
            }
            .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(OnboardingStyle.Accent.primary)
            .keyboardShortcut(.defaultAction)
            .disabled(!hasLaunchSpec)
        }
    }

    private func runTerminalInstall() {
        applyError = nil
        guard let launchSpec = state.connector?.inspection.launchSpec else {
            applyError = "Backtick MCP helper not yet bundled."
            return
        }

        let command = OnboardingClaudeDesktopHelper.makeTerminalInstallCommand(launchSpec: launchSpec)
        let launcher = MCPConnectorTerminalLauncher()
        let didLaunch = launcher.launchInTerminal(command: command)
        if didLaunch {
            didLaunchTerminal = true
        } else {
            applyError = "Couldn't open Terminal. Try the silent option below."
        }
    }

    private func applyConfigDirectly() {
        applyError = nil
        do {
            if let backup = try OnboardingClaudeDesktopHelper.writeBackup() {
                backupPath = backup.path
            }
        } catch {
            applyError = "Couldn't write backup: \(error.localizedDescription)"
            return
        }
        state.connector?.writeDirectConfig(for: .claudeDesktop)
        didApplyConfig = true
    }
}

