import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let screenshotSettingsModel: ScreenshotSettingsModel
    private let exportTailSettingsModel: PromptExportTailSettingsModel
    private let retentionSettingsModel: CardRetentionSettingsModel

    init(
        screenshotSettingsModel: ScreenshotSettingsModel,
        exportTailSettingsModel: PromptExportTailSettingsModel,
        retentionSettingsModel: CardRetentionSettingsModel
    ) {
        self.screenshotSettingsModel = screenshotSettingsModel
        self.exportTailSettingsModel = exportTailSettingsModel
        self.retentionSettingsModel = retentionSettingsModel
        super.init()
    }

    func show() {
        let window = window ?? makeWindow()
        screenshotSettingsModel.refresh()
        exportTailSettingsModel.refresh()
        retentionSettingsModel.refresh()
        window.setContentSize(
            NSSize(
                width: PanelMetrics.settingsPanelWidth,
                height: PanelMetrics.settingsPanelHeight
            )
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.minSize = NSSize(
            width: PanelMetrics.settingsPanelWidth,
            height: PanelMetrics.settingsPanelHeight
        )
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: PromptCueSettingsView(
                screenshotSettingsModel: screenshotSettingsModel,
                exportTailSettingsModel: exportTailSettingsModel,
                retentionSettingsModel: retentionSettingsModel
            )
        )

        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else {
            return
        }

        window.orderOut(nil)
    }
}
