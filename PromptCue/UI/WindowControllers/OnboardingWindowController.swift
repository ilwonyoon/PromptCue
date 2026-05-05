import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let service: OnboardingService
    private let connector: MCPConnectorSettingsModel?
    private var window: NSWindow?
    private var state: OnboardingState?

    var isVisible: Bool {
        window?.isVisible == true
    }

    init(service: OnboardingService, connector: MCPConnectorSettingsModel? = nil) {
        self.service = service
        self.connector = connector
        super.init()
    }

    func presentIfNeeded() {
        guard service.shouldPresentOnFirstLaunch else {
            return
        }
        present()
    }

    func present() {
        let state = state ?? makeState()
        self.state = state
        connector?.refresh()

        let window = window ?? makeWindow(state: state)
        self.window = window

        centerOnActiveScreen(window)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Center the onboarding window on whichever monitor currently shows
    /// the cursor / key window. `NSWindow.center()` only handles the main
    /// screen and only on first show, so re-entry after a user drag would
    /// leave the panel wherever it last sat.
    private func centerOnActiveScreen(_ window: NSWindow) {
        let activeScreen = NSScreen.screens.first(where: { screen in
            NSMouseInRect(NSEvent.mouseLocation, screen.frame, false)
        }) ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen = activeScreen else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeState() -> OnboardingState {
        OnboardingState(service: service, connector: connector) { [weak self] in
            self?.close()
        }
    }

    private func makeWindow(state: OnboardingState) -> NSWindow {
        let frame = NSRect(x: 0, y: 0, width: 540, height: 480)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Welcome to Backtick"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingRootView(state: state)
        )

        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }
}
