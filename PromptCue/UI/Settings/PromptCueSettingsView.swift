import KeyboardShortcuts
import SwiftUI

struct PromptCueSettingsView: View {
    var body: some View {
        Form {
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Quick Capture", name: .quickCapture)
                KeyboardShortcuts.Recorder("Show Stack Panel", name: .toggleStackPanel)
            }

            Section("Screenshots") {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                    Text("Detected screenshot folder")
                        .font(PrimitiveTokens.Typography.meta)
                        .foregroundStyle(SemanticTokens.Text.secondary)

                    Text(ScreenshotDirectoryResolver.preferredDirectoryDisplayPath)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.primary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, PrimitiveTokens.Space.xxxs)
            }
        }
        .formStyle(.grouped)
        .padding(PrimitiveTokens.Space.xl)
        .frame(width: AppUIConstants.settingsPanelWidth)
    }
}
