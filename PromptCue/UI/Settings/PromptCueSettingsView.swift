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
    private let advancedLabelColumnWidth: CGFloat = 92

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
        settingsSection(title: "Backtick MCP") {
            connectorCard {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
                    HStack(spacing: PrimitiveTokens.Space.xs) {
                        connectorChip(
                            mcpConnectorSettingsModel.serverStatusTitle,
                            tone: mcpConnectorSettingsModel.isServerAvailable ? .accent : .warning
                        )

                        if mcpConnectorSettingsModel.isServerAvailable {
                            connectorChip(
                                mcpConnectorSettingsModel.serverSourceLabel,
                                tone: .neutral
                            )

                            connectorChip(
                                mcpConnectorSettingsModel.serverVerificationTitle,
                                tone: serverVerificationTone
                            )
                        }
                    }

                    Text(mcpConnectorSettingsModel.serverSummary)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if mcpConnectorSettingsModel.isServerAvailable {
                        Text(mcpConnectorSettingsModel.serverStatusFootnote)
                            .font(PrimitiveTokens.Typography.meta)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: PrimitiveTokens.Space.xs) {
                        if mcpConnectorSettingsModel.isServerAvailable {
                            Button(
                                mcpConnectorSettingsModel.connectionState.isRunning
                                    ? "Testing…"
                                    : "Run Test"
                            ) {
                                mcpConnectorSettingsModel.runServerTest()
                            }
                            .controlSize(.small)
                            .disabled(mcpConnectorSettingsModel.connectionState.isRunning)

                            Button("Copy Launch Command") {
                                mcpConnectorSettingsModel.copyServerCommand()
                            }
                            .controlSize(.small)
                        }
                    }

                    if serverTroubleshootingVisible {
                        DisclosureGroup("Troubleshooting") {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                                advancedDetailPane(label: "Launch Command") {
                                    advancedValueBlock(mcpConnectorSettingsModel.serverStatusDetail)
                                }

                                advancedDetailPane(label: "Latest Test") {
                                    advancedMessageBlock(mcpConnectorSettingsModel.serverTestDetail)
                                }
                            }
                            .padding(.top, PrimitiveTokens.Space.xs)
                        }
                        .font(PrimitiveTokens.Typography.meta)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                    }
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
        settingsSection(title: client.client.title) {
            connectorCard {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
                    HStack(spacing: PrimitiveTokens.Space.xs) {
                        connectorChip(
                            mcpConnectorSettingsModel.clientSetupTitle(for: client),
                            tone: clientSetupTone(for: client)
                        )

                        if let scopeTitle = mcpConnectorSettingsModel.clientScopeTitle(for: client) {
                            connectorChip(scopeTitle, tone: .neutral)
                        }

                        if let verificationTitle = mcpConnectorSettingsModel.clientVerificationTitle(for: client) {
                            connectorChip(
                                verificationTitle,
                                tone: clientVerificationTone(for: client)
                            )
                        }
                    }

                    Text(mcpConnectorSettingsModel.clientSummary(for: client))
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: PrimitiveTokens.Space.xs) {
                        if let primaryAction = mcpConnectorSettingsModel.primaryAction(for: client) {
                            Button(primaryAction.title) {
                                mcpConnectorSettingsModel.performPrimaryAction(primaryAction, for: client)
                            }
                            .controlSize(.small)
                            .disabled(
                                primaryAction == .runServerTest
                                    && mcpConnectorSettingsModel.connectionState.isRunning
                            )
                        }

                        if client.hasDetectedCLI {
                            Button("Open Config") {
                                mcpConnectorSettingsModel.revealPreferredConfig(for: client.client)
                            }
                            .controlSize(.small)
                        } else {
                            Button("Open Docs") {
                                mcpConnectorSettingsModel.openDocumentation(for: client.client)
                            }
                            .controlSize(.small)
                        }

                        if mcpConnectorSettingsModel.connectionState.isRunning,
                           mcpConnectorSettingsModel.primaryAction(for: client) == .runServerTest {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if manualSetupVisible(for: client) {
                        DisclosureGroup("Manual Setup") {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                                if let projectConfig = client.projectConfig {
                                    advancedDetailPane(label: "Project Config") {
                                        connectorConfigDetail(
                                            config: projectConfig,
                                            revealAction: { mcpConnectorSettingsModel.revealProjectConfig(for: client.client) }
                                        )
                                    }
                                }

                                advancedDetailPane(label: "Home Config") {
                                    connectorConfigDetail(
                                        config: client.homeConfig,
                                        revealAction: { mcpConnectorSettingsModel.revealHomeConfig(for: client.client) }
                                    )
                                }

                                if let addCommand = client.addCommand {
                                    advancedDetailPane(label: "Add Command") {
                                        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                            advancedValueBlock(addCommand)

                                            HStack(spacing: PrimitiveTokens.Space.xs) {
                                                Button("Copy Add Command") {
                                                    mcpConnectorSettingsModel.copyAddCommand(for: client.client)
                                                }
                                                .controlSize(.small)

                                                Button("Open Docs") {
                                                    mcpConnectorSettingsModel.openDocumentation(for: client.client)
                                                }
                                                .controlSize(.small)
                                            }
                                        }
                                    }
                                }

                                if let configSnippet = client.configSnippet {
                                    advancedDetailPane(label: "Config Snippet") {
                                        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                            advancedValueBlock(configSnippet)

                                            Button("Copy Config Snippet") {
                                                mcpConnectorSettingsModel.copyConfigSnippet(for: client.client)
                                            }
                                            .controlSize(.small)
                                        }
                                    }
                                }
                            }
                            .padding(.top, PrimitiveTokens.Space.xs)
                        }
                        .font(PrimitiveTokens.Typography.meta)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                    }

                    if troubleshootingVisible(for: client) {
                        DisclosureGroup("Troubleshooting") {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                                advancedDetailPane(label: "CLI") {
                                    advancedValueBlock(
                                        client.cliStatusText,
                                        emphasized: client.cliPath != nil
                                    )
                                }

                                if let failureDetail = mcpConnectorSettingsModel.clientFailureDetail(for: client) {
                                    advancedDetailPane(label: "Last Failure") {
                                        advancedMessageBlock(failureDetail)
                                    }
                                }

                                if client.hasOtherConfigFiles, !client.hasConfiguredScope {
                                    advancedDetailPane(label: "Config State") {
                                        advancedMessageBlock(
                                            "Another config already exists here, but Backtick has not been added yet."
                                        )
                                    }
                                }

                                HStack(spacing: PrimitiveTokens.Space.xs) {
                                    Button("Open Docs") {
                                        mcpConnectorSettingsModel.openDocumentation(for: client.client)
                                    }
                                    .controlSize(.small)

                                    if client.hasDetectedCLI {
                                        Button("Open Config") {
                                            mcpConnectorSettingsModel.revealPreferredConfig(for: client.client)
                                        }
                                        .controlSize(.small)
                                    }
                                }
                            }
                            .padding(.top, PrimitiveTokens.Space.xs)
                        }
                        .font(PrimitiveTokens.Typography.meta)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                    }

                    if automationVisible(for: client),
                       let automationExample = mcpConnectorSettingsModel.automationExample(for: client.client) {
                        DisclosureGroup("Automation") {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                                advancedMessageBlock(
                                    "Claude runs with `--permission-mode dontAsk` still need Backtick tools listed in `--allowedTools`."
                                )

                                advancedDetailPane(label: "Example") {
                                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                        advancedValueBlock(automationExample)

                                        Button("Copy Automation Example") {
                                            mcpConnectorSettingsModel.copyAutomationExample(for: client.client)
                                        }
                                        .controlSize(.small)
                                    }
                                }
                            }
                            .padding(.top, PrimitiveTokens.Space.xs)
                        }
                        .font(PrimitiveTokens.Typography.meta)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func connectorConfigDetail(
        config: MCPConnectorConfigLocationStatus,
        revealAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
            Text(config.presence.title)
                .font(PrimitiveTokens.Typography.metaStrong)
                .foregroundStyle(
                    config.presence == .configured
                        ? SemanticTokens.Text.primary
                        : SemanticTokens.Text.secondary
                )
                .frame(maxWidth: .infinity, alignment: .leading)

            advancedValueBlock(config.path)

            HStack(spacing: PrimitiveTokens.Space.xs) {
                Button("Reveal") {
                    revealAction()
                }
                .controlSize(.small)
            }
        }
    }

    private func connectorCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
            content()
        }
        .padding(PrimitiveTokens.Space.md)
        .background(SemanticTokens.Surface.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                .stroke(SemanticTokens.Border.subtle, lineWidth: PrimitiveTokens.Stroke.subtle)
        }
    }

    private func connectorChip(_ title: String, tone: ConnectorChipTone) -> some View {
        PromptCueChip(fill: tone.fill, border: tone.border) {
            Text(title)
                .font(PrimitiveTokens.Typography.metaStrong)
                .foregroundStyle(tone.foreground)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var serverVerificationTone: ConnectorChipTone {
        switch mcpConnectorSettingsModel.connectionState {
        case .idle:
            return .neutral
        case .running:
            return .accent
        case .passed:
            return .success
        case .failed:
            return .danger
        }
    }

    private func clientSetupTone(for client: MCPConnectorClientStatus) -> ConnectorChipTone {
        if !client.hasDetectedCLI {
            return .warning
        }

        if client.hasConfiguredScope {
            return .success
        }

        return .warning
    }

    private func clientVerificationTone(for client: MCPConnectorClientStatus) -> ConnectorChipTone {
        guard client.hasConfiguredScope else {
            return .neutral
        }

        switch mcpConnectorSettingsModel.connectionState {
        case .idle:
            return .neutral
        case .running:
            return .accent
        case .passed:
            return .success
        case .failed:
            return .danger
        }
    }

    private var serverTroubleshootingVisible: Bool {
        if !mcpConnectorSettingsModel.isServerAvailable {
            return true
        }

        if case .failed = mcpConnectorSettingsModel.connectionState {
            return true
        }

        return false
    }

    private func manualSetupVisible(for client: MCPConnectorClientStatus) -> Bool {
        guard client.hasDetectedCLI else {
            return false
        }

        return client.projectConfig != nil || client.addCommand != nil || client.configSnippet != nil
    }

    private func troubleshootingVisible(for client: MCPConnectorClientStatus) -> Bool {
        if !client.hasDetectedCLI {
            return true
        }

        if client.hasOtherConfigFiles, !client.hasConfiguredScope {
            return true
        }

        return mcpConnectorSettingsModel.clientFailureDetail(for: client) != nil
    }

    private func automationVisible(for client: MCPConnectorClientStatus) -> Bool {
        client.client == .claudeCode
            && client.hasConfiguredScope
            && mcpConnectorSettingsModel.automationExample(for: client.client) != nil
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

    private func advancedDetailPane<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: PrimitiveTokens.Space.sm,
            verticalSpacing: PrimitiveTokens.Space.xxs
        ) {
            GridRow(alignment: .top) {
                Text(label)
                    .font(PrimitiveTokens.Typography.meta)
                    .foregroundStyle(SemanticTokens.Text.secondary)
                    .frame(width: advancedLabelColumnWidth, alignment: .leading)

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func advancedValueBlock(
        _ text: String,
        emphasized: Bool = false
    ) -> some View {
        Text(verbatim: displayConnectorText(text))
            .font(emphasized ? PrimitiveTokens.Typography.codeStrong : PrimitiveTokens.Typography.code)
            .foregroundStyle(emphasized ? SemanticTokens.Text.primary : SemanticTokens.Text.secondary)
            .textSelection(.enabled)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PrimitiveTokens.Space.xs)
            .padding(.vertical, PrimitiveTokens.Space.xs)
            .background(SemanticTokens.Surface.raisedFill)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: PrimitiveTokens.Radius.sm,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: PrimitiveTokens.Radius.sm,
                    style: .continuous
                )
                .stroke(SemanticTokens.Border.subtle, lineWidth: PrimitiveTokens.Stroke.subtle)
            }
            .fixedSize(horizontal: false, vertical: true)
    }

    private func advancedMessageBlock(_ text: String) -> some View {
        Text(text)
            .font(PrimitiveTokens.Typography.meta)
            .foregroundStyle(SemanticTokens.Text.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func displayConnectorText(_ text: String) -> String {
        var displayText = text
        let homePath = NSHomeDirectory()
        if !homePath.isEmpty {
            displayText = displayText.replacingOccurrences(of: homePath, with: "~")
        }

        if let repositoryRootPath = mcpConnectorSettingsModel.inspection.repositoryRootPath {
            let repositoryDisplayPath = "…/\(URL(fileURLWithPath: repositoryRootPath).lastPathComponent)"
            displayText = displayText.replacingOccurrences(of: repositoryRootPath, with: repositoryDisplayPath)
        }

        return displayText
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

private enum ConnectorChipTone {
    case neutral
    case accent
    case success
    case warning
    case danger

    var fill: Color {
        switch self {
        case .neutral:
            return SemanticTokens.Surface.raisedFill
        case .accent:
            return SemanticTokens.Accent.primary.opacity(0.12)
        case .success:
            return Color(nsColor: .systemGreen).opacity(0.14)
        case .warning:
            return Color(nsColor: .systemOrange).opacity(0.14)
        case .danger:
            return Color(nsColor: .systemRed).opacity(0.14)
        }
    }

    var border: Color {
        switch self {
        case .neutral:
            return SemanticTokens.Border.subtle
        case .accent:
            return SemanticTokens.Accent.primary.opacity(0.28)
        case .success:
            return Color(nsColor: .systemGreen).opacity(0.34)
        case .warning:
            return Color(nsColor: .systemOrange).opacity(0.34)
        case .danger:
            return Color(nsColor: .systemRed).opacity(0.34)
        }
    }

    var foreground: Color {
        switch self {
        case .neutral:
            return SemanticTokens.Text.primary
        case .accent:
            return SemanticTokens.Accent.primary
        case .success:
            return Color(nsColor: .systemGreen)
        case .warning:
            return Color(nsColor: .systemOrange)
        case .danger:
            return Color(nsColor: .systemRed)
        }
    }
}
