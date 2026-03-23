import AppKit
import SwiftUI

@MainActor
final class MemoryWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private enum ToolbarItemIdentifier {
        static let refresh = NSToolbarItem.Identifier("BacktickMemoryRefresh")
    }

    private var window: NSWindow?
    private let model: MemoryViewerModel
    private let uiState = MemoryViewerUIState()

    var isVisible: Bool {
        window?.isVisible == true
    }

    var isFrontmost: Bool {
        guard let window, window.isVisible else {
            return false
        }

        return window.isKeyWindow
            || window.isMainWindow
            || NSApp.keyWindow === window
            || NSApp.mainWindow === window
    }

    init(model: MemoryViewerModel? = nil) {
        self.model = model ?? MemoryViewerModel()
        super.init()
    }

    func toggle() {
        if isFrontmost {
            hide()
        } else {
            reveal()
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    func show() {
        model.refresh()
        uiState.syncSelection(with: model)
        let window = window ?? makeWindow()
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        present(window)
    }

    func reveal() {
        if let window, window.isVisible {
            model.refresh()
            uiState.syncSelection(with: model)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            present(window)
            return
        }

        show()
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

    private func makeWindow() -> NSWindow {
        let frame = NSRect(
            x: 0,
            y: 0,
            width: PanelMetrics.memoryWindowWidth,
            height: PanelMetrics.memoryWindowHeight
        )

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Backtick Memory"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .line
        window.toolbar = makeToolbar()
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("BacktickMemoryWindow")
        window.minSize = NSSize(
            width: PanelMetrics.memoryWindowMinimumWidth,
            height: PanelMetrics.memoryWindowMinimumHeight
        )
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: MemoryViewerView(model: model, uiState: uiState)
        )

        self.window = window
        return window
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "BacktickMemoryToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarItemIdentifier.refresh]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarItemIdentifier.refresh]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == ToolbarItemIdentifier.refresh else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Refresh"
        item.paletteLabel = "Refresh"
        item.toolTip = "Refresh Memory"
        item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh Memory")
        item.target = self
        item.action = #selector(refreshMemory)
        return item
    }

    @objc
    private func refreshMemory() {
        model.refresh()
        uiState.syncSelection(with: model)
        window?.contentViewController?.view.layoutSubtreeIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else {
            return
        }

        window.orderOut(nil)
    }
}
