import AppKit
import SwiftUI

@MainActor
final class DesignSystemWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
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

        window.title = "Prompt Cue Design System"
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

    func windowWillClose(_ notification: Notification) {
        guard let window else {
            return
        }

        window.orderOut(nil)
    }
}
