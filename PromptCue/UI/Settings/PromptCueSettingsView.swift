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
    @ObservedObject private var mcpConnectorSettingsModel: MCPConnectorSettingsModel

    private let labelColumnWidth: CGFloat = PanelMetrics.settingsLabelColumnWidth

    init(
        selectedTab: SettingsTab,
        screenshotSettingsModel: ScreenshotSettingsModel,
        exportTailSettingsModel: PromptExportTailSettingsModel,
        retentionSettingsModel: CardRetentionSettingsModel,
        cloudSyncSettingsModel: CloudSyncSettingsModel,
        appearanceSettingsModel: AppearanceSettingsModel,
        mcpConnectorSettingsModel: MCPConnectorSettingsModel
    ) {
        self.selectedTab = selectedTab
        self.screenshotSettingsModel = screenshotSettingsModel
        self.exportTailSettingsModel = exportTailSettingsModel
        self.retentionSettingsModel = retentionSettingsModel
        self.cloudSyncSettingsModel = cloudSyncSettingsModel
        self.appearanceSettingsModel = appearanceSettingsModel
        self.mcpConnectorSettingsModel = mcpConnectorSettingsModel
    }

    init() {
        self.selectedTab = .general
        self.screenshotSettingsModel = ScreenshotSettingsModel()
        self.exportTailSettingsModel = PromptExportTailSettingsModel()
        self.retentionSettingsModel = CardRetentionSettingsModel()
        self.cloudSyncSettingsModel = CloudSyncSettingsModel()
        self.appearanceSettingsModel = AppearanceSettingsModel()
        self.mcpConnectorSettingsModel = MCPConnectorSettingsModel()
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
                case .connectors:
                    connectorsContent
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
            mcpConnectorSettingsModel.refresh()
        }
    }

    @ViewBuilder
    private var generalContent: some View {
        settingsSection(
            title: "Appearance",
            footer: "Choose whether Backtick follows the system theme or forces a specific mode."
        ) {
            settingsGrid {
                row("Theme") {
                    Picker(
                        "",
                        selection: binding(
                            get: { appearanceSettingsModel.mode },
                            set: { appearanceSettingsModel.updateMode($0) }
                        )
                    ) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }
        }

        sectionDivider

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
            title: "iCloud Sync",
            footer: "Sync cards across your Macs via iCloud. Screenshots stay local."
        ) {
            settingsGrid {
                row("Sync", verticalAlignment: .top) {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                        Toggle(
                            "Enable iCloud sync",
                            isOn: binding(
                                get: { cloudSyncSettingsModel.isSyncEnabled },
                                set: cloudSyncSettingsModel.updateSyncEnabled
                            )
                        )
                        .toggleStyle(.checkbox)

                        rowNote("Cards sync automatically between Macs signed into the same Apple ID.")
                    }
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
        }
    }

    @ViewBuilder
    private var captureContent: some View {
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

    @ViewBuilder
    private var stackContent: some View {
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
                        set: { exportTailSettingsModel.updateSuffixText($0) }
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

    @ViewBuilder
    private var connectorsContent: some View {
        settingsSection(
            title: "Backtick MCP",
            footer: "Connect Stack storage to external coding agents without guessing the command or config format."
        ) {
            settingsGrid {
                row("Server") {
                    Text(mcpConnectorSettingsModel.serverStatusTitle)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                row("Repository") {
                    Text(mcpConnectorSettingsModel.repositoryRootPath)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            detailPane(label: "Launch Command") {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                    Text(mcpConnectorSettingsModel.serverStatusDetail)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Copy Command") {
                        mcpConnectorSettingsModel.copyServerCommand()
                    }
                    .controlSize(.small)
                }
            }
        }

        sectionDivider

        ForEach(mcpConnectorSettingsModel.clients, id: \.client.id) { client in
            connectorSection(client)
            if client.client != mcpConnectorSettingsModel.clients.last?.client {
                sectionDivider
            }
        }
    }

    @ViewBuilder
    private func connectorSection(_ client: MCPConnectorClientStatus) -> some View {
        settingsSection(
            title: client.client.title,
            footer: connectorFooter(for: client.client)
        ) {
            settingsGrid {
                row("CLI") {
                    Text(client.cliStatusText)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(
                            client.cliPath == nil ? SemanticTokens.Text.secondary : SemanticTokens.Text.primary
                        )
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                row("Configured") {
                    Text(client.configurationSummary)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let projectConfig = client.projectConfig {
                detailPane(label: "Project Config") {
                    connectorConfigDetail(
                        client: client.client,
                        config: projectConfig,
                        revealAction: { mcpConnectorSettingsModel.revealProjectConfig(for: client.client) }
                    )
                }
            }

            detailPane(label: "Home Config") {
                connectorConfigDetail(
                    client: client.client,
                    config: client.homeConfig,
                    revealAction: { mcpConnectorSettingsModel.revealHomeConfig(for: client.client) }
                )
            }

            detailPane(label: "Quick Add") {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                    Text(client.addCommand ?? "Backtick MCP launch command is not available yet.")
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: PrimitiveTokens.Space.xs) {
                        Button("Copy Add Command") {
                            mcpConnectorSettingsModel.copyAddCommand(for: client.client)
                        }
                        .controlSize(.small)

                        Button("Copy Config Snippet") {
                            mcpConnectorSettingsModel.copyConfigSnippet(for: client.client)
                        }
                        .controlSize(.small)

                        Button("Open Docs") {
                            mcpConnectorSettingsModel.openDocumentation(for: client.client)
                        }
                        .controlSize(.small)
                    }
                }
            }

            detailPane(label: "Config Snippet") {
                Text(client.configSnippet ?? "Launch command unavailable.")
                    .font(PrimitiveTokens.Typography.body)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .textSelection(.enabled)
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

    @ViewBuilder
    private func connectorConfigDetail(
        client: MCPConnectorClient,
        config: MCPConnectorConfigLocationStatus,
        revealAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
            Text("\(config.presence.title) · \(config.path)")
                .font(PrimitiveTokens.Typography.body)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: PrimitiveTokens.Space.xs) {
                Button("Reveal") {
                    revealAction()
                }
                .controlSize(.small)

                if config.presence != .configured {
                    Button("Copy Config Snippet") {
                        mcpConnectorSettingsModel.copyConfigSnippet(for: client)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func connectorFooter(for client: MCPConnectorClient) -> String {
        switch client {
        case .claudeCode:
            return "Claude Code supports project `.mcp.json` files and home-level `~/.claude.json` entries."
        case .codex:
            return "Codex reads MCP servers from `.codex/config.toml`, either in the repo or your home directory."
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
        Grid(
            alignment: .leading,
            horizontalSpacing: PrimitiveTokens.Space.md,
            verticalSpacing: PrimitiveTokens.Space.xs
        ) {
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
