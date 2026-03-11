import AppKit
import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case general = 0
    case capture = 1
    case stack = 2
    case connectors = 3

    var title: String {
        switch self {
        case .general:
            return "General"
        case .capture:
            return "Capture"
        case .stack:
            return "Stack"
        case .connectors:
            return "Connectors"
        }
    }

    var iconName: String {
        switch self {
        case .general:
            return "gearshape"
        case .capture:
            return "rectangle.and.pencil.and.ellipsis"
        case .stack:
            return "square.stack.3d.up"
        case .connectors:
            return "link"
        }
    }
}

private enum SettingsToolbarIdentifiers {
    static let tabs = NSToolbarItem.Identifier("settings.tabs")
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let screenshotSettingsModel: ScreenshotSettingsModel
    private let exportTailSettingsModel: PromptExportTailSettingsModel
    private let retentionSettingsModel: CardRetentionSettingsModel
    private let cloudSyncSettingsModel: CloudSyncSettingsModel
    private let appearanceSettingsModel: AppearanceSettingsModel
    private let mcpConnectorSettingsModel: MCPConnectorSettingsModel
    private var selectedTab: SettingsTab = .general
    private var toolbarTabsHostingView: NSHostingView<SettingsToolbarTabsView>?

    init(
        screenshotSettingsModel: ScreenshotSettingsModel,
        exportTailSettingsModel: PromptExportTailSettingsModel,
        retentionSettingsModel: CardRetentionSettingsModel,
        cloudSyncSettingsModel: CloudSyncSettingsModel,
        appearanceSettingsModel: AppearanceSettingsModel,
        mcpConnectorSettingsModel: MCPConnectorSettingsModel
    ) {
        self.screenshotSettingsModel = screenshotSettingsModel
        self.exportTailSettingsModel = exportTailSettingsModel
        self.retentionSettingsModel = retentionSettingsModel
        self.cloudSyncSettingsModel = cloudSyncSettingsModel
        self.appearanceSettingsModel = appearanceSettingsModel
        self.mcpConnectorSettingsModel = mcpConnectorSettingsModel
        super.init()
    }

    func show() {
        let window = window ?? makeWindow()
        refreshModels()
        refreshToolbarTabsView()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        window?.appearance = appearance
        window?.invalidateShadow()
        window?.contentView?.needsDisplay = true
        window?.contentView?.subviews.forEach { $0.needsDisplay = true }
        toolbarTabsHostingView?.appearance = appearance
        toolbarTabsHostingView?.needsDisplay = true
    }

    private func refreshModels() {
        screenshotSettingsModel.refresh()
        exportTailSettingsModel.refresh()
        retentionSettingsModel.refresh()
        cloudSyncSettingsModel.refresh()
        appearanceSettingsModel.refresh()
        mcpConnectorSettingsModel.refresh()
    }

    private func makeWindow() -> NSWindow {
        let frame = NSRect(
            x: 0,
            y: 0,
            width: PanelMetrics.settingsPanelWidth,
            height: PanelMetrics.settingsPanelHeight
        )

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Backtick Settings"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.minSize = NSSize(
            width: PanelMetrics.settingsPanelWidth,
            height: PanelMetrics.settingsPanelHeight
        )
        window.delegate = self
        window.toolbar = makeToolbar()
        window.toolbarStyle = .preference

        updateContent(for: window)

        self.window = window
        return window
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .default
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifier = SettingsToolbarIdentifiers.tabs
        return toolbar
    }

    private func updateContent(for window: NSWindow) {
        window.contentViewController = NSHostingController(
            rootView: PromptCueSettingsView(
                selectedTab: selectedTab,
                screenshotSettingsModel: screenshotSettingsModel,
                exportTailSettingsModel: exportTailSettingsModel,
                retentionSettingsModel: retentionSettingsModel,
                cloudSyncSettingsModel: cloudSyncSettingsModel,
                appearanceSettingsModel: appearanceSettingsModel,
                mcpConnectorSettingsModel: mcpConnectorSettingsModel
            )
        )
    }

    private func refreshToolbarTabsView() {
        let rootView = SettingsToolbarTabsView(selectedTab: selectedTab) { [weak self] tab in
            self?.switchTab(tab)
        }

        if let toolbarTabsHostingView {
            toolbarTabsHostingView.rootView = rootView
            toolbarTabsHostingView.invalidateIntrinsicContentSize()
            toolbarTabsHostingView.needsLayout = true
            return
        }

        toolbarTabsHostingView = NSHostingView(rootView: rootView)
        toolbarTabsHostingView?.translatesAutoresizingMaskIntoConstraints = false
    }

    private func switchTab(_ tab: SettingsTab) {
        guard tab != selectedTab, let window else {
            return
        }

        selectedTab = tab
        updateContent(for: window)
        refreshToolbarTabsView()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else {
            return
        }

        window.orderOut(nil)
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == SettingsToolbarIdentifiers.tabs else {
            return nil
        }

        refreshToolbarTabsView()
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = ""
        item.paletteLabel = "Settings Tabs"
        if let toolbarTabsHostingView {
            item.view = toolbarTabsHostingView
            let size = toolbarTabsHostingView.fittingSize
            item.minSize = size
            item.maxSize = size
        }
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [SettingsToolbarIdentifiers.tabs]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [SettingsToolbarIdentifiers.tabs]
    }
}

private struct SettingsToolbarTabsView: View {
    let selectedTab: SettingsTab
    let onSelect: (SettingsTab) -> Void

    var body: some View {
        HStack(spacing: PrimitiveTokens.Space.xs) {
            ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, PrimitiveTokens.Space.xxs)
        .padding(.vertical, PrimitiveTokens.Space.xxxs)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        Button {
            onSelect(tab)
        } label: {
            tabLabel(tab)
        }
        .buttonStyle(.plain)
    }

    private func tabLabel(_ tab: SettingsTab) -> some View {
        VStack(spacing: PrimitiveTokens.Space.xxxs) {
            Image(systemName: tab.iconName)
                .font(.system(size: 15, weight: .semibold))
            Text(tab.title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tabForegroundStyle(for: tab))
        .frame(width: PanelMetrics.settingsToolbarTabWidth)
        .frame(minHeight: PanelMetrics.settingsToolbarTabHeight)
        .padding(.vertical, PrimitiveTokens.Space.xxs)
        .contentShape(
            RoundedRectangle(
                cornerRadius: PrimitiveTokens.Radius.sm,
                style: .continuous
            )
        )
        .background(tabBackground(tab))
    }

    private func tabForegroundStyle(for tab: SettingsTab) -> Color {
        tab == selectedTab ? SemanticTokens.Accent.primary : SemanticTokens.Text.secondary
    }

    @ViewBuilder
    private func tabBackground(_ tab: SettingsTab) -> some View {
        RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
            .fill(tab == selectedTab ? SemanticTokens.Accent.selection.opacity(0.18) : Color.clear)
    }
}
