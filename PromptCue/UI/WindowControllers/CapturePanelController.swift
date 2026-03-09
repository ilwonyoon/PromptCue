import AppKit
import Carbon
import SwiftUI

@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: CapturePanel?
    private var runtimeViewController: CapturePanelRuntimeViewController?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var anchoredTopY: CGFloat?
    private var anchoredOriginX: CGFloat?
    private var preferredPanelHeight: CGFloat = AppUIConstants.capturePanelOuterPadding * 2 + PrimitiveTokens.Size.searchFieldHeight

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
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        runtimeViewController.focusEditorIfPossible()
        installDismissMonitors()
    }

    func close() {
        model.endCaptureSession()
        panel?.orderOut(nil)
        removeDismissMonitors()
        anchoredTopY = nil
        anchoredOriginX = nil
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
            self?.close()
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
            width: AppUIConstants.capturePanelWidth,
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
            width: AppUIConstants.capturePanelWidth,
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

        panel.setFrame(anchoredPanelFrame(), display: true, animate: false)
    }

    private func primePanelLayout(_ panel: CapturePanel) {
        guard let contentView = panel.contentView else {
            return
        }

        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
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

private final class CapturePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
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
