import AppKit
import Combine

@MainActor
// Runtime-owned capture panel controller.
// This file coordinates the live AppKit capture shell and must not be flattened into token-only styling work.
final class CapturePanelRuntimeViewController: NSViewController, NSTextViewDelegate {
    private let model: AppModel
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
    private var preferredPanelHeight: CGFloat = PanelMetrics.capturePanelOuterPadding * 2 + PrimitiveTokens.Size.searchFieldHeight
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingDraftExternally = false
    private var imageLoadTask: Task<Void, Never>?

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
        shellView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shellView)

        shellHeightConstraint = shellView.heightAnchor.constraint(equalToConstant: PrimitiveTokens.Size.searchFieldHeight)

        NSLayoutConstraint.activate([
            shellView.topAnchor.constraint(equalTo: view.topAnchor, constant: PanelMetrics.capturePanelOuterPadding),
            shellView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PanelMetrics.capturePanelOuterPadding),
            shellView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PanelMetrics.capturePanelOuterPadding),
            shellHeightConstraint,
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
            screenshotImageView.image = nil
            screenshotSpinner.stopAnimation(nil)
            screenshotSurface.showLoading(false)
        case .detected:
            screenshotImageView.image = nil
            screenshotSurface.showLoading(true)
            screenshotSpinner.startAnimation(nil)
        case .previewReady(_, let cacheURL, let thumbnailState):
            switch thumbnailState {
            case .loading:
                screenshotImageView.image = nil
                screenshotSurface.showLoading(true)
                screenshotSpinner.startAnimation(nil)
            case .ready:
                screenshotSurface.showLoading(false)
                screenshotSpinner.stopAnimation(nil)
                loadImage(from: cacheURL)
            }
        }

        recomputePreferredPanelHeight()
    }

    private func loadImage(from url: URL) {
        imageLoadTask?.cancel()
        imageLoadTask = Task { [weak self] in
            let image = ScreenshotDirectoryResolver.withAccessIfNeeded(to: url) { scopedURL in
                NSImage(contentsOf: scopedURL)
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self?.screenshotImageView.image = image
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

        shellHeightConstraint.constant = surfaceHeight
        preferredPanelHeight = ceil((PanelMetrics.capturePanelOuterPadding * 2) + surfaceHeight)
        onPreferredPanelHeightChange?(preferredPanelHeight)
    }

    private func handleSubmit() {
        model.beginCaptureSubmission { [weak self] in
            self?.onSubmitSuccess?()
        }
    }

    @objc
    private func handleRemoveScreenshot() {
        model.dismissPendingScreenshot()
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView === editorHost.textView else {
            return
        }

        editorHost.updateMeasuredMetrics(forceMeasure: true, emitMetrics: false)

        if !isApplyingDraftExternally, model.draftText != textView.string {
            model.draftText = textView.string
        }

        editorHost.flushPendingMetricsIfNeeded()
    }
}

private final class CapturePanelShellView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        state = .active
        blendingMode = .withinWindow
        material = .hudWindow
        wantsLayer = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        layer.cornerRadius = PrimitiveTokens.Radius.lg
        layer.masksToBounds = true

        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            layer.backgroundColor = NSColor(calibratedWhite: 0.26, alpha: 0.9).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        } else {
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
            layer.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        }

        layer.borderWidth = 1
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

    func showLoading(_ visible: Bool) {
        loadingOverlay.isHidden = !visible
    }

    private func updateAppearance() {
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
            loadingOverlay.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        } else {
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
            layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
            loadingOverlay.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor
        }
    }
}
