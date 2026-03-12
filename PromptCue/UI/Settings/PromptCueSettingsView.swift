import KeyboardShortcuts
import SwiftUI

@MainActor
struct PromptCueSettingsView: View {
    let selectedTab: SettingsTab
    let onSelectTab: ((SettingsTab) -> Void)?
    @ObservedObject private var screenshotSettingsModel: ScreenshotSettingsModel
    @ObservedObject private var exportTailSettingsModel: PromptExportTailSettingsModel
    @ObservedObject private var retentionSettingsModel: CardRetentionSettingsModel
    @ObservedObject private var cloudSyncSettingsModel: CloudSyncSettingsModel
    @ObservedObject private var appearanceSettingsModel: AppearanceSettingsModel
    @ObservedObject private var mcpConnectorSettingsModel: MCPConnectorSettingsModel
    @State private var installGuideClient: MCPConnectorClient?
    @State private var setupGuideClient: MCPConnectorClient?
    @State private var alternateSetupClient: MCPConnectorClient?
    @State private var expandedSetupClient: MCPConnectorClient?
    @State private var expandedManualSetupClient: MCPConnectorClient?
    @State private var expandedToolsClient: MCPConnectorClient?
    @State private var didCopySetupCommand = false
    @State private var didCopyConfigSnippet = false

    private let labelColumnWidth: CGFloat = PanelMetrics.settingsLabelColumnWidth
    private let advancedLabelColumnWidth: CGFloat = 92
    private let settingsSidebarRowHeight: CGFloat = 32
    private let settingsSidebarCornerRadius: CGFloat = 10
    private let settingsSidebarItemSpacing: CGFloat = 8
    private let settingsSidebarItemHorizontalPadding: CGFloat = 12
    private let settingsSidebarItemVerticalPadding: CGFloat = 4
    private let settingsSidebarIconSize: CGFloat = 24
    private let settingsSidebarIconTextSpacing: CGFloat = 4
    private let settingsSidebarIconCornerRadius: CGFloat = 6
    private let settingsGroupCornerRadius: CGFloat = 12
    private let settingsOuterPadding: CGFloat = 20
    private let settingsGroupInset: CGFloat = 10
    private let settingsFormRowMinHeight: CGFloat = 44
    private let settingsFieldCornerRadius: CGFloat = 10
    private let settingsToolbarTitleFont = Font.system(size: 15, weight: .bold)
    private let settingsSidebarFont = Font.system(size: 13, weight: .medium)
    private let settingsRowLabelFont = Font.system(size: 13, weight: .medium)
    private let settingsSupportingFont = Font.system(size: 11, weight: .regular)
    private let settingsSupportingStrongFont = Font.system(size: 11, weight: .semibold)

    init(
        selectedTab: SettingsTab,
        onSelectTab: ((SettingsTab) -> Void)? = nil,
        screenshotSettingsModel: ScreenshotSettingsModel,
        exportTailSettingsModel: PromptExportTailSettingsModel,
        retentionSettingsModel: CardRetentionSettingsModel,
        cloudSyncSettingsModel: CloudSyncSettingsModel,
        appearanceSettingsModel: AppearanceSettingsModel,
        mcpConnectorSettingsModel: MCPConnectorSettingsModel
    ) {
        self.selectedTab = selectedTab
        self.onSelectTab = onSelectTab
        self.screenshotSettingsModel = screenshotSettingsModel
        self.exportTailSettingsModel = exportTailSettingsModel
        self.retentionSettingsModel = retentionSettingsModel
        self.cloudSyncSettingsModel = cloudSyncSettingsModel
        self.appearanceSettingsModel = appearanceSettingsModel
        self.mcpConnectorSettingsModel = mcpConnectorSettingsModel
    }

    init() {
        self.selectedTab = .general
        self.onSelectTab = nil
        self.screenshotSettingsModel = ScreenshotSettingsModel()
        self.exportTailSettingsModel = PromptExportTailSettingsModel()
        self.retentionSettingsModel = CardRetentionSettingsModel()
        self.cloudSyncSettingsModel = CloudSyncSettingsModel()
        self.appearanceSettingsModel = AppearanceSettingsModel()
        self.mcpConnectorSettingsModel = MCPConnectorSettingsModel()
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Rectangle()
                .fill(settingsPaneDividerColor)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            settingsContentPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(
            width: PanelMetrics.settingsPanelWidth,
            height: PanelMetrics.settingsPanelHeight
        )
        .onAppear {
            screenshotSettingsModel.refresh()
            exportTailSettingsModel.refresh()
            retentionSettingsModel.refresh()
            cloudSyncSettingsModel.refresh()
            appearanceSettingsModel.refresh()
            mcpConnectorSettingsModel.refresh()
        }
        .onChange(of: mcpConnectorSettingsModel.connectionState) { _, newValue in
            if case .passed = newValue {
                expandedSetupClient = nil
                expandedManualSetupClient = nil
                return
            }

            expandedToolsClient = nil
        }
    }

    private var settingsContentPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.lg) {
                settingsPageHeader
                selectedTabContent
            }
            .padding(.horizontal, settingsOuterPadding)
            .padding(.top, settingsOuterPadding)
            .padding(.bottom, PrimitiveTokens.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(settingsContentBackgroundColor)
    }

    private var settingsPageHeader: some View {
        HStack(alignment: .center, spacing: PrimitiveTokens.Space.sm) {
            Text(selectedTab.title)
                .font(settingsToolbarTitleFont)
                .foregroundStyle(settingsPrimaryTextColor)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
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

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: settingsSidebarItemSpacing) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                settingsSidebarTab(tab)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, PrimitiveTokens.Space.lg)
        .padding(.horizontal, PrimitiveTokens.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: PanelMetrics.settingsSidebarWidth)
        .background(settingsSidebarBackgroundColor)
    }

    private func settingsSidebarTab(_ tab: SettingsTab) -> some View {
        Button {
            onSelectTab?(tab)
        } label: {
            HStack(spacing: settingsSidebarIconTextSpacing) {
                settingsSidebarIcon(tab)

                Text(tab.title)
                    .font(settingsSidebarFont)
                    .foregroundStyle(sidebarTabForeground(tab))
                    .lineLimit(1)
            }
            .frame(minHeight: settingsSidebarRowHeight, alignment: .leading)
            .padding(.horizontal, settingsSidebarItemHorizontalPadding)
            .padding(.vertical, settingsSidebarItemVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sidebarTabBackground(tab))
            .contentShape(RoundedRectangle(cornerRadius: settingsSidebarCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func settingsSidebarIcon(_ tab: SettingsTab) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: settingsSidebarIconCornerRadius, style: .continuous)
                .fill(tab.sidebarIconColor)

            Image(systemName: tab.sidebarIconName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: settingsSidebarIconSize, height: settingsSidebarIconSize)
    }

    private func sidebarTabForeground(_ tab: SettingsTab) -> Color {
        tab == selectedTab ? .white : settingsPrimaryTextColor
    }

    @ViewBuilder
    private func sidebarTabBackground(_ tab: SettingsTab) -> some View {
        RoundedRectangle(cornerRadius: settingsSidebarCornerRadius, style: .continuous)
            .fill(tab == selectedTab ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
    }

    @ViewBuilder
    private var generalContent: some View {
        settingsSection(
            title: "Appearance",
            footer: "Choose whether Backtick follows the system theme or forces a specific mode."
        ) {
            settingsRows {
                settingsFormRow("Theme", showsDivider: false) {
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
            settingsRows {
                settingsFormRow("Quick Capture") {
                    HStack {
                        Spacer(minLength: 0)
                        KeyboardShortcuts.Recorder(for: .quickCapture)
                    }
                }

                settingsFormRow("Show Stack", showsDivider: false) {
                    HStack {
                        Spacer(minLength: 0)
                        KeyboardShortcuts.Recorder(for: .toggleStackPanel)
                    }
                }
            }
        }

        sectionDivider

        settingsSection(
            title: "iCloud Sync",
            footer: "Sync cards across your Macs via iCloud. Screenshots stay local."
        ) {
            settingsRows {
                settingsFormRow("Sync", verticalAlignment: .top) {
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

                settingsFormRow("Status", showsDivider: false) {
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
            settingsRows {
                settingsFormRow("Status") {
                    Text(screenshotStatusTitle)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                settingsFormRow("Folder", verticalAlignment: .top, showsDivider: false) {
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
    }

    @ViewBuilder
    private var stackContent: some View {
        settingsSection(
            title: "Retention",
            footer: "Cards stay until you delete them unless auto-expire is enabled."
        ) {
            settingsRows {
                settingsFormRow("Card Lifetime", verticalAlignment: .top, showsDivider: false) {
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
            settingsRows {
                settingsFormRow("Behavior", verticalAlignment: .top) {
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

                settingsFormRow("Tail Text", verticalAlignment: .top) {
                    settingsFieldSurface {
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
                    }
                }

                settingsFormRow("Preview", verticalAlignment: .top, showsDivider: false) {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                        HStack {
                            Spacer()

                            Button("Reset to Default") {
                                exportTailSettingsModel.resetToDefault()
                            }
                            .controlSize(.small)
                        }

                        settingsFieldSurface {
                            Text(exportTailSettingsModel.previewText)
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(SemanticTokens.Text.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var connectorsContent: some View {
        if focusedConnectorClients.isEmpty {
            settingsGroupSurface {
                Text("Connector status is unavailable right now.")
                    .font(settingsRowLabelFont)
                    .foregroundStyle(settingsSecondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, settingsGroupInset)
                    .padding(.vertical, PrimitiveTokens.Space.sm)
            }
        } else {
            settingsGroupSurface {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(focusedConnectorClients.enumerated()), id: \.element.client) { index, client in
                        focusedConnectorRow(client, showsDivider: index < focusedConnectorClients.count - 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func focusedConnectorRow(
        _ client: MCPConnectorClientStatus,
        showsDivider: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
            HStack(alignment: .center, spacing: PrimitiveTokens.Space.sm) {
                connectorClientBadge(
                    for: client.client,
                    tone: connectorStatusTone(for: client)
                )

                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxxs) {
                    Text(client.client.title)
                        .font(PrimitiveTokens.Typography.bodyStrong)
                        .foregroundStyle(SemanticTokens.Text.primary)

                    Text(focusedConnectorDetail(for: client))
                        .font(PrimitiveTokens.Typography.meta)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: PrimitiveTokens.Space.xs)

                focusedConnectorAccessory(for: client)
            }

            if shouldShowInlineSetup(for: client) {
                connectorInlinePanel {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                        Text(configuredSetupPrompt(for: client))
                            .font(PrimitiveTokens.Typography.meta)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let addCommand = client.addCommand {
                            advancedValueBlock(addCommand, emphasized: true)
                        }

                        HStack(spacing: PrimitiveTokens.Space.xs) {
                            Button(didCopySetupCommand ? "Copied" : "Copy Command") {
                                mcpConnectorSettingsModel.copyAddCommand(for: client.client)
                                showSetupCommandCopiedFeedback()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)

                            Button(
                                isManualSetupExpanded(for: client)
                                    ? "Hide Manual Setup"
                                    : "Use Config File Instead"
                            ) {
                                toggleManualSetup(for: client)
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                        }

                        if isManualSetupExpanded(for: client),
                           let configSnippet = client.configSnippet {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                                Text("Paste this into the \(client.client.title) config file instead.")
                                    .font(PrimitiveTokens.Typography.meta)
                                    .foregroundStyle(SemanticTokens.Text.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                advancedValueBlock(configSnippet)

                                HStack(spacing: PrimitiveTokens.Space.xs) {
                                    Button(didCopyConfigSnippet ? "Copied" : "Copy Config") {
                                        mcpConnectorSettingsModel.copyConfigSnippet(for: client.client)
                                        showConfigSnippetCopiedFeedback()
                                    }
                                    .controlSize(.small)

                                    Button("Open \(client.client.title) Config") {
                                        mcpConnectorSettingsModel.openPreferredConfig(for: client.client)
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }

            if shouldShowRepairBlock(for: client) {
                connectorInlinePanel {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                        Text("\(client.client.title) needs one repair before Backtick can respond again.")
                            .font(PrimitiveTokens.Typography.metaStrong)
                            .foregroundStyle(ConnectorChipTone.danger.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let failureDetail = mcpConnectorSettingsModel.clientFailureDetail(for: client) {
                            advancedMessageBlock(failureDetail)
                        }

                        HStack(spacing: PrimitiveTokens.Space.xs) {
                            Button("Verify Again") {
                                mcpConnectorSettingsModel.runServerTest()
                            }
                            .controlSize(.small)
                            .disabled(mcpConnectorSettingsModel.connectionState.isRunning)

                            Button("Open \(client.client.title) Config") {
                                mcpConnectorSettingsModel.openPreferredConfig(for: client.client)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            if shouldShowConnectedTools(for: client) {
                connectorInlinePanel {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                        Text("\(mcpConnectorSettingsModel.connectedToolNames(for: client).count) tools are ready in \(client.client.title).")
                            .font(PrimitiveTokens.Typography.metaStrong)
                            .foregroundStyle(SemanticTokens.Text.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        connectorToolGrid(toolNames: mcpConnectorSettingsModel.connectedToolNames(for: client))
                    }
                }
            }

            if showsDivider {
                Rectangle()
                    .fill(settingsRowSeparatorColor)
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, settingsGroupInset)
        .padding(.vertical, PrimitiveTokens.Space.sm)
    }

    private func focusedConnectorDetail(for client: MCPConnectorClientStatus) -> String {
        if !mcpConnectorSettingsModel.isServerAvailable {
            return "Restart Backtick, then try again."
        }

        if !client.hasDetectedCLI {
            return "Install \(client.client.title) on this Mac."
        }

        if !client.hasConfiguredScope {
            return "Not connected yet."
        }

        switch mcpConnectorSettingsModel.connectionState {
        case .idle:
            return "Connected, but not verified yet."
        case .running:
            return "Checking the connection now."
        case .passed(let report):
            return "Connected. \(report.toolNames.count) tools available."
        case .failed:
            return "Connected, but verification failed."
        }
    }

    private func focusedPrimaryAction(for client: MCPConnectorClientStatus) -> MCPConnectorPrimaryAction? {
        guard mcpConnectorSettingsModel.isServerAvailable else {
            return nil
        }

        return mcpConnectorSettingsModel.primaryAction(for: client)
    }

    @ViewBuilder
    private func focusedConnectorAccessory(for client: MCPConnectorClientStatus) -> some View {
        if !mcpConnectorSettingsModel.isServerAvailable {
            EmptyView()
        } else {
            switch focusedPrimaryAction(for: client) {
            case .copyAddCommand:
                Button(isSetupExpanded(for: client) ? "Hide" : "Connect") {
                    let wasExpanded = isSetupExpanded(for: client)
                    expandedSetupClient = wasExpanded ? nil : client.client
                    expandedManualSetupClient = nil
                    expandedToolsClient = nil
                    if !wasExpanded {
                        didCopySetupCommand = false
                    }
                }
            case .openDocumentation:
                Button("Install") {
                    mcpConnectorSettingsModel.openDocumentation(for: client.client)
                }
            case .runServerTest:
                Button(repairActionTitle(for: client)) {
                    mcpConnectorSettingsModel.runServerTest()
                }
                .disabled(mcpConnectorSettingsModel.connectionState.isRunning)
            case nil:
                if case .passed = mcpConnectorSettingsModel.connectionState,
                   client.hasConfiguredScope {
                    HStack(spacing: PrimitiveTokens.Space.xs) {
                        Text("Connected")
                            .font(PrimitiveTokens.Typography.metaStrong)
                            .foregroundStyle(ConnectorChipTone.success.foreground)

                        Button(
                            isToolsExpanded(for: client)
                                ? "Hide Tools"
                                : "Show Tools"
                        ) {
                            expandedToolsClient = isToolsExpanded(for: client) ? nil : client.client
                        }
                        .controlSize(.small)
                    }
                } else {
                    EmptyView()
                }
            }
        }
    }

    private func repairActionTitle(for client: MCPConnectorClientStatus) -> String {
        if case .failed = mcpConnectorSettingsModel.connectionState {
            return "Fix"
        }

        return "Verify"
    }

    private func connectorStatusTone(for client: MCPConnectorClientStatus) -> ConnectorChipTone {
        guard client.hasConfiguredScope else {
            return .neutral
        }

        switch mcpConnectorSettingsModel.connectionState {
        case .passed:
            return .success
        case .failed:
            return .danger
        case .idle, .running:
            return .neutral
        }
    }

    private func connectorStatusDotColor(for tone: ConnectorChipTone) -> Color {
        switch tone {
        case .neutral:
            return SemanticTokens.Text.secondary
        case .accent, .success, .warning, .danger:
            return tone.foreground
        }
    }

    private func configuredSetupPrompt(for client: MCPConnectorClientStatus) -> String {
        if client.hasOtherConfigFiles {
            return "Run this in Terminal and \(client.client.title) will pick up Backtick from the existing config."
        }

        return "Copy this command, paste it into Terminal, and press Return."
    }

    private func shouldShowInlineSetup(for client: MCPConnectorClientStatus) -> Bool {
        guard client.hasDetectedCLI, !client.hasConfiguredScope else {
            return false
        }

        return expandedSetupClient == client.client
    }

    private func shouldShowRepairBlock(for client: MCPConnectorClientStatus) -> Bool {
        guard client.hasConfiguredScope else {
            return false
        }

        if case .failed = mcpConnectorSettingsModel.connectionState {
            return true
        }

        return false
    }

    private func shouldShowConnectedTools(for client: MCPConnectorClientStatus) -> Bool {
        guard client.hasConfiguredScope else {
            return false
        }

        guard case .passed = mcpConnectorSettingsModel.connectionState else {
            return false
        }

        return expandedToolsClient == client.client
    }

    private func isSetupExpanded(for client: MCPConnectorClientStatus) -> Bool {
        expandedSetupClient == client.client
    }

    private func isManualSetupExpanded(for client: MCPConnectorClientStatus) -> Bool {
        expandedManualSetupClient == client.client
    }

    private func isToolsExpanded(for client: MCPConnectorClientStatus) -> Bool {
        expandedToolsClient == client.client
    }

    private func toggleManualSetup(for client: MCPConnectorClientStatus) {
        let isExpanded = isManualSetupExpanded(for: client)
        expandedManualSetupClient = isExpanded ? nil : client.client
        if !isExpanded {
            didCopyConfigSnippet = false
        }
    }

    private func connectorInlinePanel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
            content()
        }
        .padding(PrimitiveTokens.Space.sm)
        .background(settingsInlinePanelFill)
        .clipShape(RoundedRectangle(cornerRadius: settingsGroupCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: settingsGroupCornerRadius, style: .continuous)
                .stroke(settingsFormGroupBorder, lineWidth: PrimitiveTokens.Stroke.subtle)
        }
    }

    private func connectorToolGrid(toolNames: [String]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: PrimitiveTokens.Space.xs)],
            alignment: .leading,
            spacing: PrimitiveTokens.Space.xs
        ) {
            ForEach(toolNames, id: \.self) { toolName in
                PromptCueChip(
                    fill: SemanticTokens.Surface.raisedFill,
                    border: SemanticTokens.Border.subtle
                ) {
                    Text(toolName)
                        .font(PrimitiveTokens.Typography.codeStrong)
                        .foregroundStyle(SemanticTokens.Text.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func missingCLIConnectorSection(_ client: MCPConnectorClientStatus) -> some View {
        settingsSection(title: client.client.title) {
            connectorCard {
                HStack(alignment: .top, spacing: PrimitiveTokens.Space.md) {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                        Text("Install \(client.client.title)")
                            .font(PrimitiveTokens.Typography.bodyStrong)
                            .foregroundStyle(SemanticTokens.Text.primary)

                        Text("Backtick connects through \(client.client.title). Install it first, then come back here for the next step.")
                            .font(PrimitiveTokens.Typography.body)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: PrimitiveTokens.Space.sm)

                    Button("Install \(client.client.title)") {
                        installGuideClient = client.client
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func connectorSection(_ client: MCPConnectorClientStatus) -> some View {
        settingsSection(
            title: client.client.title,
            footer: mcpConnectorSettingsModel.clientProgressSummary(for: client)
        ) {
            connectorCard {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
                    HStack(alignment: .top, spacing: PrimitiveTokens.Space.md) {
                        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                            Text(mcpConnectorSettingsModel.clientNextStepTitle(for: client))
                                .font(PrimitiveTokens.Typography.bodyStrong)
                                .foregroundStyle(SemanticTokens.Text.primary)

                            Text(mcpConnectorSettingsModel.clientNextStepDetail(for: client))
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(SemanticTokens.Text.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Spacer(minLength: PrimitiveTokens.Space.sm)

                        if let primaryAction = mcpConnectorSettingsModel.primaryAction(for: client),
                           let actionTitle = mcpConnectorSettingsModel.primaryActionTitle(for: client) {
                            Button(actionTitle) {
                                handleConnectorPrimaryAction(primaryAction, for: client)
                            }
                            .controlSize(.small)
                            .disabled(
                                primaryAction == .runServerTest
                                    && mcpConnectorSettingsModel.connectionState.isRunning
                            )
                        }
                    }

                    if let failureDetail = mcpConnectorSettingsModel.clientFailureDetail(for: client) {
                        connectorNotice(
                            title: "Fix this first.",
                            message: failureDetail,
                            tone: .danger
                        )
                    } else if client.hasOtherConfigFiles, !client.hasConfiguredScope {
                        connectorNotice(
                            title: "Backtick is missing from this config.",
                            message: "Open the config file or run the setup command to add Backtick before you verify anything.",
                            tone: .warning
                        )
                    }

                    HStack(spacing: PrimitiveTokens.Space.xs) {
                        if client.hasDetectedCLI {
                            Button(mcpConnectorSettingsModel.configButtonTitle(for: client)) {
                                mcpConnectorSettingsModel.revealPreferredConfig(for: client.client)
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
                                                Button("Copy Setup Command") {
                                                    mcpConnectorSettingsModel.copyAddCommand(for: client.client)
                                                }
                                                .controlSize(.small)

                                                Button("Open Install Guide") {
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
                        DisclosureGroup(mcpConnectorSettingsModel.troubleshootingTitle(for: client)) {
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
                                    Button("Open Install Guide") {
                                        mcpConnectorSettingsModel.openDocumentation(for: client.client)
                                    }
                                    .controlSize(.small)

                                    if client.hasDetectedCLI {
                                        Button("Open Config File") {
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
                        DisclosureGroup("Claude Automation") {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                                advancedMessageBlock(
                                    "Claude runs that use `--permission-mode dontAsk` still need Backtick tools listed in `--allowedTools`."
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

    private func connectorNotice(
        title: String,
        message: String,
        tone: ConnectorChipTone
    ) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
            Text(title)
                .font(PrimitiveTokens.Typography.metaStrong)
                .foregroundStyle(tone.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(message)
                .font(PrimitiveTokens.Typography.meta)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PrimitiveTokens.Space.sm)
        .padding(.vertical, PrimitiveTokens.Space.sm)
        .background(tone.fill)
        .clipShape(RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                .stroke(tone.border, lineWidth: PrimitiveTokens.Stroke.subtle)
        }
    }

    private func handleConnectorPrimaryAction(
        _ action: MCPConnectorPrimaryAction,
        for client: MCPConnectorClientStatus
    ) {
        switch action {
        case .copyAddCommand:
            setupGuideClient = client.client
        case .openDocumentation:
            installGuideClient = client.client
        case .runServerTest:
            mcpConnectorSettingsModel.performPrimaryAction(action, for: client)
        }
    }

    @ViewBuilder
    private func connectorSetupSheet(for client: MCPConnectorClient) -> some View {
        if let status = mcpConnectorSettingsModel.clients.first(where: { $0.client == client }) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.lg) {
                        HStack(alignment: .center, spacing: PrimitiveTokens.Space.md) {
                            connectorClientBadge(for: client)

                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                                Text("Connect \(client.title)")
                                    .font(PrimitiveTokens.Typography.panelTitle)
                                    .foregroundStyle(SemanticTokens.Text.primary)

                                Text("Copy this command, run it in Terminal, then return here and click Verify.")
                                    .font(PrimitiveTokens.Typography.body)
                                    .foregroundStyle(SemanticTokens.Text.secondary)
                            }
                        }

                        if let addCommand = status.addCommand {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                                advancedValueBlock(addCommand)

                                Button(didCopySetupCommand ? "Copied" : "Copy Command") {
                                    mcpConnectorSettingsModel.copyAddCommand(for: client)
                                    showSetupCommandCopiedFeedback()
                                }

                                Text("After you run it in Terminal, close this sheet and click Verify.")
                                    .font(PrimitiveTokens.Typography.meta)
                                    .foregroundStyle(SemanticTokens.Text.secondary)
                            }
                        }

                        if status.hasDetectedCLI || status.configSnippet != nil {
                            HStack {
                                Button("Need another way?") {
                                    alternateSetupClient = client
                                }
                                .buttonStyle(.plain)
                                .font(PrimitiveTokens.Typography.meta)
                                .foregroundStyle(SemanticTokens.Text.secondary)

                                Spacer()
                            }
                        }
                    }
                    .padding(PrimitiveTokens.Space.xl)
                }

                Divider()
                    .overlay(SemanticTokens.Border.subtle)

                HStack(spacing: PrimitiveTokens.Space.xs) {
                    Spacer()

                    Button("Done") {
                        setupGuideClient = nil
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, PrimitiveTokens.Space.xl)
                .padding(.vertical, PrimitiveTokens.Space.sm)
            }
            .frame(width: 520, height: 420)
            .background(SemanticTokens.Surface.previewBackdropBottom)
            .onAppear {
                didCopySetupCommand = false
            }
        } else {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
                Text("Setup details unavailable.")
                    .font(PrimitiveTokens.Typography.bodyStrong)
                    .foregroundStyle(SemanticTokens.Text.primary)

                Button("Close") {
                    setupGuideClient = nil
                }
                .controlSize(.small)
            }
            .padding(PrimitiveTokens.Space.xl)
            .frame(width: 420)
        }
    }

    @ViewBuilder
    private func connectorAlternateSetupSheet(for client: MCPConnectorClient) -> some View {
        if let status = mcpConnectorSettingsModel.clients.first(where: { $0.client == client }) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.lg) {
                        HStack(alignment: .center, spacing: PrimitiveTokens.Space.md) {
                            connectorClientBadge(for: client)

                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                                Text("Connect \(client.title) another way")
                                    .font(PrimitiveTokens.Typography.panelTitle)
                                    .foregroundStyle(SemanticTokens.Text.primary)

                                Text("Paste this into the \(client.title) config file instead of running the command.")
                                    .font(PrimitiveTokens.Typography.body)
                                    .foregroundStyle(SemanticTokens.Text.secondary)
                            }
                        }

                        if status.hasDetectedCLI {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                                Button("Open \(client.title) Config") {
                                    mcpConnectorSettingsModel.openPreferredConfig(for: client)
                                }
                                .controlSize(.small)
                            }
                        }

                        if let configSnippet = status.configSnippet {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                                advancedValueBlock(configSnippet)

                                Button(didCopyConfigSnippet ? "Copied" : "Copy Config Snippet") {
                                    mcpConnectorSettingsModel.copyConfigSnippet(for: client)
                                    showConfigSnippetCopiedFeedback()
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(PrimitiveTokens.Space.xl)
                }

                Divider()
                    .overlay(SemanticTokens.Border.subtle)

                HStack(spacing: PrimitiveTokens.Space.xs) {
                    Spacer()

                    Button("Done") {
                        alternateSetupClient = nil
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, PrimitiveTokens.Space.xl)
                .padding(.vertical, PrimitiveTokens.Space.sm)
            }
            .frame(width: 520, height: 360)
            .background(SemanticTokens.Surface.previewBackdropBottom)
            .onAppear {
                didCopyConfigSnippet = false
            }
        } else {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.md) {
                Text("Manual setup details unavailable.")
                    .font(PrimitiveTokens.Typography.bodyStrong)
                    .foregroundStyle(SemanticTokens.Text.primary)

                Button("Close") {
                    alternateSetupClient = nil
                }
                .controlSize(.small)
            }
            .padding(PrimitiveTokens.Space.xl)
            .frame(width: 420)
        }
    }

    private func connectorInstallSheet(for client: MCPConnectorClient) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.lg) {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                Text("Install \(client.title)")
                    .font(PrimitiveTokens.Typography.panelTitle)
                    .foregroundStyle(SemanticTokens.Text.primary)

                Text("Backtick needs the \(client.title) CLI before setup can continue.")
                    .font(PrimitiveTokens.Typography.body)
                    .foregroundStyle(SemanticTokens.Text.secondary)
            }

            connectorNotice(
                title: "What to do",
                message: "1. Open the install guide. 2. Install \(client.title). 3. Return here. Backtick will show the next setup step automatically.",
                tone: .accent
            )

            HStack(spacing: PrimitiveTokens.Space.xs) {
                Button("Open Install Guide") {
                    mcpConnectorSettingsModel.openDocumentation(for: client)
                }
                .controlSize(.small)

                Spacer()

                Button("Done") {
                    installGuideClient = nil
                }
                .controlSize(.small)
            }
        }
        .padding(PrimitiveTokens.Space.xl)
        .frame(width: 460)
        .background(SemanticTokens.Surface.previewBackdropBottom)
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
            return false
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

    private var focusedConnectorClients: [MCPConnectorClientStatus] {
        let order = Dictionary(uniqueKeysWithValues: MCPConnectorClient.allCases.enumerated().map { ($1, $0) })
        return mcpConnectorSettingsModel.clients.sorted {
            (order[$0.client] ?? 0) < (order[$1.client] ?? 0)
        }
    }

    private func connectorClientBadge(
        for client: MCPConnectorClient,
        tone: ConnectorChipTone = .neutral
    ) -> some View {
        let badgeShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return ZStack {
            if let assetName = clientBadgeAssetName(for: client) {
                Image(assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(badgeShape)
            } else {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                    .fill(SemanticTokens.Text.primary.opacity(0.9))

                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                    .stroke(SemanticTokens.Text.primary.opacity(0.08), lineWidth: PrimitiveTokens.Stroke.subtle)

                Image(systemName: clientBadgeSymbol(for: client))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SemanticTokens.Surface.previewBackdropBottom)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(SemanticTokens.Surface.previewBackdropBottom)
                    .frame(width: 12, height: 12)

                Circle()
                    .fill(connectorStatusDotColor(for: tone))
                    .frame(width: 9, height: 9)
            }
                .offset(x: 1, y: 1)
        }
        .frame(width: 44, height: 44)
    }

    private func clientBadgeAssetName(for client: MCPConnectorClient) -> String? {
        switch client {
        case .claudeCode:
            return "ClaudeCodeIcon"
        case .codex:
            return "CodexIcon"
        }
    }

    private func clientBadgeSymbol(for client: MCPConnectorClient) -> String {
        switch client {
        case .claudeCode:
            return "chevron.left.forwardslash.chevron.right"
        case .codex:
            return "terminal"
        }
    }

    private func showSetupCommandCopiedFeedback() {
        didCopySetupCommand = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopySetupCommand = false
        }
    }

    private func showConfigSnippetCopiedFeedback() {
        didCopyConfigSnippet = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopyConfigSnippet = false
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
        Color.clear
            .frame(height: 0)
    }

    private func settingsSection<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxxs) {
                Text(title)
                    .font(settingsSupportingStrongFont)
                    .foregroundStyle(settingsSecondaryTextColor)

                if let footer, footer.isEmpty == false {
                    Text(footer)
                        .font(settingsSupportingFont)
                        .foregroundStyle(settingsSecondaryTextColor)
                }
            }

            settingsGroupSurface {
                content()
            }
        }
    }

    private func settingsRows<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            content()
        }
    }

    private func settingsFormRow<Content: View>(
        _ label: String,
        verticalAlignment: VerticalAlignment = .center,
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: verticalAlignment, spacing: PrimitiveTokens.Space.md) {
            Text(label)
                .font(settingsRowLabelFont)
                .foregroundStyle(settingsPrimaryTextColor)
                .frame(width: labelColumnWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: settingsFormRowMinHeight, alignment: .leading)
        .padding(.horizontal, settingsGroupInset)
        .padding(.vertical, PrimitiveTokens.Space.xs)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(settingsRowSeparatorColor)
                    .frame(height: 1)
            }
        }
    }

    private func settingsFieldSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
            content()
        }
        .padding(PrimitiveTokens.Space.sm)
        .background(settingsInlinePanelFill)
        .clipShape(RoundedRectangle(cornerRadius: settingsFieldCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: settingsFieldCornerRadius, style: .continuous)
                .stroke(settingsFormGroupBorder, lineWidth: PrimitiveTokens.Stroke.subtle)
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
            .font(settingsSupportingFont)
            .foregroundStyle(settingsSecondaryTextColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsGroupSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(settingsFormGroupFill)
        .clipShape(RoundedRectangle(cornerRadius: settingsGroupCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: settingsGroupCornerRadius, style: .continuous)
                .stroke(settingsFormGroupBorder, lineWidth: PrimitiveTokens.Stroke.subtle)
        }
    }

    private func binding<Value>(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: get, set: set)
    }

    private var settingsPrimaryTextColor: Color {
        adaptiveSettingsColor(
            light: NSColor.black.withAlphaComponent(0.85),
            dark: NSColor.white.withAlphaComponent(0.88)
        )
    }

    private var settingsSecondaryTextColor: Color {
        adaptiveSettingsColor(
            light: NSColor.black.withAlphaComponent(0.5),
            dark: NSColor.white.withAlphaComponent(0.55)
        )
    }

    private var settingsSidebarIconColor: Color {
        adaptiveSettingsColor(
            light: NSColor.black.withAlphaComponent(0.72),
            dark: NSColor.white.withAlphaComponent(0.72)
        )
    }

    private var settingsSidebarPlateFill: Color {
        adaptiveSettingsColor(
            light: NSColor(calibratedWhite: 0.96, alpha: 0.68),
            dark: NSColor(calibratedWhite: 0.16, alpha: 0.76)
        )
    }

    private var settingsSidebarPlateBorder: Color {
        adaptiveSettingsColor(
            light: NSColor.white.withAlphaComponent(0.44),
            dark: NSColor.white.withAlphaComponent(0.10)
        )
    }

    private var settingsSidebarSelectionFill: Color {
        adaptiveSettingsColor(
            light: NSColor.black.withAlphaComponent(0.11),
            dark: NSColor.white.withAlphaComponent(0.12)
        )
    }

    private var settingsPaneDividerColor: Color {
        adaptiveSettingsColor(
            light: NSColor.black.withAlphaComponent(0.05),
            dark: NSColor.white.withAlphaComponent(0.08)
        )
    }

    private var settingsSidebarBackgroundColor: Color {
        adaptiveSettingsColor(
            light: NSColor(srgbRed: 225.0 / 255.0, green: 224.0 / 255.0, blue: 223.0 / 255.0, alpha: 1.0),
            dark: NSColor(srgbRed: 70.0 / 255.0, green: 70.0 / 255.0, blue: 69.0 / 255.0, alpha: 1.0)
        )
    }

    private var settingsContentBackgroundColor: Color {
        adaptiveSettingsColor(
            light: NSColor(srgbRed: 237.0 / 255.0, green: 237.0 / 255.0, blue: 236.0 / 255.0, alpha: 1.0),
            dark: NSColor(srgbRed: 43.0 / 255.0, green: 43.0 / 255.0, blue: 41.0 / 255.0, alpha: 1.0)
        )
    }

    private var settingsFormGroupFill: Color {
        adaptiveSettingsColor(
            light: NSColor.black.withAlphaComponent(0.03),
            dark: NSColor.white.withAlphaComponent(0.05)
        )
    }

    private var settingsInlinePanelFill: Color {
        adaptiveSettingsColor(
            light: NSColor.white.withAlphaComponent(0.60),
            dark: NSColor.white.withAlphaComponent(0.06)
        )
    }

    private var settingsFormGroupBorder: Color {
        adaptiveSettingsColor(
            light: NSColor.black.withAlphaComponent(0.05),
            dark: NSColor.white.withAlphaComponent(0.08)
        )
    }

    private var settingsRowSeparatorColor: Color {
        adaptiveSettingsColor(
            light: NSColor.black.withAlphaComponent(0.05),
            dark: NSColor.white.withAlphaComponent(0.08)
        )
    }

    private func adaptiveSettingsColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                switch appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]) {
                case .darkAqua, .vibrantDark:
                    return dark
                default:
                    return light
                }
            }
        )
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
