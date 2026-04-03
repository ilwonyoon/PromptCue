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
    private struct ScreenshotFolderReadinessPrompt {
        let title: String
        let message: String
        let confirmTitle: String
    }

    private var window: NSWindow?
    private let screenshotSettingsModel: ScreenshotSettingsModel
    private let launchAtLoginSettingsModel: LaunchAtLoginSettingsModel
    private let exportTailSettingsModel: PromptExportTailSettingsModel
    private let retentionSettingsModel: CardRetentionSettingsModel
    private let cloudSyncSettingsModel: CloudSyncSettingsModel
    private let mcpConnectorSettingsModel: MCPConnectorSettingsModel
    private let navigationModel = SettingsNavigationModel()
    init(
        screenshotSettingsModel: ScreenshotSettingsModel,
        launchAtLoginSettingsModel: LaunchAtLoginSettingsModel,
        exportTailSettingsModel: PromptExportTailSettingsModel,
        retentionSettingsModel: CardRetentionSettingsModel,
        cloudSyncSettingsModel: CloudSyncSettingsModel,
        mcpConnectorSettingsModel: MCPConnectorSettingsModel
    ) {
        self.screenshotSettingsModel = screenshotSettingsModel
        self.launchAtLoginSettingsModel = launchAtLoginSettingsModel
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

    func promptForScreenshotFolderReadiness(completion: @escaping (Bool) -> Void) {
        let window = window ?? makeWindow()
        if navigationModel.selectedTab != .capture {
            navigationModel.selectedTab = .capture
        }
        refreshModels()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)

        let requirement = screenshotSettingsModel.captureReadinessRequirement
        guard requirement != .none else {
            completion(true)
            return
        }

        let prompt = screenshotFolderReadinessPrompt(for: requirement)
        presentScreenshotFolderReadinessPrompt(prompt, on: window) { [weak self] didConfirm in
            guard let self else {
                completion(false)
                return
            }
            guard didConfirm else {
                completion(false)
                return
            }

            switch requirement {
            case .none:
                completion(true)
            case .chooseFolder:
                self.screenshotSettingsModel.chooseFolder(
                    message: "Choose the folder Backtick should watch for recent screenshots before capture opens.",
                    attachedTo: window,
                    completion: completion
                )
            case .reconnect:
                self.screenshotSettingsModel.chooseFolder(
                    message: "Backtick needs you to approve your screenshot folder again before capture can auto-attach screenshots.",
                    attachedTo: window,
                    completion: completion
                )
            case .chooseCurrentSystemFolder:
                let currentSystemDirectoryURL = ScreenshotDirectoryResolver.resolvedSystemScreenshotDirectory()
                let currentSystemPath = self.screenshotSettingsModel.suggestedSystemPath ?? "the current macOS screenshot folder"
                self.screenshotSettingsModel.chooseFolder(
                    message: "macOS is currently saving screenshots to \(currentSystemPath). Choose that folder to keep auto-attach working.",
                    initialDirectoryURL: currentSystemDirectoryURL,
                    attachedTo: window,
                    completion: completion
                )
            }
        }
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
        launchAtLoginSettingsModel.refresh()
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

    private func screenshotFolderReadinessPrompt(
        for requirement: ScreenshotSettingsModel.CaptureReadinessRequirement
    ) -> ScreenshotFolderReadinessPrompt {
        switch requirement {
        case .none:
            return ScreenshotFolderReadinessPrompt(
                title: "",
                message: "",
                confirmTitle: ""
            )
        case .chooseFolder:
            return ScreenshotFolderReadinessPrompt(
                title: "Choose a Screenshot Folder",
                message: "Backtick needs access to the folder where macOS saves screenshots before Capture can open.",
                confirmTitle: "Choose Folder…"
            )
        case .reconnect:
            return ScreenshotFolderReadinessPrompt(
                title: "Reconnect Screenshot Folder",
                message: "Backtick remembers your screenshot folder, but macOS needs you to approve it again before Capture can auto-attach screenshots.",
                confirmTitle: "Reconnect…"
            )
        case .chooseCurrentSystemFolder:
            let currentSystemPath = screenshotSettingsModel.suggestedSystemPath ?? "the current macOS screenshot folder"
            return ScreenshotFolderReadinessPrompt(
                title: "Use Current Screenshot Folder",
                message: "macOS is currently saving screenshots to \(currentSystemPath). Backtick needs you to choose that folder before Capture can open.",
                confirmTitle: "Use Current Folder…"
            )
        }
    }

    private func presentScreenshotFolderReadinessPrompt(
        _ prompt: ScreenshotFolderReadinessPrompt,
        on window: NSWindow,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        alert.addButton(withTitle: prompt.confirmTitle)
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }

    private func makeRootView() -> PromptCueSettingsView {
        PromptCueSettingsView(
            selectedTab: navigationModel.selectedTab,
            navigationModel: navigationModel,
            onSelectTab: { [weak self] tab in
                self?.switchTab(tab)
            },
            screenshotSettingsModel: screenshotSettingsModel,
            launchAtLoginSettingsModel: launchAtLoginSettingsModel,
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
