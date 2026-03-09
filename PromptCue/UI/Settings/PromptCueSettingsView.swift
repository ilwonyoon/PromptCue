import KeyboardShortcuts
import SwiftUI

@MainActor
struct PromptCueSettingsView: View {
    @ObservedObject private var screenshotSettingsModel: ScreenshotSettingsModel
    @ObservedObject private var exportTailSettingsModel: PromptExportTailSettingsModel
    @ObservedObject private var retentionSettingsModel: CardRetentionSettingsModel

    private let labelColumnWidth: CGFloat = 138

    init(
        screenshotSettingsModel: ScreenshotSettingsModel,
        exportTailSettingsModel: PromptExportTailSettingsModel,
        retentionSettingsModel: CardRetentionSettingsModel
    ) {
        self.screenshotSettingsModel = screenshotSettingsModel
        self.exportTailSettingsModel = exportTailSettingsModel
        self.retentionSettingsModel = retentionSettingsModel
    }

    init() {
        self.screenshotSettingsModel = ScreenshotSettingsModel()
        self.exportTailSettingsModel = PromptExportTailSettingsModel()
        self.retentionSettingsModel = CardRetentionSettingsModel()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xl) {
                settingsSection(
                    title: "Shortcuts",
                    footer: "These shortcuts work globally."
                ) {
                    settingsGrid {
                        row("Quick Capture") {
                            KeyboardShortcuts.Recorder(for: .quickCapture)
                        }

                        row("Show Stack") {
                            KeyboardShortcuts.Recorder(for: .toggleStackPanel)
                        }
                    }
                }

                sectionDivider

                settingsSection(
                    title: "Retention",
                    footer: "Cards stay until you delete them unless auto-expire is enabled."
                ) {
                    settingsGrid {
                        row("Card Lifetime", verticalAlignment: .top) {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                                Toggle(
                                    "Auto-expire stack cards after 8 hours",
                                    isOn: binding(
                                        get: { retentionSettingsModel.isAutoExpireEnabled },
                                        set: retentionSettingsModel.updateAutoExpireEnabled
                                    )
                                )
                                .toggleStyle(.checkbox)

                                rowNote("Off by default. Turn this on to restore the original 8-hour cleanup behavior.")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                sectionDivider

                settingsSection(
                    title: "AI Export Tail",
                    footer: "Saved cards stay unchanged. The tail is added only when you copy or export."
                ) {
                    settingsGrid {
                        row("Behavior", verticalAlignment: .top) {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                                Toggle(
                                    "Append AI export tail",
                                    isOn: binding(
                                        get: { exportTailSettingsModel.isEnabled },
                                        set: exportTailSettingsModel.updateEnabled
                                    )
                                )
                                .toggleStyle(.checkbox)

                                rowNote("Append your reusable instruction block to copied text without modifying saved cards.")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    detailPane(label: "Tail Text") {
                        TextEditor(
                            text: binding(
                                get: { exportTailSettingsModel.suffixText },
                                set: exportTailSettingsModel.updateSuffixText
                            )
                        )
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.primary)
                        .scrollContentBackground(.hidden)
                        .frame(
                            minHeight: PanelMetrics.settingsExportTailEditorMinHeight,
                            maxHeight: PanelMetrics.settingsExportTailEditorMaxHeight
                        )
                        .padding(PrimitiveTokens.Space.sm)
                        .background(SemanticTokens.Surface.raisedFill)
                        .clipShape(RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                                .stroke(SemanticTokens.Border.subtle, lineWidth: PrimitiveTokens.Stroke.subtle)
                        }
                    }

                    detailPane(label: "Preview") {
                        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                            HStack {
                                Spacer()

                                Button("Reset to Default") {
                                    exportTailSettingsModel.resetToDefault()
                                }
                                .controlSize(.small)
                            }

                            Text(exportTailSettingsModel.previewText)
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(SemanticTokens.Text.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(PrimitiveTokens.Space.sm)
                                .background(SemanticTokens.Surface.cardFill)
                                .clipShape(RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                                        .stroke(SemanticTokens.Border.subtle, lineWidth: PrimitiveTokens.Stroke.subtle)
                                }
                        }
                    }
                }

                sectionDivider

                settingsSection(
                    title: "Screenshots",
                    footer: "Auto-attach only checks the screenshot folder you explicitly approve."
                ) {
                    settingsGrid {
                        row("Status") {
                            Text(screenshotStatusTitle)
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(SemanticTokens.Text.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    detailPane(label: "Folder") {
                        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                            Text(screenshotStatusDetail)
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(SemanticTokens.Text.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: PrimitiveTokens.Space.xs) {
                                primaryScreenshotButton

                                if case .connected = screenshotSettingsModel.accessState {
                                    Button("Reveal in Finder") {
                                        screenshotSettingsModel.revealFolderInFinder()
                                    }

                                    Button("Disconnect") {
                                        screenshotSettingsModel.clearFolder()
                                    }
                                }

                                if case .needsReconnect = screenshotSettingsModel.accessState {
                                    Button("Clear") {
                                        screenshotSettingsModel.clearFolder()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(PrimitiveTokens.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            width: PanelMetrics.settingsPanelWidth,
            height: PanelMetrics.settingsPanelHeight
        )
        .background(SemanticTokens.Surface.previewBackdropBottom)
        .onAppear {
            screenshotSettingsModel.refresh()
            exportTailSettingsModel.refresh()
            retentionSettingsModel.refresh()
        }
    }

    private var screenshotStatusTitle: String {
        switch screenshotSettingsModel.accessState {
        case .notConfigured:
            return "Not connected"
        case .connected:
            return "Connected"
        case .needsReconnect:
            return "Needs reconnect"
        }
    }

    private var screenshotStatusDetail: String {
        switch screenshotSettingsModel.accessState {
        case .notConfigured:
            if let suggestedSystemPath = screenshotSettingsModel.suggestedSystemPath {
                return "System screenshots often save to \(suggestedSystemPath). Choose that folder to enable auto-attach."
            }

            return "Choose the folder Backtick should watch for recent screenshots."
        case let .connected(_, displayPath):
            return displayPath
        case let .needsReconnect(lastKnownDisplayPath):
            return "Backtick remembers \(lastKnownDisplayPath), but access needs to be approved again."
        }
    }

    @ViewBuilder
    private var primaryScreenshotButton: some View {
        switch screenshotSettingsModel.accessState {
        case .notConfigured:
            Button("Choose Folder…") {
                screenshotSettingsModel.chooseFolder()
            }
        case .connected:
            Button("Change…") {
                screenshotSettingsModel.chooseFolder()
            }
        case .needsReconnect:
            Button("Reconnect…") {
                screenshotSettingsModel.reconnectFolder()
            }
        }
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(SemanticTokens.Border.subtle)
    }

    private func settingsSection<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                Text(title)
                    .font(PrimitiveTokens.Typography.bodyStrong)
                    .foregroundStyle(SemanticTokens.Text.primary)

                if let footer, footer.isEmpty == false {
                    Text(footer)
                        .font(PrimitiveTokens.Typography.meta)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                }
            }

            content()
        }
    }

    private func settingsGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: PrimitiveTokens.Space.md,
            verticalSpacing: PrimitiveTokens.Space.md
        ) {
            content()
        }
    }

    private func row<Content: View>(
        _ label: String,
        verticalAlignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow(alignment: verticalAlignment) {
            Text(label)
                .font(PrimitiveTokens.Typography.body)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .frame(width: labelColumnWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailPane<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: PrimitiveTokens.Space.md, verticalSpacing: PrimitiveTokens.Space.xs) {
            GridRow(alignment: .top) {
                Text(label)
                    .font(PrimitiveTokens.Typography.body)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .frame(width: labelColumnWidth, alignment: .leading)

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func rowNote(_ text: String) -> some View {
        Text(text)
            .font(PrimitiveTokens.Typography.meta)
            .foregroundStyle(SemanticTokens.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func binding<Value>(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: get, set: set)
    }
}
