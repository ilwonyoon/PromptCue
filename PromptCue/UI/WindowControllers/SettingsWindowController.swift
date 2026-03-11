import AppKit
import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case general = 0
    case capture = 1
    case stack = 2

    var title: String {
        switch self {
        case .general:
            return "General"
        case .capture:
            return "Capture"
        case .stack:
            return "Stack"
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
        }
    }

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("settings.\(title.lowercased())")
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let screenshotSettingsModel: ScreenshotSettingsModel
    private let exportTailSettingsModel: PromptExportTailSettingsModel
    private let retentionSettingsModel: CardRetentionSettingsModel
    private let cloudSyncSettingsModel: CloudSyncSettingsModel
    private let appearanceSettingsModel: AppearanceSettingsModel
    private var selectedTab: SettingsTab = .general

    init(
        screenshotSettingsModel: ScreenshotSettingsModel,
        exportTailSettingsModel: PromptExportTailSettingsModel,
        retentionSettingsModel: CardRetentionSettingsModel,
        cloudSyncSettingsModel: CloudSyncSettingsModel,
        appearanceSettingsModel: AppearanceSettingsModel
    ) {
        self.screenshotSettingsModel = screenshotSettingsModel
        self.exportTailSettingsModel = exportTailSettingsModel
        self.retentionSettingsModel = retentionSettingsModel
        self.cloudSyncSettingsModel = cloudSyncSettingsModel
        self.appearanceSettingsModel = appearanceSettingsModel
        super.init()
    }

    func show() {
        let window = window ?? makeWindow()
        refreshModels()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshModels() {
        screenshotSettingsModel.refresh()
        exportTailSettingsModel.refresh()
        retentionSettingsModel.refresh()
        cloudSyncSettingsModel.refresh()
        appearanceSettingsModel.refresh()
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

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        toolbar.selectedItemIdentifier = selectedTab.toolbarIdentifier

        updateContent(for: window)

        self.window = window
        return window
    }

    private func updateContent(for window: NSWindow) {
        window.contentViewController = NSHostingController(
            rootView: PromptCueSettingsView(
                selectedTab: selectedTab,
                screenshotSettingsModel: screenshotSettingsModel,
                exportTailSettingsModel: exportTailSettingsModel,
                retentionSettingsModel: retentionSettingsModel,
                cloudSyncSettingsModel: cloudSyncSettingsModel,
                appearanceSettingsModel: appearanceSettingsModel
            )
        )
    }

    private func switchTab(_ tab: SettingsTab) {
        guard tab != selectedTab, let window else {
            return
        }

        selectedTab = tab
        updateContent(for: window)
        window.toolbar?.selectedItemIdentifier = selectedTab.toolbarIdentifier
    }

    @objc private func toolbarItemTapped(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab.allCases.first(where: { $0.toolbarIdentifier == sender.itemIdentifier }) else {
            return
        }

        switchTab(tab)
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
        guard let tab = SettingsTab.allCases.first(where: { $0.toolbarIdentifier == itemIdentifier }) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(toolbarItemTapped(_:))
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }
}
