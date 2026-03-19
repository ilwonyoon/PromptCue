import AppKit
import Carbon
import SwiftUI

struct CapturePanelFrameUpdateMetrics {
    let totalMilliseconds: Double
    let averageMicroseconds: Double
    let appliedFrameCount: Int
    let skippedFrameCount: Int
}

enum CapturePanelFrameUpdateGuard {
    static let tolerance: CGFloat = 0.5

    static func shouldApply(
        currentFrame: NSRect,
        targetFrame: NSRect,
        tolerance: CGFloat = tolerance
    ) -> Bool {
        abs(currentFrame.origin.x - targetFrame.origin.x) > tolerance
            || abs(currentFrame.origin.y - targetFrame.origin.y) > tolerance
            || abs(currentFrame.size.width - targetFrame.size.width) > tolerance
            || abs(currentFrame.size.height - targetFrame.size.height) > tolerance
    }

    @MainActor
    static func benchmark(
        initialFrame: NSRect,
        targetFrames: [NSRect],
        guarded: Bool,
        applier: (NSRect) -> Void
    ) -> CapturePanelFrameUpdateMetrics {
        var currentFrame = initialFrame
        var appliedFrameCount = 0
        var skippedFrameCount = 0

        let startedAt = CFAbsoluteTimeGetCurrent()

        for targetFrame in targetFrames {
            if guarded,
               !shouldApply(
                currentFrame: currentFrame,
                targetFrame: targetFrame
               ) {
                skippedFrameCount += 1
                continue
            }

            applier(targetFrame)
            currentFrame = targetFrame
            appliedFrameCount += 1
        }

        let totalMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        let operationCount = max(targetFrames.count, 1)

        return CapturePanelFrameUpdateMetrics(
            totalMilliseconds: totalMilliseconds,
            averageMicroseconds: totalMilliseconds * 1_000 / Double(operationCount),
            appliedFrameCount: appliedFrameCount,
            skippedFrameCount: skippedFrameCount
        )
    }
}

@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: CapturePanel?
    private var runtimeViewController: CapturePanelRuntimeViewController?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var anchoredTopY: CGFloat?
    private var anchoredOriginX: CGFloat?
    private var preferredPanelHeight: CGFloat = PanelMetrics.capturePanelOuterPadding * 2 + PrimitiveTokens.Size.searchFieldHeight

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
    }

    func toggle() {
        if isVisible {
            close()
            return
        }
        show()
    }

    func show() {
        model.beginCaptureSession()
        let runtimeViewController = runtimeViewController ?? makeRuntimeViewController()
        runtimeViewController.prepareForPresentation()
        preferredPanelHeight = runtimeViewController.currentPreferredPanelHeight
        let panel = panel ?? makePanel(contentViewController: runtimeViewController)
        primePanelLayout(panel)
        let frame = initialPanelFrame()
        anchoredTopY = frame.maxY
        anchoredOriginX = frame.minX
        applyFrameIfNeeded(frame, to: panel, display: true, animate: false)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        runtimeViewController.refreshAppearance()
        runtimeViewController.focusEditorIfPossible()
        installDismissMonitors()
    }

    func close(persistDraft: Bool = true) {
        if persistDraft {
            runtimeViewController?.persistDraftIfNeeded()
        } else {
            runtimeViewController?.discardPendingDraftSync()
        }
        panel?.orderOut(nil)
        model.endCaptureSession()
        removeDismissMonitors()
        anchoredTopY = nil
        anchoredOriginX = nil
    }

    func markAppearanceDirty() {
        // No flag needed: show() already calls
        // runtimeViewController.refreshAppearance() unconditionally,
        // so a hidden-during-theme-change scenario is handled.
        // Kept for API symmetry with StackPanelController.
    }

    func refreshForInheritedAppearanceChange() {
        panel?.appearance = nil
        panel?.contentView?.appearance = nil
        panel?.contentViewController?.view.appearance = nil
        panel?.invalidateShadow()
        panel?.contentView?.needsDisplay = true
        panel?.contentViewController?.view.layer?.contents = nil
        panel?.contentViewController?.view.needsLayout = true
        panel?.contentViewController?.view.layoutSubtreeIfNeeded()
        panel?.contentViewController?.view.needsDisplay = true
        runtimeViewController?.refreshAppearance()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard isVisible else {
            return
        }

        anchoredTopY = nil
        anchoredOriginX = nil
        resizePanelIfNeeded()
    }

    private var isVisible: Bool {
        panel?.isVisible == true
    }

    private func makeRuntimeViewController() -> CapturePanelRuntimeViewController {
        let controller = CapturePanelRuntimeViewController(model: model)
        controller.onPreferredPanelHeightChange = { [weak self] height in
            guard let self else {
                return
            }
            self.preferredPanelHeight = height
            self.resizePanelIfNeeded()
        }
        controller.onSubmitSuccess = { [weak self] in
            self?.close(persistDraft: false)
        }
        controller.onCancelRequest = { [weak self] in
            self?.close()
        }
        runtimeViewController = controller
        return controller
    }

    private func makePanel(contentViewController: NSViewController) -> CapturePanel {
        let panel = CapturePanel(
            contentRect: initialPanelFrame(),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .alertPanel
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.onCancel = { [weak self] in
            self?.close()
        }
        panel.contentViewController = contentViewController

        self.panel = panel
        return panel
    }

    private func initialPanelFrame() -> NSRect {
        let visibleFrame = screenVisibleFrame()
        let size = NSSize(
            width: PanelMetrics.capturePanelWidth,
            height: min(preferredPanelHeight, visibleFrame.height - (PrimitiveTokens.Space.xl * 2))
        )

        return NSRect(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    private func anchoredPanelFrame() -> NSRect {
        let visibleFrame = screenVisibleFrame()
        let size = NSSize(
            width: PanelMetrics.capturePanelWidth,
            height: min(preferredPanelHeight, visibleFrame.height - (PrimitiveTokens.Space.xl * 2))
        )
        let fallbackFrame = initialPanelFrame()
        let resolvedOriginX = anchoredOriginX ?? fallbackFrame.minX
        let resolvedTopY = anchoredTopY ?? fallbackFrame.maxY
        let minimumOriginY = visibleFrame.minY + PrimitiveTokens.Space.xl
        let originY = max(minimumOriginY, resolvedTopY - size.height)

        return NSRect(
            x: resolvedOriginX,
            y: originY,
            width: size.width,
            height: size.height
        )
    }

    private func screenVisibleFrame() -> NSRect {
        NSApp.keyWindow?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(
                x: 0,
                y: 0,
                width: PanelMetrics.capturePanelWidth,
                height: PanelMetrics.capturePanelFallbackVisibleHeight
            )
    }

    private func resizePanelIfNeeded() {
        guard let panel, isVisible else {
            return
        }

        if anchoredTopY == nil {
            anchoredTopY = panel.frame.maxY
        }

        if anchoredOriginX == nil {
            anchoredOriginX = panel.frame.minX
        }

        applyFrameIfNeeded(anchoredPanelFrame(), to: panel, display: true, animate: false)
    }

    private func primePanelLayout(_ panel: CapturePanel) {
        guard let contentView = panel.contentView else {
            return
        }

        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
    }

    private func applyFrameIfNeeded(
        _ targetFrame: NSRect,
        to panel: CapturePanel,
        display: Bool,
        animate: Bool
    ) {
        guard CapturePanelFrameUpdateGuard.shouldApply(
            currentFrame: panel.frame,
            targetFrame: targetFrame
        ) else {
            return
        }

        panel.setFrame(targetFrame, display: display, animate: animate)
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
        guard isVisible else {
            return
        }

        let screenPoint = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        closeIfMouseOutsidePanels(at: screenPoint)
    }

    private func closeIfMouseOutsidePanel() {
        closeIfMouseOutsidePanels(at: NSEvent.mouseLocation)
    }

    private func closeIfMouseOutsidePanels(at point: NSPoint) {
        guard isVisible else {
            return
        }

        let didClickInsideVisiblePanel = visiblePanels().contains { panel in
            panel.frame.contains(point)
        }

        if !didClickInsideVisiblePanel {
            close()
        }
    }

    private func visiblePanels() -> [NSPanel] {
        [panel].compactMap { panel in
            guard let panel, panel.isVisible else {
                return nil
            }

            return panel
        }
    }

    private func refocusCaptureEditor() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else {
                return
            }

            panel.makeKeyAndOrderFront(nil)
            self.runtimeViewController?.focusEditorIfPossible()
        }
    }

    private func attachAuxiliaryPanel(_ auxiliaryPanel: NSPanel?, to parentPanel: NSPanel) {
        guard let auxiliaryPanel else {
            return
        }

        let childWindows = parentPanel.childWindows ?? []
        if !childWindows.contains(auxiliaryPanel) {
            parentPanel.addChildWindow(auxiliaryPanel, ordered: .above)
        }
    }

    private func detachAuxiliaryPanel(_ auxiliaryPanel: NSPanel?) {
        guard let auxiliaryPanel,
              let parentWindow = auxiliaryPanel.parent else {
            return
        }

        parentWindow.removeChildWindow(auxiliaryPanel)
    }
}

private class CaptureFloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeMain: Bool { false }

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

private final class CapturePanel: CaptureFloatingPanel {
    override var canBecomeKey: Bool { true }
}
