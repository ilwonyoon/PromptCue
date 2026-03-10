import KeyboardShortcuts
import SwiftUI

@MainActor
struct PromptCueSettingsView: View {
    let selectedTab: SettingsTab
    @ObservedObject private var screenshotSettingsModel: ScreenshotSettingsModel
    @ObservedObject private var exportTailSettingsModel: PromptExportTailSettingsModel
    @ObservedObject private var retentionSettingsModel: CardRetentionSettingsModel
    @ObservedObject private var cloudSyncSettingsModel: CloudSyncSettingsModel
    @ObservedObject private var appearanceSettingsModel: AppearanceSettingsModel

    private let labelColumnWidth: CGFloat = PanelMetrics.settingsLabelColumnWidth

    init(
        selectedTab: SettingsTab,
        screenshotSettingsModel: ScreenshotSettingsModel,
        exportTailSettingsModel: PromptExportTailSettingsModel,
        retentionSettingsModel: CardRetentionSettingsModel,
        cloudSyncSettingsModel: CloudSyncSettingsModel,
        appearanceSettingsModel: AppearanceSettingsModel
    ) {
        self.selectedTab = selectedTab
        self.screenshotSettingsModel = screenshotSettingsModel
        self.exportTailSettingsModel = exportTailSettingsModel
        self.retentionSettingsModel = retentionSettingsModel
        self.cloudSyncSettingsModel = cloudSyncSettingsModel
        self.appearanceSettingsModel = appearanceSettingsModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xl) {
                switch selectedTab {
                case .general:
                    generalContent
                case .capture:
                    captureContent
                case .stack:
                    stackContent
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
            cloudSyncSettingsModel.refresh()
            appearanceSettingsModel.refresh()
        }
    }

    // MARK: - General Tab

    @ViewBuilder
    private var generalContent: some View {
        settingsSection(title: "Appearance") {
            settingsGrid {
                row("Theme") {
                    Picker("", selection: binding(
                        get: { appearanceSettingsModel.mode },
                        set: { appearanceSettingsModel.updateMode($0) }
                    )) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
            }
        }

        sectionDivider

        settingsSection(title: "Shortcuts") {
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

        settingsSection(title: "iCloud Sync") {
            settingsGrid {
                row("Sync") {
                    Toggle(
                        "Enable iCloud sync",
                        isOn: binding(
                            get: { cloudSyncSettingsModel.isSyncEnabled },
                            set: cloudSyncSettingsModel.updateSyncEnabled
                        )
                    )
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                row("Status") {
                    Text(cloudSyncSettingsModel.syncStatusText)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(
                            cloudSyncSettingsModel.syncError != nil
                                ? SemanticTokens.Text.secondary
                                : SemanticTokens.Text.primary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            rowNote("Screenshots stay local.")
        }
    }

    // MARK: - Capture Tab

    @ViewBuilder
    private var captureContent: some View {
        settingsSection(title: "Screenshots") {
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

    // MARK: - Stack Tab

    @ViewBuilder
    private var stackContent: some View {
        settingsSection(title: "Retention") {
            settingsGrid {
                row("Card Lifetime") {
                    Toggle(
                        "Auto-expire after 8 hours",
                        isOn: binding(
                            get: { retentionSettingsModel.isAutoExpireEnabled },
                            set: retentionSettingsModel.updateAutoExpireEnabled
                        )
                    )
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        sectionDivider

        settingsSection(title: "AI Export Tail") {
            settingsGrid {
                row("Behavior") {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                        Toggle(
                            "Append AI export tail",
                            isOn: binding(
                                get: { exportTailSettingsModel.isEnabled },
                                set: exportTailSettingsModel.updateEnabled
                            )
                        )
                        .toggleStyle(.checkbox)

                        rowNote("Added to clipboard output only.")
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
    }

    // MARK: - Screenshot Helpers

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
            return "Choose your screenshot folder."
        case let .connected(_, displayPath):
            return displayPath
        case .needsReconnect:
            return "Access expired. Reconnect to continue."
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

    // MARK: - Layout Helpers

    private var sectionDivider: some View {
        Divider()
            .overlay(SemanticTokens.Border.subtle)
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
            Text(title)
                .font(PrimitiveTokens.Typography.bodyStrong)
                .foregroundStyle(SemanticTokens.Text.primary)

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
