import AppKit
import Carbon
import QuartzCore
import SwiftUI

@MainActor
final class StackPanelController: NSObject, NSWindowDelegate {
    private enum PresentationMode: String {
        case current
        case slideOnly = "slide_only"
        case fadeOnly = "fade_only"
        case immediate

        init(environmentValue: String?) {
            guard let environmentValue,
                  let mode = PresentationMode(rawValue: environmentValue)
            else {
                // Default to a visible fade-only entrance. It keeps the stack
                // perceptible on open without reintroducing the heavier
                // offscreen frame animation path.
                self = .fadeOnly
                return
            }

            self = mode
        }

        var startsOffscreen: Bool {
            switch self {
            case .current, .slideOnly:
                true
            case .fadeOnly, .immediate:
                false
            }
        }

        var startsTransparent: Bool {
            switch self {
            case .current, .fadeOnly:
                true
            case .slideOnly, .immediate:
                false
            }
        }

        var animatesFrame: Bool {
            switch self {
            case .current, .slideOnly:
                true
            case .fadeOnly, .immediate:
                false
            }
        }

        var animatesAlpha: Bool {
            switch self {
            case .current, .fadeOnly:
                true
            case .slideOnly, .immediate:
                false
            }
        }
    }

    private let model: AppModel
    private let onEditCard: (CaptureCard) -> Void
    private var panel: StackPanel?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private(set) var isVisible = false
    private var isAnimatingClose = false
    private var hasWarmedFirstPresentation = false
    private var lastInheritedAppearanceSignature: String?
    private var pendingAppearanceRefresh = false

    var isPresentedOrTransitioning: Bool {
        isVisible || isAnimatingClose || panel?.isVisible == true
    }

    private var presentationMode: PresentationMode {
        PresentationMode(
            environmentValue: ProcessInfo.processInfo.environment["PROMPTCUE_TRACE_STACK_PRESENTATION_MODE"]
        )
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
        model.refreshCardsForExternalChanges()

        let panel = panel ?? makePanel()
        guard !panel.isVisible else {
            return
        }
        PerformanceTrace.markStackOpenPhase("panel_ready")

        // If the system theme changed while the panel was hidden,
        // AppKit may not have propagated the new effective appearance
        // to our offscreen views, so viewDidChangeEffectiveAppearance
        // never fired.  Flush the pending refresh now, before we
        // composite the first visible frame.
        if pendingAppearanceRefresh {
            refreshForInheritedAppearanceChange()
        }

        primePanelLayout(panel)
        PerformanceTrace.markStackOpenPhase("layout_primed")
        let targetFrame = onscreenPanelFrame(for: panel.frame.size)
        let presentationMode = presentationMode
        PerformanceTrace.markStackOpenPhase("presentation_mode_\(presentationMode.rawValue)")
        let initialFrame = presentationMode.startsOffscreen
            ? offscreenPanelFrame(for: targetFrame.size)
            : targetFrame
        panel.setFrame(initialFrame, display: false)
        PerformanceTrace.markStackOpenPhase(
            presentationMode.startsOffscreen
                ? "offscreen_frame_positioned"
                : "onscreen_frame_positioned"
        )
        panel.armFirstFrameCallback {
            PerformanceTrace.completeStackOpenTraceIfNeeded()
        }
        PerformanceTrace.markStackOpenPhase("first_frame_callback_armed")

        panel.alphaValue = presentationMode.startsTransparent ? 0 : 1
        PerformanceTrace.markStackOpenPhase(
            presentationMode.startsTransparent
                ? "alpha_zeroed"
                : "alpha_primed"
        )
        NSApp.activate(ignoringOtherApps: true)
        PerformanceTrace.markStackOpenPhase("app_activated")
        panel.makeKeyAndOrderFront(nil)
        PerformanceTrace.markStackOpenPhase("made_key_and_ordered_front")
        isVisible = true
        installDismissMonitors()
        PerformanceTrace.markStackOpenPhase("dismiss_monitors_installed")

        guard presentationMode.animatesAlpha || presentationMode.animatesFrame else {
            return
        }

        // Allow one run-loop cycle for NSVisualEffectView materials to
        // composite, then apply the selected presentation choreography.
        DispatchQueue.main.async { [weak panel] in
            guard let panel else { return }
            PerformanceTrace.markStackOpenPhase("animation_dispatch")
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PrimitiveTokens.Motion.stackOpen
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)

                if presentationMode.animatesAlpha {
                    panel.animator().alphaValue = 1
                }

                if presentationMode.animatesFrame {
                    panel.animator().setFrame(targetFrame, display: true)
                }
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
            context.duration = PrimitiveTokens.Motion.stackClose
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offscreenPanelFrame(for: panel.frame.size), display: true)
        } completionHandler: { [weak self, weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
            self?.isAnimatingClose = false
        }
    }

    /// Called synchronously when the system theme notification arrives,
    /// *before* AppKit has propagated the new effective appearance.
    /// Sets a flag so that the next `show()` or deferred
    /// `refreshForInheritedAppearanceChange()` picks up the change.
    func markAppearanceDirty() {
        pendingAppearanceRefresh = true
    }

    func refreshForInheritedAppearanceChange() {
        pendingAppearanceRefresh = false

        // Always clear local overrides — they pin the window to a
        // stale appearance and prevent system inheritance.
        panel?.appearance = nil
        panel?.contentView?.appearance = nil
        panel?.contentViewController?.view.appearance = nil

        let appearanceSignature = Self.appearanceSignature(
            for: panel?.effectiveAppearance ?? NSApp.effectiveAppearance
        )
        let didChange = lastInheritedAppearanceSignature != appearanceSignature
        lastInheritedAppearanceSignature = appearanceSignature

        panel?.invalidateShadow()
        panel?.contentView?.needsDisplay = true
        panel?.contentViewController?.view.needsDisplay = true

        // Always tell the content VC to refresh — it owns its own
        // deduplication and the cost of a no-op pass is negligible
        // compared to displaying stale theme colors.
        (panel?.contentViewController as? StackPanelContentViewController<CardStackView>)?.refreshAppearance(forceRebuild: didChange)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !hasVisibleAuxiliaryPresentation() else {
            return
        }
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
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
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
        panel.contentViewController = StackPanelContentViewController(rootViewBuilder: { [self] in
            CardStackView(
                model: self.model,
                onBackdropTap: { [weak self] in
                    self?.close()
                },
                onDismissAfterCopy: { [weak self] in
                    self?.close(commitDeferredCopies: false)
                },
                onEditCard: { [weak self] card in
                    self?.onEditCard(card)
                },
                onDeleteCard: { [weak self] card in
                    self?.model.delete(card: card)
                }
            )
        })
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

    private static func appearanceSignature(for appearance: NSAppearance?) -> String {
        appearance?.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])?.rawValue ?? "unspecified"
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

        let eventWindow = event.window
        if shouldIgnoreMouseEvent(for: eventWindow, panel: panel) {
            return
        }

        let clickPoint = eventWindow?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        closeIfMouseOutsidePanel(at: clickPoint)
    }

    private func closeIfMouseOutsidePanel() {
        guard let panel, isVisible else {
            return
        }

        closeIfMouseOutsidePanel(at: NSEvent.mouseLocation)
    }

    private func closeIfMouseOutsidePanel(at mouseLocation: NSPoint) {
        guard let panel, isVisible else {
            return
        }

        if panel.frame.contains(mouseLocation) {
            return
        }

        if relatedAuxiliaryWindows(for: panel).contains(where: { $0.frame.contains(mouseLocation) }) {
            return
        }

        if hasVisiblePopoverUnderPoint(mouseLocation) {
            return
        }

        if !panel.frame.contains(mouseLocation) {
            close()
        }
    }

    private func shouldIgnoreMouseEvent(for window: NSWindow?, panel: NSWindow) -> Bool {
        if window == nil || isAssociatedAuxiliaryWindow(window, panel: panel) {
            return true
        }

        if isPopoverWindow(window) {
            return true
        }

        if window === panel {
            return true
        }

        return false
    }

    private func hasVisiblePopoverUnderPoint(_ point: NSPoint) -> Bool {
        guard let panel else {
            return false
        }

        return visiblePopoverWindows(for: panel).contains { popoverWindow in
            popoverWindow.frame.contains(point)
        }
    }

    private func visiblePopoverWindows(for panel: NSWindow) -> [NSWindow] {
        NSApp.windows
            .filter { window in
                guard window.isVisible else {
                    return false
                }

                if window === panel {
                    return false
                }

                if isPopoverWindow(window) {
                    return true
                }

                return false
            }
    }

    private func isPopoverWindow(_ window: NSWindow?) -> Bool {
        guard let window else {
            return false
        }

        let className = NSStringFromClass(type(of: window))
        return className.localizedStandardContains("Popover")
    }

    private func hasVisibleAuxiliaryPresentation() -> Bool {
        guard let panel else {
            return false
        }

        return relatedAuxiliaryWindows(for: panel).contains(where: \.isVisible)
    }

    private func relatedAuxiliaryWindows(for panel: NSWindow) -> [NSWindow] {
        var relatedWindows: [NSWindow] = []

        if let childWindows = panel.childWindows {
            relatedWindows.append(contentsOf: childWindows)
        }

        if let keyWindow = NSApp.keyWindow, isAssociatedAuxiliaryWindow(keyWindow, panel: panel) {
            relatedWindows.append(keyWindow)
        }

        if let mainWindow = NSApp.mainWindow, isAssociatedAuxiliaryWindow(mainWindow, panel: panel) {
            relatedWindows.append(mainWindow)
        }

        var seen = Set<ObjectIdentifier>()
        return relatedWindows.filter { window in
            let identifier = ObjectIdentifier(window)
            if seen.contains(identifier) {
                return false
            }
            seen.insert(identifier)
            return true
        }
    }

    private func isAssociatedAuxiliaryWindow(_ window: NSWindow?, panel: NSWindow) -> Bool {
        guard let window, window !== panel else {
            return false
        }

        if window.parent === panel || window.sheetParent === panel {
            return true
        }

        if panel.childWindows?.contains(where: { $0 === window }) == true {
            return true
        }

        if let parent = window.parent, parent === panel {
            return true
        }

        return false
    }
}

private final class StackPanelContentViewController<Content: View>: NSViewController {
    private let shellView = StackPanelShellView()
    private let rootViewBuilder: () -> Content
    private let hostingController: NSHostingController<Content>
    private var lastAppearanceSignature: String?

    init(rootViewBuilder: @escaping () -> Content) {
        self.rootViewBuilder = rootViewBuilder
        self.hostingController = NSHostingController(rootView: rootViewBuilder())
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = StackPanelAppearanceAwareView()
        rootView.onEffectiveAppearanceChange = { [weak self] in
            self?.refreshAppearance()
        }
        view = rootView
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        shellView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shellView)

        addChild(hostingController)
        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor.clear.cgColor
        shellView.addSubview(hostedView)

        NSLayoutConstraint.activate([
            shellView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shellView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shellView.topAnchor.constraint(equalTo: view.topAnchor),
            shellView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostedView.leadingAnchor.constraint(equalTo: shellView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: shellView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: shellView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: shellView.bottomAnchor),
        ])

        refreshAppearance()
    }

    func refreshAppearance(forceRebuild: Bool = false) {
        let appearanceSignature = Self.appearanceSignature(for: view.window?.effectiveAppearance ?? view.effectiveAppearance)
        let didChangeAppearance = lastAppearanceSignature != nil && lastAppearanceSignature != appearanceSignature
        lastAppearanceSignature = appearanceSignature
        shellView.refreshAppearance()

        // Rebuild the SwiftUI view hierarchy whenever the effective
        // appearance actually changed, OR when the caller detected a
        // change that our local signature comparison missed (e.g. the
        // panel was offscreen and effectiveAppearance lagged behind).
        if didChangeAppearance || forceRebuild {
            hostingController.rootView = rootViewBuilder()
            hostingController.view.layer?.contents = nil
            hostingController.view.needsLayout = true
            hostingController.view.layoutSubtreeIfNeeded()
        }
        view.needsDisplay = true
        shellView.needsDisplay = true
        hostingController.view.needsDisplay = true
    }

    private static func appearanceSignature(for appearance: NSAppearance?) -> String {
        appearance?.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])?.rawValue ?? "unspecified"
    }
}

private final class StackPanelAppearanceAwareView: NSView {
    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}

private final class StackPanelShellView: NSView {
    private let effectView = NSVisualEffectView()
    private let overlayView = NSView()
    private let fillLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private let borderLayer = CAShapeLayer()
    private let topHighlightLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Keep the backdrop itself rounded, but allow card/plate shadows near
        // the panel edge to render without getting clipped by the shell layer.
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor

        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.material = .underWindowBackground
        effectView.wantsLayer = true
        effectView.layer?.masksToBounds = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.wantsLayer = true
        overlayView.layer?.masksToBounds = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor
        overlayView.layer?.addSublayer(fillLayer)
        overlayView.layer?.addSublayer(gradientLayer)
        overlayView.layer?.addSublayer(borderLayer)
        overlayView.layer?.addSublayer(topHighlightLayer)

        addSubview(effectView)
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
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
        let usesDarkAppearance = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
            .map { $0 == .darkAqua || $0 == .vibrantDark } ?? false

        effectView.blendingMode = .behindWindow
        effectView.material = usesDarkAppearance
            ? PanelBackdropFamily.stackShellMaterialDark
            : PanelBackdropFamily.stackShellMaterialLight
        effectView.alphaValue = usesDarkAppearance
            ? PanelBackdropFamily.stackShellBlurOpacityDark
            : PanelBackdropFamily.stackShellBlurOpacityLight

        fillLayer.fillColor = (
            usesDarkAppearance
                ? PanelBackdropFamily.stackShellFillDark
                : PanelBackdropFamily.stackShellFillLight
        ).cgColor
        gradientLayer.colors = [
            (
                usesDarkAppearance
                    ? PanelBackdropFamily.stackShellGradientTopDark
                    : PanelBackdropFamily.stackShellGradientTopLight
            ).cgColor,
            (
                usesDarkAppearance
                    ? PanelBackdropFamily.stackShellGradientBottomDark
                    : PanelBackdropFamily.stackShellGradientBottomLight
            ).cgColor,
        ]
        borderLayer.strokeColor = (
            usesDarkAppearance
                ? PanelBackdropFamily.stackShellStrokeDark
                : PanelBackdropFamily.stackShellStrokeLight
        ).cgColor
        topHighlightLayer.strokeColor = (
            usesDarkAppearance
                ? PanelBackdropFamily.stackShellTopHighlightDark
                : PanelBackdropFamily.stackShellTopHighlightLight
        ).cgColor

        let tintOpacity = usesDarkAppearance
            ? PanelBackdropFamily.stackShellTintOpacityDark
            : PanelBackdropFamily.stackShellTintOpacityLight
        fillLayer.opacity = Float(tintOpacity)
        gradientLayer.opacity = Float(tintOpacity)
        borderLayer.opacity = Float(tintOpacity)
        topHighlightLayer.opacity = Float(tintOpacity)
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        borderLayer.lineWidth = PrimitiveTokens.Stroke.subtle
        borderLayer.fillColor = NSColor.clear.cgColor
        topHighlightLayer.lineWidth = PrimitiveTokens.Stroke.subtle
        topHighlightLayer.fillColor = NSColor.clear.cgColor

        updateShape()
    }

    private func updateShape() {
        guard let layer,
              let effectLayer = effectView.layer,
              let overlayLayer = overlayView.layer
        else {
            return
        }

        let boundsRect = bounds
        let radius = PrimitiveTokens.Radius.lg
        let fullPath = CGPath(
            roundedRect: boundsRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        effectLayer.cornerRadius = radius
        effectLayer.masksToBounds = true
        overlayLayer.cornerRadius = radius
        overlayLayer.masksToBounds = true
        fillLayer.frame = boundsRect
        fillLayer.path = fullPath
        gradientLayer.frame = boundsRect
        gradientLayer.cornerRadius = radius
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

        let maskLayer = CALayer()
        maskLayer.frame = topRect
        maskLayer.backgroundColor = NSColor.white.cgColor
        topHighlightLayer.mask = maskLayer

        layer.cornerRadius = radius
        layer.backgroundColor = NSColor.clear.cgColor
    }
}

private final class StackPanel: NSPanel {
    var onCancel: (() -> Void)?
    private var firstFrameCallback: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Always accept mouse-moved events so hover tracking works
    // even if AppKit tries to disable them during panel transitions.
    override var acceptsMouseMovedEvents: Bool {
        get { true }
        set {}
    }

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
