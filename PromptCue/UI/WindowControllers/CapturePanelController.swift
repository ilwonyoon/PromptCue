import AppKit
import Combine
import Carbon
import SwiftUI

@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: CapturePanel?
    private var suggestedTargetPanel: CaptureSuggestedTargetPanel?
    private var sizingObserver: AnyCancellable?
    private var suggestedTargetObserver: AnyCancellable?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var anchoredTopY: CGFloat?
    private var anchoredOriginX: CGFloat?

    init(model: AppModel) {
        self.model = model
        super.init()

        sizingObserver = Publishers.CombineLatest3(
            model.$draftEditorContentHeight.removeDuplicates(),
            model.$pendingScreenshotAttachment.map { $0 != nil }.removeDuplicates(),
            model.$isAwaitingRecentScreenshot.removeDuplicates()
        )
        .sink { [weak self] _, _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.resizePanelIfNeeded()
            }
        }

        suggestedTargetObserver = Publishers.CombineLatest3(
            model.$isShowingCaptureSuggestedTargetChooser.removeDuplicates(),
            model.$availableSuggestedTargets.removeDuplicates(),
            model.$captureDebugSuggestedTargetLine.removeDuplicates()
        )
        .sink { [weak self] _, _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.updateSuggestedTargetPanelIfNeeded()
            }
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        model.beginCaptureSession()
        let frame = initialPanelFrame()
        anchoredTopY = frame.maxY
        anchoredOriginX = frame.minX
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
    }

    func close() {
        model.endCaptureSession()
        detachAuxiliaryPanel(suggestedTargetPanel)
        suggestedTargetPanel?.orderOut(nil)
        panel?.orderOut(nil)
        removeDismissMonitors()
        anchoredTopY = nil
        anchoredOriginX = nil
    }

    private var isVisible: Bool {
        panel?.isVisible == true
    }

    private func makePanel() -> CapturePanel {
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
        panel.contentViewController = NSHostingController(
            rootView: CaptureComposerView(
                model: model,
                onSubmitSuccess: { [weak self] in
                    self?.close()
                }
            )
        )

        self.panel = panel
        return panel
    }

    private func makeSuggestedTargetPanel() -> CaptureSuggestedTargetPanel {
        let panel = CaptureSuggestedTargetPanel(
            contentRect: initialPanelFrame(),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

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
        panel.animationBehavior = .none
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = NSHostingController(
            rootView: CaptureSuggestedTargetListPanelView(model: model)
        )

        self.suggestedTargetPanel = panel
        return panel
    }

    private func initialPanelFrame() -> NSRect {
        let visibleFrame = screenVisibleFrame()
        let size = NSSize(
            width: AppUIConstants.capturePanelWidth,
            height: min(desiredPanelHeight(), visibleFrame.height - (PrimitiveTokens.Space.xl * 2))
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
            width: AppUIConstants.capturePanelWidth,
            height: min(desiredPanelHeight(), visibleFrame.height - (PrimitiveTokens.Space.xl * 2))
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

    private func suggestedTargetPanelFrame(above captureFrame: NSRect) -> NSRect {
        let visibleFrame = screenVisibleFrame()
        let size = NSSize(
            width: AppUIConstants.capturePanelWidth,
            height: min(desiredSuggestedTargetPanelHeight(), visibleFrame.height - (PrimitiveTokens.Space.xl * 2))
        )
        let maximumOriginY = visibleFrame.maxY - PrimitiveTokens.Space.xl - size.height
        let preferredOriginY = captureFrame.maxY
            - AppUIConstants.capturePanelOuterPadding
            + AppUIConstants.captureChooserPanelVerticalSpacing
            - AppUIConstants.captureChooserPanelOuterPadding
        let originY = min(maximumOriginY, preferredOriginY)

        return NSRect(
            x: captureFrame.minX,
            y: originY,
            width: size.width,
            height: size.height
        )
    }

    private func screenVisibleFrame() -> NSRect {
        panel?.screen?.visibleFrame
            ?? NSApp.keyWindow?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: AppUIConstants.capturePanelWidth, height: 240)
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

        let targetFrame = anchoredPanelFrame()
        if hasMeaningfulFrameChange(from: panel.frame, to: targetFrame) {
            panel.setFrame(targetFrame, display: true, animate: false)
        }

        updateSuggestedTargetPanelIfNeeded()
    }

    private func updateSuggestedTargetPanelIfNeeded() {
        guard let panel, isVisible, model.isShowingCaptureSuggestedTargetChooser else {
            let wasVisible = suggestedTargetPanel?.isVisible == true
            detachAuxiliaryPanel(suggestedTargetPanel)
            suggestedTargetPanel?.orderOut(nil)
            if wasVisible {
                refocusCaptureEditor()
            }
            return
        }

        let suggestedTargetPanel = suggestedTargetPanel ?? makeSuggestedTargetPanel()
        if let hostingController = suggestedTargetPanel.contentViewController as? NSHostingController<CaptureSuggestedTargetListPanelView> {
            hostingController.rootView = CaptureSuggestedTargetListPanelView(model: model)
        }

        let targetFrame = suggestedTargetPanelFrame(above: panel.frame)
        if hasMeaningfulFrameChange(from: suggestedTargetPanel.frame, to: targetFrame) {
            suggestedTargetPanel.setFrame(targetFrame, display: true, animate: false)
        }

        attachAuxiliaryPanel(suggestedTargetPanel, to: panel)
        if !suggestedTargetPanel.isVisible {
            suggestedTargetPanel.orderFrontRegardless()
            refocusCaptureEditor()
        }
    }

    private func desiredPanelHeight() -> CGFloat {
        let editorHeight = max(model.draftEditorContentHeight, AppUIConstants.captureTextLineHeight)
        let attachmentHeight: CGFloat

        if model.pendingScreenshotAttachment != nil || model.isAwaitingRecentScreenshot {
            attachmentHeight = PrimitiveTokens.Size.captureAttachmentPreviewSize + PrimitiveTokens.Space.sm
        } else {
            attachmentHeight = 0
        }

        let surfaceHeight = max(
            PrimitiveTokens.Size.searchFieldHeight,
            editorHeight
                + attachmentHeight
                + AppUIConstants.captureDebugLineHeight
                + PrimitiveTokens.Space.sm
                + (AppUIConstants.captureSurfaceInnerPadding * 2)
        )

        return ceil(
            (AppUIConstants.capturePanelOuterPadding * 2)
            + surfaceHeight
        )
    }

    private func desiredSuggestedTargetPanelHeight() -> CGFloat {
        let visibleRowUnits = suggestedTargetVisibleRowUnits()
        let fullRowCount = max(Int(floor(visibleRowUnits)), 1)
        let partialRowUnits = max(visibleRowUnits - CGFloat(fullRowCount), 0)
        let rowsHeight = (CGFloat(fullRowCount) * AppUIConstants.captureChooserRowHeight)
            + (CGFloat(max(0, fullRowCount - 1)) * AppUIConstants.captureChooserRowSpacing)
            + (partialRowUnits * AppUIConstants.captureChooserRowHeight)
        let contentHeight = AppUIConstants.captureChooserSurfaceVerticalPadding
            + (AppUIConstants.captureChooserPromptVerticalPadding * 2)
            + AppUIConstants.captureChooserPromptLineHeight
            + AppUIConstants.captureChooserPromptBottomSpacing
            + rowsHeight
            + AppUIConstants.captureChooserSurfaceVerticalPadding
        let surfaceHeight = max(
            PrimitiveTokens.Size.searchFieldHeight,
            contentHeight
        )

        return ceil(surfaceHeight + (AppUIConstants.captureChooserPanelOuterPadding * 2))
    }

    private func suggestedTargetVisibleRowUnits() -> CGFloat {
        let totalRows = model.captureSuggestedTargetChoiceCount
        return AppUIConstants.captureChooserVisibleRowUnits(for: totalRows)
    }

    private func hasMeaningfulFrameChange(from currentFrame: NSRect, to targetFrame: NSRect) -> Bool {
        abs(currentFrame.origin.x - targetFrame.origin.x) > 0.5
            || abs(currentFrame.origin.y - targetFrame.origin.y) > 0.5
            || abs(currentFrame.size.width - targetFrame.size.width) > 0.5
            || abs(currentFrame.size.height - targetFrame.size.height) > 0.5
    }

    private func installDismissMonitors() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else {
            return
        }

        let mask: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.closeIfMouseOutsidePanels(at: self?.mouseLocation(for: event) ?? NSEvent.mouseLocation)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.closeIfMouseOutsidePanels(at: NSEvent.mouseLocation)
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

    private func mouseLocation(for event: NSEvent) -> NSPoint {
        guard let window = event.window else {
            return NSEvent.mouseLocation
        }

        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func closeIfMouseOutsidePanels(at point: NSPoint) {
        guard isVisible else {
            return
        }

        let didClickInsideVisiblePanel = visiblePanels().contains { panel in
            panel.frame.contains(point)
        }

        if !didClickInsideVisiblePanel {
            if model.isShowingCaptureSuggestedTargetChooser {
                model.hideCaptureSuggestedTargetChooser()
                return
            }

            close()
        }
    }

    private func visiblePanels() -> [NSPanel] {
        [panel, suggestedTargetPanel].compactMap { panel in
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

            if let textView = self.findTextView(in: panel.contentView) {
                panel.makeFirstResponder(textView)
            }
        }
    }

    private func findTextView(in view: NSView?) -> WrappingCueTextView? {
        guard let view else {
            return nil
        }

        if let textView = view as? WrappingCueTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        return nil
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

private final class CaptureSuggestedTargetPanel: CaptureFloatingPanel {
    override var canBecomeKey: Bool { true }
}
