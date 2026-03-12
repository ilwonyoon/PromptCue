import AppKit
import SwiftUI

@MainActor
final class DesignSystemWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let frame = NSRect(
            x: 0,
            y: 0,
            width: DesignSystemPreviewTokens.windowWidth,
            height: DesignSystemPreviewTokens.windowHeight
        )
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Backtick Design System"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(
            width: DesignSystemPreviewTokens.windowWidth,
            height: DesignSystemPreviewTokens.windowHeight
        )
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: DesignSystemPreviewView())

        self.window = window
        return window
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        window?.appearance = appearance
        window?.invalidateShadow()
        window?.contentView?.needsDisplay = true
        window?.contentView?.subviews.forEach { $0.needsDisplay = true }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else {
            return
        }

        window.orderOut(nil)
    }
}
