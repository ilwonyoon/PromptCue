import AppKit
import SwiftUI

@MainActor
final class MemoryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: MemoryViewerModel

    init(model: MemoryViewerModel? = nil) {
        self.model = model ?? MemoryViewerModel()
        super.init()
    }

    func toggle() {
        guard let window, window.isVisible else {
            show()
            return
        }

        window.orderOut(nil)
    }

    func show() {
        model.refresh()
        let window = window ?? makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
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
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(
            width: PanelMetrics.memoryWindowMinimumWidth,
            height: PanelMetrics.memoryWindowMinimumHeight
        )
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: MemoryViewerView(model: model)
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
