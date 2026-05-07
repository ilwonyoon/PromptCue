import SwiftUI

struct OnboardingFirstDocView: View {
    @ObservedObject var state: OnboardingState
    @StateObject private var watcher = OnboardingSaveActivityWatcher()
    @State private var didCopyPrompt = false

    private var clientTitle: String {
        state.selectedClient?.title ?? "your AI"
    }

    private var samplePrompt: String {
        "Save this to my Backtick memory: I prefer concise replies and want code in TypeScript by default."
    }

    private var detectedSave: OnboardingSaveActivityWatcher.DetectedSave? {
        watcher.detectedSave
    }

    var body: some View {
        OnboardingStepChrome(progress: nil) {
            OnboardingListLayout {
                HStack(spacing: PrimitiveTokens.Space.xs + 2) {
                    OnboardingClientIcon(client: state.selectedClient, size: 36)
                    Text(detectedSave == nil ? "Try it in \(clientTitle)" : "Saved.")
                        .font(OnboardingStyle.Typography.title)
                        .foregroundStyle(SemanticTokens.Text.primary)
                }
            } listContent: {
                if detectedSave == nil {
                    instructionCard
                } else {
                    successCard
                }
            }
        } footer: {
            footerButtons
        }
        .onAppear { watcher.start() }
        .onDisappear { watcher.stop() }
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(samplePrompt)
                .font(PrimitiveTokens.Typography.code)
                .foregroundStyle(SemanticTokens.Text.primary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .padding(.trailing, 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(OnboardingStyle.Surface.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SemanticTokens.Border.subtle, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    copyButton
                        .padding(8)
                }

            if didCopyPrompt && detectedSave == nil {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Watching for \(clientTitle)…")
                        .font(OnboardingStyle.Typography.subheadline)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                }
            }
        }
    }

    private var copyButton: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(samplePrompt, forType: .string)
            didCopyPrompt = true
        } label: {
            Image(systemName: didCopyPrompt ? "checkmark" : "doc.on.doc")
                .font(.body.weight(.medium))
                .foregroundStyle(didCopyPrompt
                                 ? OnboardingStyle.Accent.primary
                                 : SemanticTokens.Text.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(OnboardingStyle.Surface.groupedBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SemanticTokens.Border.subtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(didCopyPrompt ? "Copied" : "Copy prompt")
    }

    private var successCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title.weight(.medium))
                .foregroundStyle(.green)
            Text("Backtick now has memory \(clientTitle) can read.")
                .font(OnboardingStyle.Typography.body)
                .foregroundStyle(SemanticTokens.Text.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: OnboardingStyle.Radius.card, style: .continuous)
                .fill(OnboardingStyle.Surface.card)
        )
    }

    @ViewBuilder
    private var footerButtons: some View {
        HStack(spacing: PrimitiveTokens.Space.sm) {
            Button("Skip") {
                state.skipFromAnyStep()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(SemanticTokens.Text.secondary)
            .font(OnboardingStyle.Typography.body)

            Spacer()

            Button(detectedSave != nil ? "Done" : "I tried it — done") {
                state.finish()
            }
            .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(OnboardingStyle.Accent.primary)
            .keyboardShortcut(.defaultAction)
        }
    }
}

