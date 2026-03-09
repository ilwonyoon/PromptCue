import AppKit
import Carbon
import QuartzCore
import SwiftUI

@MainActor
final class StackPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: StackPanel?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private(set) var isVisible = false
    private var isAnimatingClose = false

    var isPresentedOrTransitioning: Bool {
        isVisible || isAnimatingClose || panel?.isVisible == true
    }

    init(model: AppModel) {
        self.model = model
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
    }

    func show() {
        guard !isAnimatingClose else {
            return
        }

        let panel = panel ?? makePanel()
        guard !panel.isVisible else {
            return
        }

        let targetFrame = onscreenPanelFrame(for: panel.frame.size)
        panel.setFrame(offscreenPanelFrame(for: targetFrame.size), display: false)
        panel.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        installDismissMonitors()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = PrimitiveTokens.Motion.standard
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    func close() {
        model.clearSelection()

        guard let panel else {
            isVisible = false
            removeDismissMonitors()
            return
        }

        guard panel.isVisible, !isAnimatingClose else {
            isVisible = false
            removeDismissMonitors()
            return
        }

        isVisible = false
        removeDismissMonitors()
        isAnimatingClose = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = PrimitiveTokens.Motion.quick
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offscreenPanelFrame(for: panel.frame.size), display: true)
        } completionHandler: { [weak self, weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
            self?.isAnimatingClose = false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else {
            return
        }

        panel.setFrame(onscreenPanelFrame(for: panel.frame.size), display: true, animate: false)
    }

    private func makePanel() -> StackPanel {
        let initialFrame = offscreenPanelFrame(for: NSSize(width: AppUIConstants.stackPanelWidth, height: 0))
        let panel = StackPanel(
            contentRect: initialFrame,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.minSize = NSSize(width: AppUIConstants.stackPanelWidth, height: 360)
        panel.onCancel = { [weak self] in
            self?.close()
        }
        panel.contentViewController = NSHostingController(
            rootView: CardStackView(
                model: model,
                onCopyCard: { [weak self] card in
                    self?.copyCardAndClose(card)
                },
                onCopySelection: { [weak self] in
                    self?.copySelectionAndClose()
                },
                onDeleteCard: { [weak self] card in
                    self?.model.delete(card: card)
                }
            )
        )

        self.panel = panel
        return panel
    }

    private func copyCardAndClose(_ card: CaptureCard) {
        _ = model.copy(card: card)
        close()
    }

    private func copySelectionAndClose() {
        guard model.copySelection() != nil else {
            return
        }

        close()
    }

    private func onscreenPanelFrame(for size: NSSize? = nil) -> NSRect {
        let visibleFrame = screenVisibleFrame()
        let width = max(size?.width ?? AppUIConstants.stackPanelWidth, AppUIConstants.stackPanelWidth)
        let height = visibleFrame.height

        return NSRect(
            x: visibleFrame.maxX - width,
            y: visibleFrame.minY,
            width: width,
            height: height
        )
    }

    private func offscreenPanelFrame(for size: NSSize) -> NSRect {
        let visibleFrame = screenVisibleFrame()

        return NSRect(
            x: visibleFrame.maxX,
            y: visibleFrame.minY,
            width: size.width,
            height: visibleFrame.height
        )
    }

    private func screenVisibleFrame() -> NSRect {
        panel?.screen?.visibleFrame
            ?? NSApp.keyWindow?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: AppUIConstants.stackPanelWidth, height: 600)
    }

    private func installDismissMonitors() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else {
            return
        }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.closeIfNeeded(for: event)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.closeIfMouseOutsidePanel()
        }
    }

    private func removeDismissMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }

        localMouseMonitor = nil
        globalMouseMonitor = nil
    }

    private func closeIfNeeded(for event: NSEvent) {
        guard let panel, isVisible else {
            return
        }

        if event.window !== panel {
            close()
            return
        }

        closeIfMouseOutsidePanel()
    }

    private func closeIfMouseOutsidePanel() {
        guard let panel, isVisible else {
            return
        }

        if !panel.frame.contains(NSEvent.mouseLocation) {
            close()
        }
    }
}

private final class StackPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
