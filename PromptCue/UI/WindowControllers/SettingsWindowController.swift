import AppKit
import SwiftUI

enum SettingsTab: Int, CaseIterable, Hashable {
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

    var sidebarIcon: SettingsSidebarIcon {
        switch self {
        case .general:
            return .system("gearshape.fill")
        case .capture:
            return .system("rectangle.dashed")
        case .stack:
            return .system("square.stack.3d.up.fill")
        case .connectors:
            return .system("link")
        }
    }

    var sidebarIconColor: Color {
        switch self {
        case .general:
            return Color(nsColor: .systemGray)
        case .capture:
            return Color(nsColor: .systemPurple)
        case .stack:
            return Color(nsColor: .systemOrange)
        case .connectors:
            return Color(nsColor: .systemBlue)
        }
    }

    var subtitle: String? {
        switch self {
        case .general:
            return "Shortcuts and sync."
        case .capture:
            return "Screenshot access and capture behavior."
        case .stack:
            return "Retention and export defaults."
        case .connectors:
            return "Connect Claude Desktop, Claude Code, and Codex to Backtick."
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let screenshotSettingsModel: ScreenshotSettingsModel
    private let exportTailSettingsModel: PromptExportTailSettingsModel
    private let retentionSettingsModel: CardRetentionSettingsModel
    private let cloudSyncSettingsModel: CloudSyncSettingsModel
    private let mcpConnectorSettingsModel: MCPConnectorSettingsModel
    private let navigationModel = SettingsNavigationModel()
    init(
        screenshotSettingsModel: ScreenshotSettingsModel,
        exportTailSettingsModel: PromptExportTailSettingsModel,
        retentionSettingsModel: CardRetentionSettingsModel,
        cloudSyncSettingsModel: CloudSyncSettingsModel,
        mcpConnectorSettingsModel: MCPConnectorSettingsModel
    ) {
        self.screenshotSettingsModel = screenshotSettingsModel
        self.exportTailSettingsModel = exportTailSettingsModel
        self.retentionSettingsModel = retentionSettingsModel
        self.cloudSyncSettingsModel = cloudSyncSettingsModel
        self.mcpConnectorSettingsModel = mcpConnectorSettingsModel
        super.init()
    }

    func show(selectedTab preferredTab: SettingsTab? = nil) {
        let window = window ?? makeWindow()
        if let preferredTab,
           preferredTab != navigationModel.selectedTab {
            navigationModel.selectedTab = preferredTab
        }
        refreshModels()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshForInheritedAppearanceChange() {
        guard let window else {
            return
        }

        window.appearance = nil
        window.contentView?.appearance = nil
        window.contentViewController?.view.appearance = nil
        window.invalidateShadow()
        window.contentView?.needsDisplay = true
        window.contentViewController?.view.layer?.contents = nil
        window.contentViewController?.view.needsLayout = true
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.contentViewController?.view.needsDisplay = true
    }

    private func refreshModels() {
        screenshotSettingsModel.refresh()
        exportTailSettingsModel.refresh()
        retentionSettingsModel.refresh()
        cloudSyncSettingsModel.refresh()
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
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Backtick Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titlebarSeparatorStyle = .none
        window.center()
        window.minSize = NSSize(
            width: PanelMetrics.settingsPanelWidth,
            height: PanelMetrics.settingsPanelHeight
        )
        window.delegate = self

        window.contentViewController = NSHostingController(
            rootView: makeRootView()
        )

        self.window = window
        return window
    }

    private func makeRootView() -> PromptCueSettingsView {
        PromptCueSettingsView(
            selectedTab: navigationModel.selectedTab,
            navigationModel: navigationModel,
            onSelectTab: { [weak self] tab in
                self?.switchTab(tab)
            },
            screenshotSettingsModel: screenshotSettingsModel,
            exportTailSettingsModel: exportTailSettingsModel,
            retentionSettingsModel: retentionSettingsModel,
            cloudSyncSettingsModel: cloudSyncSettingsModel,
            mcpConnectorSettingsModel: mcpConnectorSettingsModel
        )
    }

    private func switchTab(_ tab: SettingsTab) {
        guard tab != navigationModel.selectedTab else {
            return
        }

        navigationModel.selectedTab = tab
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else {
            return
        }

        window.orderOut(nil)
    }
}
