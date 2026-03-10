import AppKit
import Combine

struct CapturePanelPreferredHeightUpdateMetrics {
    let totalMilliseconds: Double
    let averageMicroseconds: Double
    let emittedHeightCount: Int
    let skippedHeightCount: Int
}

enum CapturePanelPreferredHeightGuard {
    static let tolerance: CGFloat = 0.5

    static func shouldEmit(
        currentHeight: CGFloat,
        targetHeight: CGFloat,
        tolerance: CGFloat = tolerance
    ) -> Bool {
        abs(currentHeight - targetHeight) > tolerance
    }

    static func benchmark(
        initialHeight: CGFloat,
        targetHeights: [CGFloat],
        guarded: Bool,
        emitter: (CGFloat) -> Void
    ) -> CapturePanelPreferredHeightUpdateMetrics {
        var currentHeight = initialHeight
        var emittedHeightCount = 0
        var skippedHeightCount = 0

        let startedAt = CFAbsoluteTimeGetCurrent()

        for targetHeight in targetHeights {
            if guarded,
               !shouldEmit(
                currentHeight: currentHeight,
                targetHeight: targetHeight
               ) {
                currentHeight = targetHeight
                skippedHeightCount += 1
                continue
            }

            emitter(targetHeight)
            currentHeight = targetHeight
            emittedHeightCount += 1
        }

        let totalMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        let operationCount = max(targetHeights.count, 1)

        return CapturePanelPreferredHeightUpdateMetrics(
            totalMilliseconds: totalMilliseconds,
            averageMicroseconds: totalMilliseconds * 1_000 / Double(operationCount),
            emittedHeightCount: emittedHeightCount,
            skippedHeightCount: skippedHeightCount
        )
    }
}

@MainActor
// Runtime-owned capture panel controller.
// This file coordinates the live AppKit capture shell and must not be flattened into token-only styling work.
final class CapturePanelRuntimeViewController: NSViewController, NSTextViewDelegate {
    private static let previewImageCache = CapturePreviewImageCache()

    private let model: AppModel
    private let shadowHostView = CapturePanelShadowHostView()
    private let shadowCasterView = CapturePanelShadowCasterView()
    private let shellView = CapturePanelShellView()
    private let contentStack = NSStackView()
    private let screenshotContainer = NSView()
    private let screenshotSurface = CaptureScreenshotSurfaceView()
    private let screenshotImageView = NSImageView()
    private let screenshotSpinner = NSProgressIndicator()
    private let removeScreenshotButton = NSButton()
    private let editorHost = CaptureEditorRuntimeHostView()

    private var shellHeightConstraint: NSLayoutConstraint!
    private var screenshotHeightConstraint: NSLayoutConstraint!
    private var editorHeightConstraint: NSLayoutConstraint!
    private var preferredPanelHeight: CGFloat =
        PanelMetrics.capturePanelShadowTopInset
        + PrimitiveTokens.Size.searchFieldHeight
        + PanelMetrics.capturePanelShadowBottomInset
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingDraftExternally = false
    private var imageLoadTask: Task<Void, Never>?
    private var pendingDraftSyncWorkItem: DispatchWorkItem?
    private var pendingDraftSyncText: String?
    private var displayedPreviewImageKey: String?

    var onPreferredPanelHeightChange: ((CGFloat) -> Void)?
    var onSubmitSuccess: (() -> Void)?
    var onCancelRequest: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        imageLoadTask?.cancel()
        pendingDraftSyncWorkItem?.cancel()
        cancellables.removeAll()
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        buildViewHierarchy()
        bindModel()
    }

    func prepareForPresentation() {
        loadViewIfNeeded()
        applyDraftText(model.draftText, forceScrollToSelection: !model.draftText.isEmpty)
        applyRecentScreenshotState(model.recentScreenshotState)
        applySubmittingState(model.isSubmittingCapture)
        recomputePreferredPanelHeight()
    }

    func focusEditorIfPossible() {
        editorHost.focusIfPossible()
    }

    var currentPreferredPanelHeight: CGFloat {
        preferredPanelHeight
    }

    private func buildViewHierarchy() {
        shadowHostView.translatesAutoresizingMaskIntoConstraints = false
        shadowCasterView.translatesAutoresizingMaskIntoConstraints = false
        shellView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shadowHostView)
        shadowHostView.addSubview(shadowCasterView)
        shadowHostView.addSubview(shellView)

        shellHeightConstraint = shadowHostView.heightAnchor.constraint(equalToConstant: PrimitiveTokens.Size.searchFieldHeight)

        NSLayoutConstraint.activate([
            shadowHostView.topAnchor.constraint(equalTo: view.topAnchor, constant: PanelMetrics.capturePanelShadowTopInset),
            shadowHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PanelMetrics.capturePanelOuterPadding),
            shadowHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PanelMetrics.capturePanelOuterPadding),
            shellHeightConstraint,
            shadowCasterView.leadingAnchor.constraint(equalTo: shadowHostView.leadingAnchor),
            shadowCasterView.trailingAnchor.constraint(equalTo: shadowHostView.trailingAnchor),
            shadowCasterView.topAnchor.constraint(equalTo: shadowHostView.topAnchor),
            shadowCasterView.bottomAnchor.constraint(equalTo: shadowHostView.bottomAnchor),
            shellView.leadingAnchor.constraint(equalTo: shadowHostView.leadingAnchor),
            shellView.trailingAnchor.constraint(equalTo: shadowHostView.trailingAnchor),
            shellView.topAnchor.constraint(equalTo: shadowHostView.topAnchor),
            shellView.bottomAnchor.constraint(equalTo: shadowHostView.bottomAnchor),
        ])

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = PrimitiveTokens.Space.sm
        shellView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: shellView.leadingAnchor, constant: PanelMetrics.captureSurfaceInnerPadding),
            contentStack.trailingAnchor.constraint(equalTo: shellView.trailingAnchor, constant: -PanelMetrics.captureSurfaceInnerPadding),
            contentStack.topAnchor.constraint(equalTo: shellView.topAnchor, constant: PanelMetrics.captureSurfaceTopPadding),
            contentStack.bottomAnchor.constraint(equalTo: shellView.bottomAnchor, constant: -PanelMetrics.captureSurfaceBottomPadding),
        ])

        editorHost.translatesAutoresizingMaskIntoConstraints = false
        editorHost.textView.delegate = self
        editorHost.configureRuntime(
            text: model.draftText,
            placeholder: "Type and press Enter to save",
            maxContentHeight: CaptureRuntimeMetrics.editorMaxHeight,
            onMetricsChange: { [weak self] metrics in
                self?.applyEditorMetrics(metrics)
            },
            onSubmit: { [weak self] in
                self?.handleSubmit()
            },
            onCancel: { [weak self] in
                self?.onCancelRequest?()
            }
        )
        contentStack.addArrangedSubview(editorHost)

        screenshotContainer.translatesAutoresizingMaskIntoConstraints = false
        screenshotContainer.isHidden = true
        contentStack.addArrangedSubview(screenshotContainer)

        screenshotHeightConstraint = screenshotContainer.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            screenshotContainer.widthAnchor.constraint(equalToConstant: PrimitiveTokens.Size.captureAttachmentPreviewSize),
            screenshotHeightConstraint,
        ])

        screenshotSurface.translatesAutoresizingMaskIntoConstraints = false
        screenshotContainer.addSubview(screenshotSurface)
        NSLayoutConstraint.activate([
            screenshotSurface.leadingAnchor.constraint(equalTo: screenshotContainer.leadingAnchor),
            screenshotSurface.topAnchor.constraint(equalTo: screenshotContainer.topAnchor),
            screenshotSurface.widthAnchor.constraint(equalToConstant: PrimitiveTokens.Size.captureAttachmentPreviewSize),
            screenshotSurface.heightAnchor.constraint(equalToConstant: PrimitiveTokens.Size.captureAttachmentPreviewSize),
        ])

        screenshotImageView.translatesAutoresizingMaskIntoConstraints = false
        screenshotImageView.imageScaling = .scaleAxesIndependently
        screenshotImageView.wantsLayer = true
        screenshotImageView.layer?.cornerRadius = PrimitiveTokens.Radius.md
        screenshotImageView.layer?.masksToBounds = true
        screenshotSurface.addSubview(screenshotImageView)
        NSLayoutConstraint.activate([
            screenshotImageView.leadingAnchor.constraint(equalTo: screenshotSurface.leadingAnchor),
            screenshotImageView.trailingAnchor.constraint(equalTo: screenshotSurface.trailingAnchor),
            screenshotImageView.topAnchor.constraint(equalTo: screenshotSurface.topAnchor),
            screenshotImageView.bottomAnchor.constraint(equalTo: screenshotSurface.bottomAnchor),
        ])

        screenshotSpinner.translatesAutoresizingMaskIntoConstraints = false
        screenshotSpinner.controlSize = .small
        screenshotSpinner.style = .spinning
        screenshotSurface.addSubview(screenshotSpinner)
        NSLayoutConstraint.activate([
            screenshotSpinner.centerXAnchor.constraint(equalTo: screenshotSurface.centerXAnchor),
            screenshotSpinner.centerYAnchor.constraint(equalTo: screenshotSurface.centerYAnchor),
        ])

        removeScreenshotButton.translatesAutoresizingMaskIntoConstraints = false
        removeScreenshotButton.bezelStyle = .regularSquare
        removeScreenshotButton.isBordered = false
        removeScreenshotButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove recent screenshot")
        removeScreenshotButton.contentTintColor = .labelColor
        removeScreenshotButton.target = self
        removeScreenshotButton.action = #selector(handleRemoveScreenshot)
        screenshotContainer.addSubview(removeScreenshotButton)
        NSLayoutConstraint.activate([
            removeScreenshotButton.topAnchor.constraint(equalTo: screenshotContainer.topAnchor, constant: PrimitiveTokens.Space.xs),
            removeScreenshotButton.trailingAnchor.constraint(equalTo: screenshotContainer.trailingAnchor, constant: -PrimitiveTokens.Space.xs),
        ])
        editorHeightConstraint = editorHost.heightAnchor.constraint(equalToConstant: CaptureRuntimeMetrics.editorMinimumVisibleHeight)
        editorHeightConstraint.isActive = true
    }

    private func bindModel() {
        model.$recentScreenshotState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.applyRecentScreenshotState(state)
            }
            .store(in: &cancellables)

        model.$draftText
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] draftText in
                self?.applyDraftText(draftText)
            }
            .store(in: &cancellables)

        model.$isSubmittingCapture
            .receive(on: RunLoop.main)
            .sink { [weak self] isSubmitting in
                self?.applySubmittingState(isSubmitting)
            }
            .store(in: &cancellables)
    }

    private func applyDraftText(_ text: String, forceScrollToSelection: Bool = false) {
        guard !isApplyingDraftExternally else {
            return
        }

        guard editorHost.textView.string != text else {
            return
        }

        isApplyingDraftExternally = true
        editorHost.applyExternalText(text, forceScrollToSelection: forceScrollToSelection, forceMeasure: true)
        isApplyingDraftExternally = false
    }

    private func applyEditorMetrics(_ metrics: CaptureEditorMetrics) {
        editorHeightConstraint.constant = max(CaptureRuntimeMetrics.editorMinimumVisibleHeight, metrics.visibleHeight)
        recomputePreferredPanelHeight()
    }

    private func applySubmittingState(_ isSubmitting: Bool) {
        editorHost.textView.isEditable = !isSubmitting
        removeScreenshotButton.isEnabled = !isSubmitting
        if isSubmitting {
            screenshotSpinner.startAnimation(nil)
        } else if !model.showsRecentScreenshotPlaceholder {
            screenshotSpinner.stopAnimation(nil)
        }
    }

    private func applyRecentScreenshotState(_ state: RecentScreenshotState) {
        let shouldShow = model.showsRecentScreenshotSlot
        screenshotContainer.isHidden = !shouldShow
        screenshotHeightConstraint.constant = shouldShow ? PrimitiveTokens.Size.captureAttachmentPreviewSize : 0

        switch state {
        case .idle, .expired, .consumed:
            imageLoadTask?.cancel()
            displayedPreviewImageKey = nil
            screenshotImageView.image = nil
            screenshotSpinner.stopAnimation(nil)
            screenshotSurface.showLoading(false)
        case .detected:
            imageLoadTask?.cancel()
            displayedPreviewImageKey = nil
            screenshotImageView.image = nil
            screenshotSurface.showLoading(true)
            screenshotSpinner.startAnimation(nil)
        case .previewReady(let sessionID, let cacheURL, let thumbnailState):
            switch thumbnailState {
            case .loading:
                imageLoadTask?.cancel()
                displayedPreviewImageKey = nil
                screenshotImageView.image = nil
                screenshotSurface.showLoading(true)
                screenshotSpinner.startAnimation(nil)
            case .ready:
                loadImage(from: cacheURL, sessionID: sessionID)
            }
        }

        recomputePreferredPanelHeight()
    }

    private func loadImage(from url: URL, sessionID: UUID) {
        let cacheKey = CapturePreviewImageCache.cacheKey(
            sessionID: sessionID,
            cacheURL: url
        )

        if displayedPreviewImageKey == cacheKey, screenshotImageView.image != nil {
            screenshotSurface.showLoading(false)
            screenshotSpinner.stopAnimation(nil)
            return
        }

        if let cachedImage = Self.previewImageCache.image(forKey: cacheKey) {
            imageLoadTask?.cancel()
            displayedPreviewImageKey = cacheKey
            screenshotImageView.image = cachedImage
            screenshotSurface.showLoading(false)
            screenshotSpinner.stopAnimation(nil)
            return
        }

        imageLoadTask?.cancel()
        displayedPreviewImageKey = cacheKey
        screenshotImageView.image = nil
        screenshotSurface.showLoading(true)
        screenshotSpinner.startAnimation(nil)

        imageLoadTask = Task.detached(priority: .utility) { [weak self, cacheKey, url] in
            let image = CapturePreviewImageCache.loadUncachedImage(from: url)

            guard !Task.isCancelled else {
                return
            }

            if let image {
                Self.previewImageCache.store(image, forKey: cacheKey)
            }

            await MainActor.run {
                guard !Task.isCancelled else {
                    return
                }

                let resolvedImage = Self.previewImageCache.image(forKey: cacheKey)
                guard let self, self.displayedPreviewImageKey == cacheKey else {
                    return
                }

                self.screenshotImageView.image = resolvedImage
                self.screenshotSurface.showLoading(false)
                self.screenshotSpinner.stopAnimation(nil)
            }
        }
    }

    private func recomputePreferredPanelHeight() {
        let screenshotHeight = screenshotContainer.isHidden ? 0 : (PrimitiveTokens.Size.captureAttachmentPreviewSize + PrimitiveTokens.Space.sm)
        let editorHeight = max(editorHost.currentMetrics.visibleHeight, CaptureRuntimeMetrics.editorMinimumVisibleHeight)
        let surfaceHeight = max(
            PrimitiveTokens.Size.searchFieldHeight,
            editorHeight + screenshotHeight + PanelMetrics.captureSurfaceTopPadding + PanelMetrics.captureSurfaceBottomPadding
        )

        let nextPreferredPanelHeight = ceil(
            PanelMetrics.capturePanelShadowTopInset
            + surfaceHeight
            + PanelMetrics.capturePanelShadowBottomInset
        )
        if abs(shellHeightConstraint.constant - surfaceHeight) > CapturePanelPreferredHeightGuard.tolerance {
            shellHeightConstraint.constant = surfaceHeight
        }

        guard CapturePanelPreferredHeightGuard.shouldEmit(
            currentHeight: preferredPanelHeight,
            targetHeight: nextPreferredPanelHeight
        ) else {
            return
        }

        preferredPanelHeight = nextPreferredPanelHeight
        onPreferredPanelHeightChange?(preferredPanelHeight)
    }

    private func handleSubmit() {
        flushDraftSyncIfNeeded(forceText: editorHost.textView.string)
        model.beginCaptureSubmission { [weak self] in
            self?.onSubmitSuccess?()
        }
    }

    @objc
    private func handleRemoveScreenshot() {
        model.dismissPendingScreenshot()
    }

    func persistDraftIfNeeded() {
        flushDraftSyncIfNeeded(forceText: editorHost.textView.string)
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView === editorHost.textView else {
            return
        }

        let previousDraftCount = model.draftText.utf16.count
        let currentDraftText = textView.string
        let currentDraftCount = currentDraftText.utf16.count
        let isGrowingDraft = currentDraftCount >= previousDraftCount
        let shouldSkipMeasurement = editorHost.currentMetrics.isScrollable && isGrowingDraft

        if !isApplyingDraftExternally {
            scheduleDraftSync(currentDraftText)
        }

        guard !shouldSkipMeasurement else {
            return
        }

        // Keep wrap and early multiline growth synchronous so the shell grows
        // in the same interaction frame. Once the editor is already clamped
        // and scrollable, we can afford to coalesce follow-up measurements.
        if editorHost.currentMetrics.isScrollable {
            editorHost.scheduleMeasuredMetrics()
        } else {
            editorHost.resolvePreferredHeight(forceMeasure: true)
        }
    }

    private func scheduleDraftSync(_ text: String) {
        pendingDraftSyncText = text
        pendingDraftSyncWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingDraftSyncWorkItem = nil
            let resolvedText = self.pendingDraftSyncText ?? text
            self.pendingDraftSyncText = nil
            if self.model.draftText != resolvedText {
                self.model.draftText = resolvedText
            }
        }

        pendingDraftSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func flushDraftSyncIfNeeded(forceText: String? = nil) {
        pendingDraftSyncWorkItem?.cancel()
        pendingDraftSyncWorkItem = nil

        let resolvedText = forceText ?? pendingDraftSyncText ?? editorHost.textView.string
        pendingDraftSyncText = nil

        if !isApplyingDraftExternally, model.draftText != resolvedText {
            model.draftText = resolvedText
        }
    }
}

final class CapturePreviewImageCache {
    private let storage = NSCache<NSString, NSImage>()

    init(countLimit: Int = 12) {
        storage.countLimit = countLimit
    }

    func image(forKey key: String) -> NSImage? {
        storage.object(forKey: key as NSString)
    }

    func store(_ image: NSImage, forKey key: String) {
        storage.setObject(image, forKey: key as NSString)
    }

    func removeAllObjects() {
        storage.removeAllObjects()
    }

    func cachedImage(
        sessionID: UUID,
        cacheURL: URL,
        loader: (URL) -> NSImage?
    ) -> NSImage? {
        let cacheKey = Self.cacheKey(sessionID: sessionID, cacheURL: cacheURL)
        if let cachedImage = image(forKey: cacheKey) {
            return cachedImage
        }

        guard let decodedImage = loader(cacheURL) else {
            return nil
        }

        store(decodedImage, forKey: cacheKey)
        return decodedImage
    }

    static func cacheKey(sessionID: UUID, cacheURL: URL) -> String {
        "\(sessionID.uuidString.lowercased())|\(cacheURL.standardizedFileURL.path)"
    }

    static func loadUncachedImage(from url: URL) -> NSImage? {
        ScreenshotDirectoryResolver.withAccessIfNeeded(to: url) { scopedURL in
            NSImage(contentsOf: scopedURL)
        }
    }
}

private final class CapturePanelShadowHostView: NSView {
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

private final class CapturePanelShadowCasterView: NSView {
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

    private func updateAppearance() {
        ambientLayer.fillColor = NSColor.white.withAlphaComponent(0.02).cgColor
        ambientLayer.shadowColor = NSColor(SemanticTokens.Shadow.captureShellAmbient).cgColor
        ambientLayer.shadowOpacity = Float(PrimitiveTokens.Shadow.captureAmbientOpacity)
        ambientLayer.shadowRadius = PrimitiveTokens.Shadow.captureAmbientBlur / 2
        // Light is assumed to come from above, so both ambient and key shadow
        // should bias downward instead of blooming symmetrically around the shell.
        ambientLayer.shadowOffset = CGSize(width: PrimitiveTokens.Shadow.zeroX, height: -PrimitiveTokens.Shadow.captureAmbientY)

        keyLayer.fillColor = NSColor.white.withAlphaComponent(0.02).cgColor
        keyLayer.shadowColor = NSColor(SemanticTokens.Shadow.captureShellKey).cgColor
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
}

private final class CapturePanelShellView: NSVisualEffectView {
    private let fillLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let topHighlightLayer = CAShapeLayer()

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

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

    override func layout() {
        super.layout()
        updateShape()
    }

    private func updateAppearance() {
        guard let layer else { return }

        material = usesDarkAppearance ? .menu : .hudWindow

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

        let topRect = CGRect(x: 0, y: max(0, boundsRect.height - PrimitiveTokens.Space.lg), width: boundsRect.width, height: PrimitiveTokens.Space.lg)
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
        let resolvedAppearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        let bestMatch = resolvedAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        return bestMatch == .darkAqua || bestMatch == .vibrantDark
    }

    private var captureShellFillColor: NSColor {
        NSColor(SemanticTokens.Surface.captureShellFill)
    }

    private var captureShellStrokeColor: NSColor {
        NSColor(SemanticTokens.Surface.captureShellStroke)
    }

    private var captureShellTopHighlightColor: NSColor {
        NSColor(SemanticTokens.Surface.captureShellTopHighlight)
    }
}

private final class CaptureScreenshotSurfaceView: NSView {
    private let loadingOverlay = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PrimitiveTokens.Radius.md
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.wantsLayer = true
        addSubview(loadingOverlay)
        NSLayoutConstraint.activate([
            loadingOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            loadingOverlay.topAnchor.constraint(equalTo: topAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        showLoading(false)
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

    func showLoading(_ visible: Bool) {
        loadingOverlay.isHidden = !visible
    }

    private func updateAppearance() {
        let resolvedAppearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        let bestMatch = resolvedAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        let isDark = bestMatch == .darkAqua || bestMatch == .vibrantDark
        layer?.backgroundColor = (isDark
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.white.withAlphaComponent(0.68)).cgColor
        layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.10)).cgColor
        loadingOverlay.layer?.backgroundColor = (isDark
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.white.withAlphaComponent(0.44)).cgColor
    }
}
