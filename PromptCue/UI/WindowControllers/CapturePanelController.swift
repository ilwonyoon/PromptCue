import AppKit
import Combine
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
    private var suggestedTargetPanel: CaptureSuggestedTargetPanel?
    private var runtimeViewController: CapturePanelRuntimeViewController?
    private var suggestedTargetObserver: AnyCancellable?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var anchoredTopY: CGFloat?
    private var anchoredOriginX: CGFloat?
    private var preferredPanelHeight: CGFloat = PanelMetrics.capturePanelOuterPadding * 2 + PrimitiveTokens.Size.searchFieldHeight

    init(model: AppModel) {
        self.model = model
        super.init()
        suggestedTargetObserver = Publishers.CombineLatest(
            model.$isShowingCaptureSuggestedTargetChooser,
            model.$availableSuggestedTargets
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.updateSuggestedTargetPanelIfNeeded()
        }
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
        applyFrameIfNeeded(frame, to: panel, display: true, animate: false)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        runtimeViewController.refreshAppearance()
        runtimeViewController.focusEditorIfPossible()
        installDismissMonitors()
        updateSuggestedTargetPanelIfNeeded()
    }

    func close(persistDraft: Bool = true) {
        if persistDraft {
            runtimeViewController?.persistDraftIfNeeded()
        } else {
            runtimeViewController?.discardPendingDraftSync()
        }
        detachAuxiliaryPanel(suggestedTargetPanel)
        suggestedTargetPanel?.orderOut(nil)
        panel?.orderOut(nil)
        model.endCaptureSession()
        removeDismissMonitors()
        anchoredTopY = nil
        anchoredOriginX = nil
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        panel?.appearance = appearance
        panel?.contentViewController?.view.appearance = appearance
        panel?.invalidateShadow()
        panel?.contentView?.needsDisplay = true
        runtimeViewController?.refreshAppearance()

        suggestedTargetPanel?.appearance = appearance
        suggestedTargetPanel?.contentViewController?.view.appearance = appearance
        suggestedTargetPanel?.invalidateShadow()
        (suggestedTargetPanel?.contentViewController as? CaptureSuggestedTargetPanelViewController)?.refreshAppearance()
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
        panel.onCancel = { [weak self] in
            self?.model.hideCaptureSuggestedTargetChooser()
            self?.refocusCaptureEditor()
        }
        panel.contentViewController = CaptureSuggestedTargetPanelViewController(model: model)

        suggestedTargetPanel = panel
        return panel
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

    private func suggestedTargetPanelFrame(above captureFrame: NSRect) -> NSRect {
        let visibleFrame = screenVisibleFrame()
        let size = NSSize(
            width: PanelMetrics.capturePanelWidth,
            height: min(desiredSuggestedTargetPanelHeight(), visibleFrame.height - (PrimitiveTokens.Space.xl * 2))
        )
        return CaptureSuggestedTargetPanelLayout.frame(
            above: captureFrame,
            visibleFrame: visibleFrame,
            panelSize: size
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
        updateSuggestedTargetPanelIfNeeded()
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

        let targetFrame = suggestedTargetPanelFrame(above: panel.frame)
        if CapturePanelFrameUpdateGuard.shouldApply(
            currentFrame: suggestedTargetPanel.frame,
            targetFrame: targetFrame
        ) {
            suggestedTargetPanel.setFrame(targetFrame, display: true, animate: false)
        }

        attachAuxiliaryPanel(suggestedTargetPanel, to: panel)
        if !suggestedTargetPanel.isVisible {
            suggestedTargetPanel.orderFrontRegardless()
            refocusCaptureEditor()
        }
    }

    private func desiredSuggestedTargetPanelHeight() -> CGFloat {
        let visibleRowUnits = suggestedTargetVisibleRowUnits(allowsPeekRow: false)
        let fullRowCount = max(Int(floor(visibleRowUnits)), 1)
        let partialRowUnits = max(visibleRowUnits - CGFloat(fullRowCount), 0)
        let interRowSpacing = AppUIConstants.captureChooserSectionSpacing
        let rowsHeight = (CGFloat(fullRowCount) * AppUIConstants.captureChooserRowHeight)
            + (CGFloat(max(0, fullRowCount - 1)) * interRowSpacing)
            + (partialRowUnits * AppUIConstants.captureChooserRowHeight)
        let contentHeight = AppUIConstants.captureChooserPanelSurfaceTopPadding
            + AppUIConstants.captureChooserPanelHeaderTopPadding
            + AppUIConstants.captureChooserPromptLineHeight
            + AppUIConstants.captureChooserPanelHeaderBottomPadding
            + AppUIConstants.captureChooserPromptBottomSpacing
            + rowsHeight
            + AppUIConstants.captureChooserPanelSurfaceBottomPadding
        let surfaceHeight = max(PrimitiveTokens.Size.searchFieldHeight, contentHeight)

        return ceil(
            surfaceHeight
                + AppUIConstants.captureChooserPanelShadowTopInset
                + AppUIConstants.captureChooserPanelShadowBottomInset
        )
    }

    private func suggestedTargetVisibleRowUnits(allowsPeekRow: Bool) -> CGFloat {
        let totalRows = model.captureSuggestedTargetChoiceCount
        return AppUIConstants.captureChooserVisibleRowUnits(
            for: totalRows,
            allowsPeekRow: allowsPeekRow
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

enum CaptureSuggestedTargetPanelLayout {
    static func frame(
        above captureFrame: NSRect,
        visibleFrame: NSRect,
        panelSize: NSSize
    ) -> NSRect {
        let maximumOriginY = visibleFrame.maxY - PrimitiveTokens.Space.xl - panelSize.height
        let preferredOriginY = captureShellTopY(for: captureFrame)
            + AppUIConstants.captureChooserPanelVerticalSpacing
            - AppUIConstants.captureChooserPanelShadowBottomInset
        let originY = min(maximumOriginY, preferredOriginY)

        return NSRect(
            x: captureFrame.minX,
            y: originY,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    static func captureShellTopY(for captureFrame: NSRect) -> CGFloat {
        captureFrame.maxY - PanelMetrics.capturePanelShadowTopInset
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

private final class CaptureSuggestedTargetPanelViewController: NSViewController {
    private let model: AppModel
    private let shadowHostView = CaptureSuggestedTargetShadowHostView()
    private let shadowCasterView = CaptureSuggestedTargetShadowCasterView()
    private let shellView = CaptureSuggestedTargetShellView()
    private let hostingView: NSHostingView<CaptureSuggestedTargetChooserPanelView>

    init(model: AppModel) {
        self.model = model
        self.hostingView = NSHostingView(rootView: CaptureSuggestedTargetChooserPanelView(model: model))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        buildViewHierarchy()
    }

    func refreshAppearance() {
        let appliedAppearance = view.effectiveAppearance
        view.appearance = appliedAppearance
        shadowHostView.appearance = appliedAppearance
        shadowCasterView.appearance = appliedAppearance
        shellView.appearance = appliedAppearance
        view.needsDisplay = true
        shadowCasterView.refreshAppearance()
        shellView.refreshAppearance()
        hostingView.appearance = appliedAppearance
        hostingView.needsDisplay = true
    }

    private func buildViewHierarchy() {
        shadowHostView.translatesAutoresizingMaskIntoConstraints = false
        shadowCasterView.translatesAutoresizingMaskIntoConstraints = false
        shellView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(shadowHostView)
        shadowHostView.addSubview(shadowCasterView)
        shadowHostView.addSubview(shellView)
        shellView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            shadowHostView.topAnchor.constraint(equalTo: view.topAnchor, constant: AppUIConstants.captureChooserPanelShadowTopInset),
            shadowHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppUIConstants.capturePanelOuterPadding),
            shadowHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppUIConstants.capturePanelOuterPadding),
            shadowHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -AppUIConstants.captureChooserPanelShadowBottomInset),

            shadowCasterView.leadingAnchor.constraint(equalTo: shadowHostView.leadingAnchor),
            shadowCasterView.trailingAnchor.constraint(equalTo: shadowHostView.trailingAnchor),
            shadowCasterView.topAnchor.constraint(equalTo: shadowHostView.topAnchor),
            shadowCasterView.bottomAnchor.constraint(equalTo: shadowHostView.bottomAnchor),

            shellView.leadingAnchor.constraint(equalTo: shadowHostView.leadingAnchor),
            shellView.trailingAnchor.constraint(equalTo: shadowHostView.trailingAnchor),
            shellView.topAnchor.constraint(equalTo: shadowHostView.topAnchor),
            shellView.bottomAnchor.constraint(equalTo: shadowHostView.bottomAnchor),

            hostingView.leadingAnchor.constraint(equalTo: shellView.leadingAnchor, constant: PrimitiveTokens.Space.xl),
            hostingView.trailingAnchor.constraint(equalTo: shellView.trailingAnchor, constant: -PrimitiveTokens.Space.xl),
            hostingView.topAnchor.constraint(equalTo: shellView.topAnchor, constant: AppUIConstants.captureChooserPanelSurfaceTopPadding),
            hostingView.bottomAnchor.constraint(equalTo: shellView.bottomAnchor, constant: -AppUIConstants.captureChooserPanelSurfaceBottomPadding),
        ])
    }
}

private final class CaptureSuggestedTargetShadowHostView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class CaptureSuggestedTargetShadowCasterView: NSView {
    private let ambientLayer = CAShapeLayer()
    private let keyLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        layer?.addSublayer(ambientLayer)
        layer?.addSublayer(keyLayer)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        updateShape()
    }

    func refreshAppearance() {
        updateAppearance()
        needsDisplay = true
    }

    private func updateAppearance() {
        ambientLayer.fillColor = NSColor.white.withAlphaComponent(0.02).cgColor
        ambientLayer.shadowColor = ambientShadowColor.cgColor
        ambientLayer.shadowOpacity = Float(PrimitiveTokens.Shadow.captureAmbientOpacity)
        ambientLayer.shadowRadius = PrimitiveTokens.Shadow.captureAmbientBlur / 2
        ambientLayer.shadowOffset = CGSize(width: PrimitiveTokens.Shadow.zeroX, height: -PrimitiveTokens.Shadow.captureAmbientY)

        keyLayer.fillColor = NSColor.white.withAlphaComponent(0.02).cgColor
        keyLayer.shadowColor = keyShadowColor.cgColor
        keyLayer.shadowOpacity = Float(PrimitiveTokens.Shadow.captureKeyOpacity)
        keyLayer.shadowRadius = PrimitiveTokens.Shadow.captureKeyBlur / 2
        keyLayer.shadowOffset = CGSize(width: PrimitiveTokens.Shadow.zeroX, height: -PrimitiveTokens.Shadow.captureKeyY)

        updateShape()
    }

    private func updateShape() {
        let path = CGPath(
            roundedRect: bounds,
            cornerWidth: PrimitiveTokens.Radius.lg,
            cornerHeight: PrimitiveTokens.Radius.lg,
            transform: nil
        )
        ambientLayer.frame = bounds
        ambientLayer.path = path
        ambientLayer.shadowPath = path

        keyLayer.frame = bounds
        keyLayer.path = path
        keyLayer.shadowPath = path
    }

    private var usesDarkAppearance: Bool {
        let bestMatch = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        return bestMatch == .darkAqua || bestMatch == .vibrantDark
    }

    private var ambientShadowColor: NSColor {
        usesDarkAppearance
            ? NSColor.black.withAlphaComponent(0.28)
            : NSColor.black.withAlphaComponent(0.16)
    }

    private var keyShadowColor: NSColor {
        usesDarkAppearance
            ? NSColor.black.withAlphaComponent(0.36)
            : NSColor.black.withAlphaComponent(0.22)
    }
}

private final class CaptureSuggestedTargetShellView: NSVisualEffectView {
    private let fillLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let topHighlightLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        state = .active
        blendingMode = .withinWindow
        material = .menu
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(borderLayer)
        layer?.addSublayer(topHighlightLayer)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        updateShape()
    }

    func refreshAppearance() {
        updateAppearance()
        needsDisplay = true
    }

    private func updateAppearance() {
        guard let layer else { return }

        material = usesDarkAppearance ? .menu : .underWindowBackground
        fillLayer.fillColor = captureShellFillColor.cgColor
        borderLayer.strokeColor = captureShellStrokeColor.cgColor
        borderLayer.lineWidth = PrimitiveTokens.Stroke.subtle
        borderLayer.fillColor = NSColor.clear.cgColor
        topHighlightLayer.strokeColor = captureShellTopHighlightColor.cgColor
        topHighlightLayer.lineWidth = PrimitiveTokens.Stroke.subtle
        topHighlightLayer.fillColor = NSColor.clear.cgColor
        layer.cornerRadius = PrimitiveTokens.Radius.lg
        layer.backgroundColor = NSColor.clear.cgColor
        updateShape()
    }

    private func updateShape() {
        guard let layer else { return }

        let boundsRect = bounds
        let radius = PrimitiveTokens.Radius.lg
        let fullPath = CGPath(
            roundedRect: boundsRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        fillLayer.frame = boundsRect
        fillLayer.path = fullPath

        borderLayer.frame = boundsRect
        borderLayer.path = fullPath

        let topRect = CGRect(
            x: 0,
            y: max(0, boundsRect.height - PrimitiveTokens.Space.lg),
            width: boundsRect.width,
            height: PrimitiveTokens.Space.lg
        )
        topHighlightLayer.frame = boundsRect
        topHighlightLayer.path = fullPath
        topHighlightLayer.mask = {
            let maskLayer = CALayer()
            maskLayer.frame = topRect
            maskLayer.backgroundColor = NSColor.white.cgColor
            return maskLayer
        }()

        layer.cornerRadius = radius
    }

    private var usesDarkAppearance: Bool {
        let bestMatch = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        return bestMatch == .darkAqua || bestMatch == .vibrantDark
    }

    private var captureShellFillColor: NSColor {
        usesDarkAppearance ? PanelBackdropFamily.captureShellFillDark : PanelBackdropFamily.captureShellFillLight
    }

    private var captureShellStrokeColor: NSColor {
        usesDarkAppearance ? PanelBackdropFamily.captureShellStrokeDark : PanelBackdropFamily.captureShellStrokeLight
    }

    private var captureShellTopHighlightColor: NSColor {
        usesDarkAppearance ? PanelBackdropFamily.captureShellTopHighlightDark : PanelBackdropFamily.captureShellTopHighlightLight
    }
}

private final class CapturePanel: CaptureFloatingPanel {
    override var canBecomeKey: Bool { true }
}

private final class CaptureSuggestedTargetPanel: CaptureFloatingPanel {
    override var canBecomeKey: Bool { true }
}
