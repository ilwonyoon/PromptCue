import AppKit
import Carbon
import QuartzCore
import SwiftUI

@MainActor
final class StackPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let onEditCard: (CaptureCard) -> Void
    private var panel: StackPanel?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private(set) var isVisible = false
    private var isAnimatingClose = false
    private var hasWarmedFirstPresentation = false

    var isPresentedOrTransitioning: Bool {
        isVisible || isAnimatingClose || panel?.isVisible == true
    }

    init(
        model: AppModel,
        onEditCard: @escaping (CaptureCard) -> Void = { _ in }
    ) {
        self.model = model
        self.onEditCard = onEditCard
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

        PerformanceTrace.markStackOpenPhase("show_enter")

        let panel = panel ?? makePanel()
        guard !panel.isVisible else {
            return
        }
        PerformanceTrace.markStackOpenPhase("panel_ready")

        model.beginStackSuggestedTargetPresentation()
        PerformanceTrace.markStackOpenPhase("suggested_target_presentation_started")
        primePanelLayout(panel)
        PerformanceTrace.markStackOpenPhase("layout_primed")
        let targetFrame = onscreenPanelFrame(for: panel.frame.size)
        panel.setFrame(offscreenPanelFrame(for: targetFrame.size), display: false)
        PerformanceTrace.markStackOpenPhase("offscreen_frame_positioned")
        panel.armFirstFrameCallback {
            PerformanceTrace.completeStackOpenTraceIfNeeded()
        }
        PerformanceTrace.markStackOpenPhase("first_frame_callback_armed")

        // Start fully transparent so backdrop materials and SwiftUI content
        // can settle for one frame before becoming visible — prevents flash.
        panel.alphaValue = 0
        PerformanceTrace.markStackOpenPhase("alpha_zeroed")
        NSApp.activate(ignoringOtherApps: true)
        PerformanceTrace.markStackOpenPhase("app_activated")
        panel.makeKeyAndOrderFront(nil)
        PerformanceTrace.markStackOpenPhase("made_key_and_ordered_front")
        isVisible = true
        installDismissMonitors()
        PerformanceTrace.markStackOpenPhase("dismiss_monitors_installed")

        // Allow one run-loop cycle for NSVisualEffectView materials to
        // composite, then fade in alongside the slide animation.
        DispatchQueue.main.async { [weak panel] in
            guard let panel else { return }
            PerformanceTrace.markStackOpenPhase("animation_dispatch")
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PrimitiveTokens.Motion.standard
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(targetFrame, display: true)
            }
        }
    }

    func prepareForFirstPresentation() {
        guard !isVisible, !isAnimatingClose else {
            return
        }

        let panel = panel ?? makePanel()
        primePanelLayout(panel)
        warmOrderFrontIfNeeded(panel)
    }

    func close(commitDeferredCopies: Bool = true) {
        if commitDeferredCopies, model.hasStagedCopiedCards {
            model.commitDeferredCopies()
        } else {
            model.exitMultiSelectMode()
        }

        guard let panel else {
            model.endStackSuggestedTargetPresentation()
            isVisible = false
            removeDismissMonitors()
            return
        }

        guard panel.isVisible, !isAnimatingClose else {
            model.endStackSuggestedTargetPresentation()
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
            self?.model.endStackSuggestedTargetPresentation()
            self?.isAnimatingClose = false
        }
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        panel?.appearance = appearance
        panel?.invalidateShadow()
        panel?.contentView?.needsDisplay = true
        panel?.contentView?.subviews.forEach { $0.needsDisplay = true }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func windowDidExpose(_ notification: Notification) {
        guard let panel,
              notification.object as AnyObject? === panel
        else {
            return
        }

        PerformanceTrace.completeStackOpenTraceIfNeeded()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else {
            return
        }

        panel.setFrame(onscreenPanelFrame(for: panel.frame.size), display: true, animate: false)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let panel, isVisible else {
            return
        }

        panel.setFrame(onscreenPanelFrame(for: panel.frame.size), display: true, animate: false)
    }

    private func makePanel() -> StackPanel {
        let initialFrame = offscreenPanelFrame(for: NSSize(width: PanelMetrics.stackPanelWidth, height: 0))
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
        panel.minSize = NSSize(width: PanelMetrics.stackPanelWidth, height: PanelMetrics.stackPanelMinimumHeight)
        panel.onCancel = { [weak self] in
            self?.close()
        }
        panel.contentViewController = NSHostingController(
            rootView: CardStackView(
                model: model,
                onBackdropTap: { [weak self] in
                    self?.close()
                },
                onEditCard: { [weak self] card in
                    self?.onEditCard(card)
                },
                onDeleteCard: { [weak self] card in
                    self?.model.delete(card: card)
                }
            )
        )
        PerformanceTrace.markStackOpenPhase("panel_content_built")

        self.panel = panel
        return panel
    }

    private func primePanelLayout(_ panel: StackPanel) {
        guard let contentView = panel.contentView else {
            return
        }

        contentView.needsLayout = true
        PerformanceTrace.markStackOpenPhase("layout_marked_dirty")
        contentView.layoutSubtreeIfNeeded()
        PerformanceTrace.markStackOpenPhase("layout_subtree_complete")
        contentView.displayIfNeeded()
        PerformanceTrace.markStackOpenPhase("display_if_needed_complete")
    }

    private func warmOrderFrontIfNeeded(_ panel: StackPanel) {
        guard !hasWarmedFirstPresentation, !panel.isVisible else {
            return
        }

        hasWarmedFirstPresentation = true
        let targetFrame = onscreenPanelFrame(for: panel.frame.size)
        panel.setFrame(offscreenPanelFrame(for: targetFrame.size), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func onscreenPanelFrame(for size: NSSize? = nil) -> NSRect {
        let visibleFrame = screenVisibleFrame()
        let width = max(size?.width ?? PanelMetrics.stackPanelWidth, PanelMetrics.stackPanelWidth)
        let height = visibleFrame.height

        return NSRect(
            x: visibleFrame.maxX - width,
            y: visibleFrame.maxY - height,
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
            ?? NSRect(
                x: 0,
                y: 0,
                width: PanelMetrics.stackPanelWidth,
                height: PanelMetrics.stackPanelFallbackVisibleHeight
            )
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
    private var firstFrameCallback: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Bypass AppKit's default frame constraint so the panel can be placed
    /// off-screen (to the right of the visible area) for the slide-in/out
    /// animation. Without this override, `setFrame(_:display:animate:)`
    /// would clamp the frame to the screen bounds and prevent the animation.
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

    override func displayIfNeeded() {
        super.displayIfNeeded()
        fireFirstFrameCallbackIfNeeded()
    }

    func armFirstFrameCallback(_ callback: @escaping () -> Void) {
        firstFrameCallback = callback
    }

    private func fireFirstFrameCallbackIfNeeded() {
        guard let firstFrameCallback else {
            return
        }

        self.firstFrameCallback = nil
        firstFrameCallback()
    }
}
