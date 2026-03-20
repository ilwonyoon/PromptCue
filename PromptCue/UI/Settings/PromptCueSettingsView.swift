import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
struct PromptCueSettingsView: View {
    @ObservedObject private var navigationModel: SettingsNavigationModel
    let onSelectTab: ((SettingsTab) -> Void)?
    @ObservedObject private var screenshotSettingsModel: ScreenshotSettingsModel
    @ObservedObject private var exportTailSettingsModel: PromptExportTailSettingsModel
    @ObservedObject private var retentionSettingsModel: CardRetentionSettingsModel
    @ObservedObject private var cloudSyncSettingsModel: CloudSyncSettingsModel
    @ObservedObject private var mcpConnectorSettingsModel: MCPConnectorSettingsModel
    @State private var installGuideClient: MCPConnectorClient?
    @State private var setupGuideClient: MCPConnectorClient?
    @State private var alternateSetupClient: MCPConnectorClient?
    @State private var expandedSetupClient: MCPConnectorClient?
    @State private var expandedManualSetupClient: MCPConnectorClient?
    @State private var expandedToolsClient: MCPConnectorClient?
    @State private var didCopySetupCommand = false
    @State private var didCopyConfigSnippet = false
    @State private var experimentalRemotePortDraft = ""
    @State private var experimentalRemotePublicBaseURLDraft = ""
    @State private var experimentalRemoteAPIKeyDraft = ""
    @State private var experimentalRemotePublicBaseURLValidationMessage: String?
    @State private var didCopyExperimentalRemoteEndpoint = false
    @State private var didCopyExperimentalRemotePublicEndpoint = false
    @State private var didCopyExperimentalRemoteAPIKey = false
    @State private var didCopyExperimentalRemoteTunnelCommand = false
    @State private var isExperimentalRemoteAdvancedExpanded = false

    init(
        selectedTab: SettingsTab,
        navigationModel: SettingsNavigationModel? = nil,
        onSelectTab: ((SettingsTab) -> Void)? = nil,
        screenshotSettingsModel: ScreenshotSettingsModel,
        exportTailSettingsModel: PromptExportTailSettingsModel,
        retentionSettingsModel: CardRetentionSettingsModel,
        cloudSyncSettingsModel: CloudSyncSettingsModel,
        mcpConnectorSettingsModel: MCPConnectorSettingsModel
    ) {
        _navigationModel = ObservedObject(
            wrappedValue: navigationModel ?? SettingsNavigationModel(selectedTab: selectedTab)
        )
        self.onSelectTab = onSelectTab
        self.screenshotSettingsModel = screenshotSettingsModel
        self.exportTailSettingsModel = exportTailSettingsModel
        self.retentionSettingsModel = retentionSettingsModel
        self.cloudSyncSettingsModel = cloudSyncSettingsModel
        self.mcpConnectorSettingsModel = mcpConnectorSettingsModel
    }

    init() {
        _navigationModel = ObservedObject(
            wrappedValue: SettingsNavigationModel(selectedTab: .general)
        )
        self.onSelectTab = nil
        self.screenshotSettingsModel = ScreenshotSettingsModel()
        self.exportTailSettingsModel = PromptExportTailSettingsModel()
        self.retentionSettingsModel = CardRetentionSettingsModel()
        self.cloudSyncSettingsModel = CloudSyncSettingsModel()
        self.mcpConnectorSettingsModel = MCPConnectorSettingsModel()
    }

    var body: some View {
        NavigationSplitView {
            settingsSidebar
                .navigationSplitViewColumnWidth(
                    min: SettingsTokens.Layout.sidebarWidth,
                    ideal: SettingsTokens.Layout.sidebarWidth,
                    max: SettingsTokens.Layout.sidebarWidth
                )
        } detail: {
            settingsContentPane
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(
            width: PanelMetrics.settingsPanelWidth,
            height: PanelMetrics.settingsPanelHeight
        )
        .onAppear {
            refreshSettingsModels()
            syncExperimentalRemoteDrafts(with: mcpConnectorSettingsModel.experimentalRemoteSettings)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSettingsModels()
        }
        .onChange(of: mcpConnectorSettingsModel.experimentalRemoteSettings) { _, newValue in
            syncExperimentalRemoteDrafts(with: newValue)
            if !newValue.isEnabled {
                isExperimentalRemoteAdvancedExpanded = false
            }
        }
        .onChange(of: mcpConnectorSettingsModel.connectionState) { _, newValue in
            if case .passed = newValue {
                expandedSetupClient = nil
                expandedManualSetupClient = nil
                return
            }

            expandedToolsClient = nil
        }
        .alert(
            "Connected",
            isPresented: Binding(
                get: { mcpConnectorSettingsModel.directConfigSuccessClient != nil },
                set: { if !$0 { mcpConnectorSettingsModel.directConfigSuccessClient = nil } }
            )
        ) {
            Button("OK") {
                mcpConnectorSettingsModel.directConfigSuccessClient = nil
            }
        } message: {
            if let client = mcpConnectorSettingsModel.directConfigSuccessClient {
                Text("Backtick has been added to \(client.title). Restart \(client.title) to activate, then try asking: \"List my Backtick notes\"")
            }
        }
    }

    private func refreshSettingsModels() {
        screenshotSettingsModel.refresh()
        exportTailSettingsModel.refresh()
        retentionSettingsModel.refresh()
        cloudSyncSettingsModel.refresh()
        mcpConnectorSettingsModel.refresh()
    }

    private var settingsContentPane: some View {
        selectedTabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .toolbar(removing: .sidebarToggle)
            .background {
                SettingsSemanticTokens.Surface.contentBackground
                    .ignoresSafeArea()
            }
    }

    private var settingsPageHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(navigationModel.selectedTab.title)
                .font(SettingsTokens.Typography.pageTitle)
                .foregroundStyle(SettingsSemanticTokens.Text.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch navigationModel.selectedTab {
        case .general:
            generalPage
        case .capture:
            capturePage
        case .stack:
            stackPage
        case .connectors:
            connectorsPage
        }
    }

    private var settingsSidebar: some View {
        ZStack {
            settingsSidebarBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: SettingsTokens.Layout.sidebarItemSpacing) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        SettingsSidebarItem(
                            title: tab.title,
                            icon: tab.sidebarIcon,
                            iconFill: tab.sidebarIconColor,
                            isSelected: tab == navigationModel.selectedTab,
                            usesManualSelection: true
                        ) {
                            if let onSelectTab {
                                onSelectTab(tab)
                            } else {
                                navigationModel.selectedTab = tab
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, SettingsTokens.Layout.sidebarHorizontalPadding)
                .padding(.vertical, SettingsTokens.Layout.sidebarVerticalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var settingsSidebarBackground: some View {
        ZStack {
            SettingsSemanticTokens.Surface.sidebarBackground

            LinearGradient(
                colors: [
                    SettingsSemanticTokens.Surface.sidebarBackgroundTopTint,
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    SettingsSemanticTokens.Surface.sidebarBackgroundBottomShade
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func settingsScrollPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let pageContent = content()

        return GeometryReader { proxy in
            let contentWidth = max(
                0,
                min(
                    SettingsTokens.Layout.contentMaxWidth,
                    proxy.size.width
                        - SettingsTokens.Layout.pageLeadingPadding
                        - SettingsTokens.Layout.pageTrailingPadding
                )
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    settingsPageHeader

                    VStack(alignment: .leading, spacing: SettingsTokens.Layout.sectionSpacing) {
                        pageContent
                    }
                    .padding(.top, SettingsTokens.Layout.titleToFirstSectionSpacing)
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.leading, SettingsTokens.Layout.pageLeadingPadding)
                .padding(.trailing, SettingsTokens.Layout.pageTrailingPadding)
                .padding(.top, SettingsTokens.Layout.pageTopPadding)
                .padding(.bottom, SettingsTokens.Layout.pageBottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var generalPage: some View {
        settingsScrollPage {
            generalSections
        }
    }

    private var capturePage: some View {
        settingsScrollPage {
            captureSections
        }
    }

    private var stackPage: some View {
        settingsScrollPage {
            stackSections
        }
    }

    private var connectorsPage: some View {
        settingsScrollPage {
            connectorsContent
        }
    }

    @ViewBuilder
    private var generalSections: some View {
        SettingsSection(
            title: "Shortcuts",
            titleFont: SettingsTokens.Typography.sectionTitleMedium,
            footer: "These shortcuts work globally."
        ) {
            SettingsRows {
                SettingsTwoColumnGroupRow("Quick Capture", contentAlignment: .trailing) {
                    KeyboardShortcuts.Recorder(for: .quickCapture)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                SettingsTwoColumnGroupRow(
                    "Show Stack",
                    showsDivider: false,
                    contentAlignment: .trailing
                ) {
                    KeyboardShortcuts.Recorder(for: .toggleStackPanel)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }

        SettingsSection(
            title: "iCloud Sync",
            footer: "Sync cards across your Macs via iCloud. Screenshots stay local."
        ) {
            SettingsRows {
                SettingsTwoColumnGroupRow("Sync", verticalAlignment: .top) {
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

                SettingsTwoColumnGroupRow("Status", showsDivider: false) {
                    SettingsStatusBadge(
                        title: cloudSyncSettingsModel.syncStatusText,
                        tone: cloudSyncStatusBadgeTone
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var captureSections: some View {
        SettingsSection(
            title: "Screenshots",
            titleFont: SettingsTokens.Typography.sectionTitleMedium,
            footer: "Auto-attach watches the folder you approve and checks the current macOS screenshot save location while capture is open."
        ) {
            SettingsRows {
                SettingsTwoColumnGroupRow("Status") {
                    SettingsStatusBadge(
                        title: screenshotStatusTitle,
                        tone: screenshotStatusBadgeTone
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsDetailGroupRow("Folder", showsDivider: false) {
                    Text(screenshotStatusDetail)
                        .font(PrimitiveTokens.Typography.bodyStrong)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } actions: {
                    Group {
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
    private var stackSections: some View {
        SettingsSection(
            title: "Retention",
            titleFont: SettingsTokens.Typography.sectionTitleMedium
        ) {
            SettingsRows {
                SettingsDetailGroupRow("Card Lifetime", showsDivider: false) {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                        Toggle(
                            "Auto-expire stack cards after 8 hours",
                            isOn: binding(
                                get: { retentionSettingsModel.isAutoExpireEnabled },
                                set: retentionSettingsModel.updateAutoExpireEnabled
                            )
                        )
                        .toggleStyle(.checkbox)

                        rowNote("Cards stay until you delete them unless auto-expire is enabled.")
                        rowNote("Off by default. Turn this on to restore the original 8-hour cleanup behavior.")
                    }
                }
            }
        }

        SettingsSection(
            title: "AI Export Tail",
            footer: "Saved cards stay unchanged. The tail is added only when you copy or export."
        ) {
            SettingsRows {
                SettingsDetailGroupRow("Behavior") {
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
                }

                SettingsLongFormGroupRow("Tail Text") {
                    SettingsInlinePanel {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                SettingsLongFormGroupRow(
                    "Preview",
                    showsDivider: false,
                    actionTitle: "Reset to Default",
                    action: {
                        exportTailSettingsModel.resetToDefault()
                    }
                ) {
                    SettingsInlinePanel {
                        Text(exportTailSettingsModel.previewText)
                            .font(PrimitiveTokens.Typography.body)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var connectorsContent: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Layout.sectionSpacing) {
            if focusedConnectorClients.isEmpty {
                SettingsGroupSurface {
                    Text("Connector status is unavailable right now.")
                        .font(SettingsTokens.Typography.rowLabel)
                        .foregroundStyle(SettingsSemanticTokens.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SettingsTokens.Layout.groupInset)
                        .padding(.vertical, PrimitiveTokens.Space.sm)
                }
            } else {
                SettingsGroupSurface {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(focusedConnectorClients.enumerated()), id: \.element.client) { index, client in
                            focusedConnectorRow(client, showsDivider: index < focusedConnectorClients.count - 1)
                        }
                    }
                }
            }

            SettingsSection(
                title: "ChatGPT (Experimental)",
                footer: "Experimental self-hosted ChatGPT connection. Turn this on to let Backtick host a local MCP endpoint on this Mac while your public HTTPS tunnel exposes it.",
                headerAccessory: {
                    Toggle(
                        "Enable ChatGPT connection",
                        isOn: binding(
                            get: { mcpConnectorSettingsModel.experimentalRemoteSettings.isEnabled },
                            set: mcpConnectorSettingsModel.updateExperimentalRemoteEnabled
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            ) {
                SettingsRows {
                    SettingsDetailGroupRow(
                        "Status",
                        showsDivider: mcpConnectorSettingsModel.experimentalRemoteSettings.isEnabled
                            || mcpConnectorSettingsModel.experimentalRemoteShouldShowInlinePublicBaseURL
                            || mcpConnectorSettingsModel.experimentalRemoteShouldShowInlineChatGPTMCPURL
                    ) {
                        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                            SettingsStatusBadge(
                                title: mcpConnectorSettingsModel.experimentalRemoteStatusPresentation.title,
                                tone: experimentalRemoteStatusTone
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                            rowNote(mcpConnectorSettingsModel.experimentalRemoteStatusPresentation.reason)

                            if let detail = mcpConnectorSettingsModel.experimentalRemoteStatusPresentation.detail {
                                rowNote(detail)
                            }

                            if experimentalRemoteHasPendingPortChange {
                                rowNote("Apply the local port change first. Backtick and ngrok must use the same port.")
                            }
                        }
                    } actions: {
                        if shouldShowExperimentalRemoteStatusAction,
                           let action = mcpConnectorSettingsModel.experimentalRemoteStatusPresentation.action {
                            Button(action.title) {
                                mcpConnectorSettingsModel.performExperimentalRemoteStatusAction(action)
                                if action == .copyPublicMCPURL {
                                    showExperimentalRemotePublicEndpointCopiedFeedback()
                                }
                            }
                            .disabled(action == .launchTunnel && experimentalRemoteHasPendingPortChange)
                            .controlSize(.small)
                        }
                    }

                    if mcpConnectorSettingsModel.experimentalRemoteShouldShowInlinePublicBaseURL {
                        SettingsDetailGroupRow("Tunnel URL") {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                                TextField(
                                    "https://your-ngrok-domain.ngrok-free.dev",
                                    text: binding(
                                        get: { experimentalRemotePublicBaseURLDraft },
                                        set: {
                                            experimentalRemotePublicBaseURLDraft = $0
                                            experimentalRemotePublicBaseURLValidationMessage = nil
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(PrimitiveTokens.Typography.code)
                                .onSubmit {
                                    commitExperimentalRemotePublicBaseURLDraft()
                                }

                                rowNote("Paste the `https://` base URL ngrok shows for this Mac. Leave off `/mcp`.")

                                if let validationMessage = experimentalRemotePublicBaseURLValidationMessage {
                                    rowNote(validationMessage)
                                }
                            }
                        } actions: {
                            if experimentalRemoteHasPendingPublicBaseURLChange {
                                Button("Apply") {
                                    commitExperimentalRemotePublicBaseURLDraft()
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    if mcpConnectorSettingsModel.experimentalRemoteShouldShowInlineChatGPTMCPURL,
                       let publicEndpoint = mcpConnectorSettingsModel.experimentalRemotePublicEndpoint {
                        SettingsDetailGroupRow(
                            "ChatGPT MCP URL",
                            showsDivider: mcpConnectorSettingsModel.experimentalRemoteSettings.isEnabled
                        ) {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                                Text(publicEndpoint)
                                    .font(PrimitiveTokens.Typography.codeStrong)
                                    .foregroundStyle(SemanticTokens.Text.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                rowNote("Paste this into ChatGPT when you create or recreate the Backtick app.")
                            }
                        } actions: {
                            Button(didCopyExperimentalRemotePublicEndpoint ? "Copied" : "Copy ChatGPT MCP URL") {
                                mcpConnectorSettingsModel.copyExperimentalRemotePublicEndpoint()
                                showExperimentalRemotePublicEndpointCopiedFeedback()
                            }
                            .controlSize(.small)
                        }
                    }

                    if mcpConnectorSettingsModel.experimentalRemoteSettings.isEnabled {
                        SettingsTwoColumnGroupRow(
                            "Advanced",
                            showsDivider: false
                        ) {
                            Button {
                                isExperimentalRemoteAdvancedExpanded.toggle()
                            } label: {
                                HStack(spacing: PrimitiveTokens.Space.xs) {
                                    Image(systemName: isExperimentalRemoteAdvancedExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(SemanticTokens.Text.secondary)

                                    Text("Show technical details")
                                        .font(SettingsTokens.Typography.rowLabel)
                                        .foregroundStyle(SettingsSemanticTokens.Text.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if isExperimentalRemoteAdvancedExpanded {
                            SettingsTwoColumnGroupRow(
                                "",
                                verticalAlignment: .top,
                                showsDivider: false
                            ) {
                                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                                        advancedDetailPane(label: "Authentication") {
                                            Picker(
                                                "Authentication",
                                                selection: binding(
                                                    get: { mcpConnectorSettingsModel.experimentalRemoteSettings.authMode },
                                                    set: mcpConnectorSettingsModel.updateExperimentalRemoteAuthMode
                                                )
                                            ) {
                                                ForEach(ExperimentalMCPHTTPAuthMode.allCases, id: \.self) { authMode in
                                                    Text(authMode.title).tag(authMode)
                                                }
                                            }
                                            .pickerStyle(.segmented)
                                            .frame(maxWidth: 260, alignment: .leading)
                                        }

                                        advancedDetailPane(label: "ngrok") {
                                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                                advancedValueBlock(
                                                    mcpConnectorSettingsModel.experimentalRemoteRecommendedTunnelCommand,
                                                    emphasized: true
                                                )

                                                advancedMessageBlock(
                                                    mcpConnectorSettingsModel.experimentalRemoteRecommendedTunnelSummary
                                                )

                                                if shouldShowExperimentalRemoteTunnelActions {
                                                    HStack(spacing: PrimitiveTokens.Space.xs) {
                                                        if mcpConnectorSettingsModel.experimentalRemoteRecommendedTunnelPath != nil {
                                                            Button("Launch ngrok") {
                                                                _ = mcpConnectorSettingsModel.launchExperimentalRemoteRecommendedTunnelInTerminal()
                                                            }
                                                            .disabled(experimentalRemoteHasPendingPortChange)
                                                            .controlSize(.small)
                                                        }

                                                        if mcpConnectorSettingsModel.experimentalRemoteRecommendedTunnelPath != nil {
                                                            Button(didCopyExperimentalRemoteTunnelCommand ? "Copied" : "Copy Command") {
                                                                mcpConnectorSettingsModel.copyExperimentalRemoteRecommendedTunnelCommand()
                                                                showExperimentalRemoteTunnelCommandCopiedFeedback()
                                                            }
                                                            .disabled(experimentalRemoteHasPendingPortChange)
                                                            .controlSize(.small)
                                                        }

                                                        if mcpConnectorSettingsModel.experimentalRemoteRecommendedTunnelPath == nil {
                                                            Button("Install ngrok") {
                                                                mcpConnectorSettingsModel.openExperimentalRemoteTunnelDocumentation()
                                                            }
                                                            .controlSize(.small)
                                                        }
                                                    }
                                                }

                                                if experimentalRemoteHasPendingPortChange {
                                                    advancedMessageBlock(
                                                        "Apply the local port change first. Then launch ngrok so it forwards to the same port."
                                                    )
                                                }
                                            }
                                        }

                                        if !mcpConnectorSettingsModel.experimentalRemoteShouldShowInlinePublicBaseURL {
                                            advancedDetailPane(label: "Tunnel URL") {
                                                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                                    TextField(
                                                        "https://your-ngrok-domain.ngrok-free.dev",
                                                        text: binding(
                                                            get: { experimentalRemotePublicBaseURLDraft },
                                                            set: {
                                                                experimentalRemotePublicBaseURLDraft = $0
                                                                experimentalRemotePublicBaseURLValidationMessage = nil
                                                            }
                                                        )
                                                    )
                                                    .textFieldStyle(.roundedBorder)
                                                    .font(PrimitiveTokens.Typography.code)
                                                    .onSubmit {
                                                        commitExperimentalRemotePublicBaseURLDraft()
                                                    }

                                                    advancedMessageBlock(
                                                        "Paste the `https://` base URL ngrok shows for this Mac. Leave off `/mcp`."
                                                    )

                                                    if let validationMessage = experimentalRemotePublicBaseURLValidationMessage {
                                                        advancedMessageBlock(validationMessage)
                                                    }

                                                    if experimentalRemoteHasPendingPublicBaseURLChange {
                                                        Button("Apply") {
                                                            commitExperimentalRemotePublicBaseURLDraft()
                                                        }
                                                        .controlSize(.small)
                                                    }
                                                }
                                            }
                                        }

                                        if let publicEndpoint = mcpConnectorSettingsModel.experimentalRemotePublicEndpoint,
                                           !mcpConnectorSettingsModel.experimentalRemoteShouldShowInlineChatGPTMCPURL {
                                            advancedDetailPane(label: "ChatGPT MCP URL") {
                                                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                                    advancedValueBlock(publicEndpoint, emphasized: true)
                                                    advancedMessageBlock(
                                                        "Paste this into ChatGPT when you create or recreate the Backtick app."
                                                    )
                                                    Button(didCopyExperimentalRemotePublicEndpoint ? "Copied" : "Copy ChatGPT MCP URL") {
                                                        mcpConnectorSettingsModel.copyExperimentalRemotePublicEndpoint()
                                                        showExperimentalRemotePublicEndpointCopiedFeedback()
                                                    }
                                                    .controlSize(.small)
                                                }
                                            }
                                        }

                                        advancedDetailPane(label: "Local Endpoint") {
                                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                                advancedValueBlock(
                                                    mcpConnectorSettingsModel.experimentalRemoteLocalEndpoint,
                                                    emphasized: true
                                                )
                                                advancedMessageBlock(
                                                    "Your tunnel or reverse proxy should forward to this local endpoint."
                                                )
                                                Button(didCopyExperimentalRemoteEndpoint ? "Copied" : "Copy Endpoint") {
                                                    mcpConnectorSettingsModel.copyExperimentalRemoteEndpoint()
                                                    showExperimentalRemoteEndpointCopiedFeedback()
                                                }
                                                .controlSize(.small)
                                            }
                                        }

                                        advancedDetailPane(label: "Port") {
                                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                                HStack(spacing: PrimitiveTokens.Space.xs) {
                                                    TextField(
                                                        "8321",
                                                        text: binding(
                                                            get: { experimentalRemotePortDraft },
                                                            set: { experimentalRemotePortDraft = $0 }
                                                        )
                                                    )
                                                    .textFieldStyle(.roundedBorder)
                                                    .frame(width: 92)
                                                    .onSubmit {
                                                        commitExperimentalRemotePortDraft()
                                                    }

                                                    if experimentalRemoteHasPendingPortChange {
                                                        Button("Apply") {
                                                            commitExperimentalRemotePortDraft()
                                                        }
                                                        .controlSize(.small)
                                                    }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                                advancedMessageBlock(
                                                    "If you change the local port, apply it before launching ngrok. Both Backtick and ngrok must use the same port."
                                                )
                                            }
                                        }

                                        if mcpConnectorSettingsModel.experimentalRemoteSettings.authMode == .apiKey {
                                            advancedDetailPane(label: "Auth Token") {
                                                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                                    TextField(
                                                        "Required",
                                                        text: binding(
                                                            get: { experimentalRemoteAPIKeyDraft },
                                                            set: { experimentalRemoteAPIKeyDraft = $0 }
                                                        )
                                                    )
                                                    .textFieldStyle(.roundedBorder)
                                                    .font(PrimitiveTokens.Typography.code)
                                                    .onSubmit {
                                                        commitExperimentalRemoteAPIKeyDraft()
                                                    }

                                                    advancedMessageBlock(
                                                        "Use this as the Bearer token for your public connector."
                                                    )

                                                    HStack(spacing: PrimitiveTokens.Space.xs) {
                                                        Button("Apply") {
                                                            commitExperimentalRemoteAPIKeyDraft()
                                                        }
                                                        .controlSize(.small)

                                                        Button("Generate") {
                                                            mcpConnectorSettingsModel.generateExperimentalRemoteAPIKey()
                                                            didCopyExperimentalRemoteAPIKey = false
                                                        }
                                                        .controlSize(.small)

                                                        Button(didCopyExperimentalRemoteAPIKey ? "Copied" : "Copy Token") {
                                                            mcpConnectorSettingsModel.copyExperimentalRemoteAPIKey()
                                                            showExperimentalRemoteAPIKeyCopiedFeedback()
                                                        }
                                                        .controlSize(.small)
                                                    }
                                                }
                                            }
                                        }
                                }
                                .padding(.top, PrimitiveTokens.Space.xs)
                            }
                        }
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
        SettingsConnectorClientRow(
            title: client.client.title,
            detail: focusedConnectorDetail(for: client),
            showsDivider: showsDivider,
            statusTitle: shouldShowConnectorStatusBadge(for: client)
                ? connectorStatusTitle(for: client)
                : nil,
            statusTone: shouldShowConnectorStatusBadge(for: client)
                ? connectorStatusBadgeTone(for: client)
                : nil
        ) {
            connectorClientBadge(
                for: client.client,
                tone: connectorStatusTone(for: client)
            )
        } accessory: {
            focusedConnectorAccessory(for: client)
        } footer: {
            if shouldShowInlineSetup(for: client)
                || shouldShowRepairBlock(for: client)
                || shouldShowConnectedTools(for: client) {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                    if shouldShowInlineSetup(for: client) {
                        connectorInlinePanel {
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
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
                                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                        Text(manualSetupDestinationSummary(for: client))
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

                                            if client.projectConfig != nil {
                                                Button(projectConfigButtonTitle(for: client.client)) {
                                                    mcpConnectorSettingsModel.openProjectConfig(for: client.client)
                                                }
                                                .controlSize(.small)
                                            }

                                            Button(homeConfigButtonTitle(for: client.client)) {
                                                mcpConnectorSettingsModel.openHomeConfig(for: client.client)
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
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                Text("\(client.client.title) needs one repair before Backtick can respond again.")
                                    .font(PrimitiveTokens.Typography.metaStrong)
                                    .foregroundStyle(ConnectorChipTone.danger.foreground)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let failureDetail = mcpConnectorSettingsModel.clientFailureDetail(for: client) {
                                    advancedMessageBlock(failureDetail)
                                }

                                HStack(spacing: PrimitiveTokens.Space.xs) {
                                    Button("Verify Again") {
                                        mcpConnectorSettingsModel.runServerTest(for: client.client)
                                    }
                                    .controlSize(.small)
                                    .disabled(mcpConnectorSettingsModel.verificationState(for: client).isRunning)

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
                            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                                Text("\(mcpConnectorSettingsModel.connectedToolNames(for: client).count) tools are ready in \(client.client.title).")
                                    .font(PrimitiveTokens.Typography.metaStrong)
                                    .foregroundStyle(SemanticTokens.Text.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                connectorToolGrid(toolNames: mcpConnectorSettingsModel.connectedToolNames(for: client))
                            }
                        }
                    }
                }
            }
        }
    }

    private func focusedConnectorDetail(for client: MCPConnectorClientStatus) -> String {
        if !mcpConnectorSettingsModel.isServerAvailable {
            return "Restart Backtick, then verify again."
        }

        if !client.isClientAvailable {
            return "Install \(client.client.title) on this Mac."
        }

        if !client.hasConfiguredScope {
            if client.client.usesDirectConfig {
                return "Click Connect to set up \(client.client.title)."
            }

            return "Add Backtick to \(client.client.title) to connect it."
        }

        switch mcpConnectorSettingsModel.verificationState(for: client) {
        case .idle:
            if client.client.usesDirectConfig {
                return "Config saved. Restart \(client.client.title), then ask: \"List my Backtick notes\""
            }

            return "Backtick is configured and ready to verify."
        case .running:
            return "Checking the connection now."
        case .passed(let report):
            return "\(report.toolNames.count) tools are ready in \(client.client.title)."
        case .failed:
            return "Connected, but the last verification failed."
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
            case .writeConfig:
                Button("Connect") {
                    mcpConnectorSettingsModel.writeDirectConfig(for: client.client)
                }
            case .launchTerminalSetup:
                Button("Connect") {
                    _ = mcpConnectorSettingsModel.launchAddCommandInTerminal(for: client.client)
                    expandedSetupClient = client.client
                    expandedManualSetupClient = nil
                    expandedToolsClient = nil
                    didCopySetupCommand = false
                }
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
                    mcpConnectorSettingsModel.runServerTest(for: client.client)
                }
                .disabled(mcpConnectorSettingsModel.verificationState(for: client).isRunning)
            case nil:
                if case .passed = mcpConnectorSettingsModel.verificationState(for: client),
                   client.hasConfiguredScope {
                    Button(
                        isToolsExpanded(for: client)
                            ? "Hide Tools"
                            : "Show Tools"
                    ) {
                        expandedToolsClient = isToolsExpanded(for: client) ? nil : client.client
                    }
                    .controlSize(.small)
                } else {
                    EmptyView()
                }
            }
        }
    }

    private func repairActionTitle(for client: MCPConnectorClientStatus) -> String {
        if case .failed = mcpConnectorSettingsModel.verificationState(for: client) {
            return "Fix"
        }

        return "Verify"
    }

    private func connectorStatusTone(for client: MCPConnectorClientStatus) -> ConnectorChipTone {
        if !mcpConnectorSettingsModel.isServerAvailable {
            return .warning
        }

        if !client.isClientAvailable {
            return .warning
        }

        guard client.hasConfiguredScope else {
            return .accent
        }

        switch mcpConnectorSettingsModel.verificationState(for: client) {
        case .passed:
            return .success
        case .failed:
            return .danger
        case .idle, .running:
            return .accent
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

    private func connectorStatusTitle(for client: MCPConnectorClientStatus) -> String {
        if !mcpConnectorSettingsModel.isServerAvailable {
            return "Restart"
        }

        if !client.isClientAvailable {
            return "Install"
        }

        if !client.hasConfiguredScope {
            return "Setup Needed"
        }

        switch mcpConnectorSettingsModel.verificationState(for: client) {
        case .idle:
            return "Ready to Verify"
        case .running:
            return "Checking"
        case .passed:
            return "Connected"
        case .failed:
            return "Needs Repair"
        }
    }

    private func shouldShowConnectorStatusBadge(for client: MCPConnectorClientStatus) -> Bool {
        client.hasConfiguredScope || !client.isClientAvailable || !mcpConnectorSettingsModel.isServerAvailable
    }

    private func connectorStatusBadgeTone(for client: MCPConnectorClientStatus) -> SettingsStatusBadge.Tone {
        if !mcpConnectorSettingsModel.isServerAvailable {
            return .warning
        }

        if !client.isClientAvailable {
            return .warning
        }

        if !client.hasConfiguredScope {
            return .accent
        }

        switch mcpConnectorSettingsModel.verificationState(for: client) {
        case .idle, .running:
            return .accent
        case .passed:
            return .success
        case .failed:
            return .danger
        }
    }

    private func configuredSetupPrompt(for client: MCPConnectorClientStatus) -> String {
        switch client.client {
        case .claudeCode:
            return "Connect opens Terminal and runs the global Claude Code setup command. If Terminal did not open, run this command manually, or use Config File Instead for ~/.claude.json."
        case .codex:
            return "Connect opens Terminal and runs the Codex setup command. If Terminal did not open, run this command manually, or use Config File Instead for ~/.codex/config.toml."
        case .claudeDesktop:
            break
        }

        if client.hasOtherConfigFiles {
            return "Run this in Terminal and \(client.client.title) will pick up Backtick from the existing config."
        }

        return "Copy this command, paste it into Terminal, and press Return."
    }

    private func manualSetupDestinationSummary(for client: MCPConnectorClientStatus) -> String {
        switch client.client {
        case .claudeDesktop:
            return "Backtick writes this config automatically. Edit only if you need to customize."

        case .claudeCode:
            if client.projectConfig != nil {
                return "Paste this into ~/.claude.json for global use, or .mcp.json in this project for project-only use."
            }

            return "Paste this into ~/.claude.json for global use."

        case .codex:
            if client.projectConfig != nil {
                return "Paste this into ~/.codex/config.toml for global use, or .codex/config.toml in this project for project-only use."
            }

            return "Paste this into ~/.codex/config.toml for global use."
        }
    }

    private func projectConfigButtonTitle(for client: MCPConnectorClient) -> String {
        switch client {
        case .claudeDesktop:
            // Claude Desktop has no project config (projectConfigRelativePath is nil),
            // so this case is unreachable in practice.
            return "Open Config"
        case .claudeCode:
            return "Open .mcp.json"
        case .codex:
            return "Open Project Config"
        }
    }

    private func homeConfigButtonTitle(for client: MCPConnectorClient) -> String {
        switch client {
        case .claudeDesktop:
            return "Open claude_desktop_config.json"
        case .claudeCode:
            return "Open ~/.claude.json"
        case .codex:
            return "Open ~/.codex/config.toml"
        }
    }

    private func shouldShowInlineSetup(for client: MCPConnectorClientStatus) -> Bool {
        if client.client.usesDirectConfig {
            return false
        }

        guard client.hasDetectedCLI, !client.hasConfiguredScope else {
            return false
        }

        return expandedSetupClient == client.client
    }

    private func shouldShowRepairBlock(for client: MCPConnectorClientStatus) -> Bool {
        guard client.hasConfiguredScope else {
            return false
        }

        if case .failed = mcpConnectorSettingsModel.verificationState(for: client) {
            return true
        }

        return false
    }

    private func shouldShowConnectedTools(for client: MCPConnectorClientStatus) -> Bool {
        guard client.hasConfiguredScope else {
            return false
        }

        guard case .passed = mcpConnectorSettingsModel.verificationState(for: client) else {
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
        SettingsInlinePanel {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                content()
            }
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
        SettingsSection(title: client.client.title) {
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
        SettingsSection(
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
                                    && mcpConnectorSettingsModel.verificationState(for: client).isRunning
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
                        if client.isClientAvailable {
                            Button(mcpConnectorSettingsModel.configButtonTitle(for: client)) {
                                mcpConnectorSettingsModel.revealPreferredConfig(for: client.client)
                            }
                            .controlSize(.small)
                        }

                        if mcpConnectorSettingsModel.verificationState(for: client).isRunning,
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

                                    if client.isClientAvailable {
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
        case .writeConfig:
            mcpConnectorSettingsModel.performPrimaryAction(action, for: client)
        case .launchTerminalSetup:
            _ = mcpConnectorSettingsModel.performPrimaryAction(action, for: client)
            expandedSetupClient = client.client
            expandedManualSetupClient = nil
            expandedToolsClient = nil
            didCopySetupCommand = false
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

                                Text("After you run it in Terminal, click Verify Connection below.")
                                    .font(PrimitiveTokens.Typography.meta)
                                    .foregroundStyle(SemanticTokens.Text.secondary)
                            }
                        }

                        if status.isClientAvailable || status.configSnippet != nil {
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

                    Button("Skip") {
                        setupGuideClient = nil
                    }
                    .controlSize(.small)
                    .buttonStyle(.plain)
                    .foregroundStyle(SemanticTokens.Text.secondary)

                    Button("Verify Connection") {
                        setupGuideClient = nil
                        mcpConnectorSettingsModel.runServerTest(for: client)
                    }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
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

                        if status.isClientAvailable {
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
        guard client.isClientAvailable else {
            return false
        }

        return client.projectConfig != nil || client.addCommand != nil || client.configSnippet != nil
    }

    private func troubleshootingVisible(for client: MCPConnectorClientStatus) -> Bool {
        if !client.isClientAvailable {
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
        ConnectorClientBadge(
            assetName: clientBadgeAssetName(for: client),
            fallbackSymbol: clientBadgeSymbol(for: client),
            statusColor: connectorStatusDotColor(for: tone)
        )
    }

    private func clientBadgeAssetName(for client: MCPConnectorClient) -> String? {
        switch client {
        case .claudeDesktop:
            return "ClaudeDesktopIcon"
        case .claudeCode:
            return "ClaudeDesktopIcon"
        case .codex:
            return "CodexIcon"
        }
    }

    private func clientBadgeSymbol(for client: MCPConnectorClient) -> String {
        switch client {
        case .claudeDesktop:
            return "message"
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

    private var screenshotStatusBadgeTone: SettingsStatusBadge.Tone {
        switch screenshotSettingsModel.accessState {
        case .notConfigured:
            return .neutral
        case .connected:
            return .success
        case .needsReconnect:
            return .warning
        }
    }

    private var cloudSyncStatusBadgeTone: SettingsStatusBadge.Tone {
        if cloudSyncSettingsModel.syncError != nil {
            return .warning
        }

        return cloudSyncSettingsModel.isSyncEnabled ? .success : .neutral
    }

    private var sectionDivider: some View {
        EmptyView()
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
                    .frame(width: SettingsTokens.Layout.advancedLabelColumnWidth, alignment: .leading)

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
            .font(SettingsTokens.Typography.supporting)
            .foregroundStyle(SettingsSemanticTokens.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var experimentalRemoteStatusTone: SettingsStatusBadge.Tone {
        switch mcpConnectorSettingsModel.experimentalRemoteStatusPresentation.tone {
        case .neutral:
            return .neutral
        case .accent:
            return .accent
        case .success:
            return .success
        case .warning:
            return .warning
        case .danger:
            return .danger
        }
    }

    private var shouldShowExperimentalRemoteStatusAction: Bool {
        guard let action = mcpConnectorSettingsModel.experimentalRemoteStatusPresentation.action else {
            return false
        }

        if action == .copyPublicMCPURL,
           mcpConnectorSettingsModel.experimentalRemoteShouldShowInlineChatGPTMCPURL {
            return false
        }

        return true
    }

    private var shouldShowExperimentalRemoteTunnelActions: Bool {
        guard let action = mcpConnectorSettingsModel.experimentalRemoteStatusPresentation.action else {
            return false
        }

        switch action {
        case .launchTunnel, .installTunnel:
            return true
        case .copyPublicMCPURL, .resetLocalState, .retry:
            return false
        }
    }

    private var experimentalRemoteSavedPortDraft: String {
        "\(mcpConnectorSettingsModel.experimentalRemoteSettings.port)"
    }

    private var experimentalRemoteHasPendingPortChange: Bool {
        experimentalRemotePortDraft.trimmingCharacters(in: .whitespacesAndNewlines) != experimentalRemoteSavedPortDraft
    }

    private var experimentalRemoteHasPendingPublicBaseURLChange: Bool {
        experimentalRemotePublicBaseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            != mcpConnectorSettingsModel.experimentalRemoteSettings.publicBaseURL
    }

    private func syncExperimentalRemoteDrafts(with settings: ExperimentalMCPHTTPSettings) {
        experimentalRemotePortDraft = "\(settings.port)"
        experimentalRemotePublicBaseURLDraft = settings.publicBaseURL
        experimentalRemoteAPIKeyDraft = settings.apiKey
        experimentalRemotePublicBaseURLValidationMessage = nil
    }

    private func commitExperimentalRemotePortDraft() {
        guard mcpConnectorSettingsModel.updateExperimentalRemotePort(experimentalRemotePortDraft) else {
            syncExperimentalRemoteDrafts(with: mcpConnectorSettingsModel.experimentalRemoteSettings)
            return
        }

        experimentalRemotePortDraft = "\(mcpConnectorSettingsModel.experimentalRemoteSettings.port)"
    }

    private func commitExperimentalRemotePublicBaseURLDraft() {
        guard mcpConnectorSettingsModel.updateExperimentalRemotePublicBaseURL(experimentalRemotePublicBaseURLDraft) else {
            experimentalRemotePublicBaseURLValidationMessage = "Use an `https://` base URL only. Leave off `/mcp` and any extra path."
            return
        }

        experimentalRemotePublicBaseURLValidationMessage = nil
        experimentalRemotePublicBaseURLDraft = mcpConnectorSettingsModel.experimentalRemoteSettings.publicBaseURL
    }

    private func commitExperimentalRemoteAPIKeyDraft() {
        guard mcpConnectorSettingsModel.updateExperimentalRemoteAPIKey(experimentalRemoteAPIKeyDraft) else {
            syncExperimentalRemoteDrafts(with: mcpConnectorSettingsModel.experimentalRemoteSettings)
            return
        }

        experimentalRemoteAPIKeyDraft = mcpConnectorSettingsModel.experimentalRemoteSettings.apiKey
    }

    private func showExperimentalRemoteEndpointCopiedFeedback() {
        didCopyExperimentalRemoteEndpoint = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            didCopyExperimentalRemoteEndpoint = false
        }
    }

    private func showExperimentalRemotePublicEndpointCopiedFeedback() {
        didCopyExperimentalRemotePublicEndpoint = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            didCopyExperimentalRemotePublicEndpoint = false
        }
    }

    private func showExperimentalRemoteAPIKeyCopiedFeedback() {
        didCopyExperimentalRemoteAPIKey = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            didCopyExperimentalRemoteAPIKey = false
        }
    }

    private func showExperimentalRemoteTunnelCommandCopiedFeedback() {
        didCopyExperimentalRemoteTunnelCommand = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            didCopyExperimentalRemoteTunnelCommand = false
        }
    }

    private func binding<Value>(
        get: @escaping @MainActor () -> Value,
        set: @escaping @MainActor (Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: {
                MainActor.assumeIsolated {
                    get()
                }
            },
            set: { value in
                MainActor.assumeIsolated {
                    set(value)
                }
            }
        )
    }
}

private struct SettingsConnectorClientRow<Badge: View, Accessory: View, Footer: View>: View {
    let title: String
    let detail: String
    let showsDivider: Bool
    let statusTitle: String?
    let statusTone: SettingsStatusBadge.Tone?
    private let badge: Badge
    private let accessory: Accessory
    private let footer: Footer?

    init(
        title: String,
        detail: String,
        showsDivider: Bool = true,
        statusTitle: String? = nil,
        statusTone: SettingsStatusBadge.Tone? = nil,
        @ViewBuilder badge: () -> Badge,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder footer: () -> Footer? = { nil }
    ) {
        self.title = title
        self.detail = detail
        self.showsDivider = showsDivider
        self.statusTitle = statusTitle
        self.statusTone = statusTone
        self.badge = badge()
        self.accessory = accessory()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
            HStack(alignment: .center, spacing: PrimitiveTokens.Space.xs) {
                badge

                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxxs) {
                    HStack(alignment: .center, spacing: PrimitiveTokens.Space.xxs) {
                        Text(title)
                            .font(PrimitiveTokens.Typography.bodyStrong)
                            .foregroundStyle(SemanticTokens.Text.primary)

                        if let statusTitle, let statusTone {
                            SettingsStatusBadge(
                                title: statusTitle,
                                tone: statusTone
                            )
                        }
                    }

                    Text(detail)
                        .font(PrimitiveTokens.Typography.body)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: PrimitiveTokens.Space.xs)

                accessory
            }

            if let footer {
                footer
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsDivider {
                Rectangle()
                    .fill(SettingsSemanticTokens.Border.rowSeparator)
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, SettingsTokens.Layout.groupInset)
        .padding(.vertical, PrimitiveTokens.Space.xs)
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
