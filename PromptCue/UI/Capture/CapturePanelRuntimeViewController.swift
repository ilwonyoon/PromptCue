import AppKit
import Combine
import PromptCueCore
import SwiftUI

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
    private static let captureSurfaceVerticalInset = AppUIConstants.captureSurfaceInnerPadding

    private let model: AppModel
    private let shadowHostView = CapturePanelShadowHostView()
    private let shadowCasterView = CapturePanelShadowCasterView()
    private let shellView = CapturePanelShellView()
    private let contentStack = NSStackView()
    private let screenshotContainer = NSView()
    private let screenshotSurface = CaptureScreenshotSurfaceView()
    private let screenshotImageView = CaptureScreenshotPreviewView()
    private let screenshotSpinner = NSProgressIndicator()
    private let removeScreenshotButton = HoverTintButton()
    private let editorHost = CaptureEditorRuntimeHostView()
    private let inlineTagSuggestionView: NSHostingView<CaptureInlineTagSuggestionView>
    private let bootstrapSurfaceHeight: CGFloat

    private var shellHeightConstraint: NSLayoutConstraint!
    private var screenshotHeightConstraint: NSLayoutConstraint!
    private var editorHeightConstraint: NSLayoutConstraint!
    private var preferredPanelHeight: CGFloat
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingDraftExternally = false
    private var imageLoadTask: Task<Void, Never>?
    private var pendingDraftSyncWorkItem: DispatchWorkItem?
    private var pendingDraftSyncText: String?
    private var displayedPreviewImageKey: String?
    private var lastAppearanceSignature: String?
    private var inlineTagSuggestions: [String] = []
    private var selectedInlineTagSuggestionIndex = 0
    private var lastInlineTagQueryValue: String?

    var onPreferredPanelHeightChange: ((CGFloat) -> Void)?
    var onSubmitSuccess: (() -> Void)?
    var onCancelRequest: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        self.inlineTagSuggestionView = NSHostingView(
            rootView: CaptureInlineTagSuggestionView(
                suggestions: [],
                selectedIndex: 0,
                onSelectSuggestion: { _ in }
            )
        )
        self.bootstrapSurfaceHeight = Self.minimumSurfaceHeight(
            editorHeight: CaptureRuntimeMetrics.editorMinimumVisibleHeight,
            inlineTagSuggestionHeight: 0,
            screenshotHeight: 0
        )
        self.preferredPanelHeight = Self.preferredPanelHeight(
            forSurfaceHeight: self.bootstrapSurfaceHeight
        )
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
        let rootView = CapturePanelAppearanceAwareView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: AppUIConstants.capturePanelWidth,
                height: preferredPanelHeight
            )
        )
        rootView.onEffectiveAppearanceChange = { [weak self] in
            self?.refreshAppearance()
        }
        view = rootView
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

    func refreshAppearance() {
        let appearanceSignature = Self.appearanceSignature(for: view.window?.effectiveAppearance ?? view.effectiveAppearance)
        let didChangeAppearance = lastAppearanceSignature != nil && lastAppearanceSignature != appearanceSignature
        lastAppearanceSignature = appearanceSignature

        editorHost.refreshAppearance()
        view.needsDisplay = true
        shadowCasterView.refreshAppearance()
        shellView.refreshAppearance()
        screenshotSurface.refreshAppearance()
        if didChangeAppearance {
            view.layer?.contents = nil
            inlineTagSuggestionView.rootView = makeInlineTagSuggestionView()
            inlineTagSuggestionView.layer?.contents = nil
        }
        inlineTagSuggestionView.needsDisplay = true
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

        shellHeightConstraint = shadowHostView.heightAnchor.constraint(equalToConstant: bootstrapSurfaceHeight)

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
            contentStack.topAnchor.constraint(equalTo: shellView.topAnchor, constant: Self.captureSurfaceVerticalInset),
            contentStack.bottomAnchor.constraint(equalTo: shellView.bottomAnchor, constant: -Self.captureSurfaceVerticalInset),
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
        screenshotSurface.addSubview(screenshotImageView)
        NSLayoutConstraint.activate([
            screenshotImageView.leadingAnchor.constraint(equalTo: screenshotSurface.leadingAnchor),
            screenshotImageView.trailingAnchor.constraint(equalTo: screenshotSurface.trailingAnchor),
            screenshotImageView.topAnchor.constraint(equalTo: screenshotSurface.topAnchor),
            screenshotImageView.bottomAnchor.constraint(equalTo: screenshotSurface.bottomAnchor),
        ])

        screenshotSpinner.isHidden = true

        removeScreenshotButton.translatesAutoresizingMaskIntoConstraints = false
        removeScreenshotButton.bezelStyle = .regularSquare
        removeScreenshotButton.isBordered = false
        removeScreenshotButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove recent screenshot")
        removeScreenshotButton.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        removeScreenshotButton.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            return shadow
        }()
        removeScreenshotButton.target = self
        removeScreenshotButton.action = #selector(handleRemoveScreenshot)
        screenshotContainer.addSubview(removeScreenshotButton)
        NSLayoutConstraint.activate([
            removeScreenshotButton.topAnchor.constraint(equalTo: screenshotContainer.topAnchor, constant: PrimitiveTokens.Space.xs),
            removeScreenshotButton.trailingAnchor.constraint(equalTo: screenshotContainer.trailingAnchor, constant: -PrimitiveTokens.Space.xs),
        ])

        editorHost.translatesAutoresizingMaskIntoConstraints = false
        editorHost.textView.delegate = self
        contentStack.addArrangedSubview(editorHost)
        editorHeightConstraint = editorHost.heightAnchor.constraint(equalToConstant: CaptureRuntimeMetrics.editorMinimumVisibleHeight)
        editorHeightConstraint.isActive = true
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
            },
            onCommand: { [weak self] command in
                self?.handleEditorCommand(command) ?? false
            }
        )

        inlineTagSuggestionView.translatesAutoresizingMaskIntoConstraints = false
        inlineTagSuggestionView.isHidden = true
        contentStack.addArrangedSubview(inlineTagSuggestionView)
        NSLayoutConstraint.activate([
            inlineTagSuggestionView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])

        recomputePreferredPanelHeight()
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

        model.$cards
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshInlineTagState()
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

        // IME composition owns the live editor contents until the marked text commits.
        guard !editorHost.textView.hasMarkedText() else {
            return
        }

        guard editorHost.textView.string != text else {
            return
        }

        discardPendingDraftSync()
        isApplyingDraftExternally = true
        editorHost.applyExternalText(text, forceScrollToSelection: forceScrollToSelection, forceMeasure: true)
        isApplyingDraftExternally = false
        refreshInlineTagState(resetSuggestionSelection: true)
    }

    private func applyEditorMetrics(_ metrics: CaptureEditorMetrics) {
        editorHeightConstraint.constant = max(CaptureRuntimeMetrics.editorMinimumVisibleHeight, metrics.visibleHeight)
        recomputePreferredPanelHeight()
    }

    private func applySubmittingState(_ isSubmitting: Bool) {
        editorHost.textView.isEditable = !isSubmitting
        removeScreenshotButton.isEnabled = !isSubmitting
        if isSubmitting {
            screenshotSpinner.stopAnimation(nil)
        } else if !model.showsRecentScreenshotPlaceholder {
            screenshotSpinner.stopAnimation(nil)
        }
    }

    private func applyRecentScreenshotState(_ state: RecentScreenshotState) {
        let shouldShow = model.showsRecentScreenshotSlot
        screenshotContainer.isHidden = !shouldShow
        screenshotHeightConstraint.constant = shouldShow ? PrimitiveTokens.Size.captureAttachmentPreviewSize : 0

        switch state {
        case .idle, .detected, .expired, .consumed:
            imageLoadTask?.cancel()
            displayedPreviewImageKey = nil
            screenshotImageView.image = nil
            screenshotSpinner.stopAnimation(nil)
            screenshotSurface.showLoading(false)
        case .previewReady(let sessionID, let cacheURL, let thumbnailState):
            switch thumbnailState {
            case .loading:
                imageLoadTask?.cancel()
                displayedPreviewImageKey = nil
                screenshotImageView.image = nil
                screenshotSurface.showLoading(true)
                screenshotSpinner.stopAnimation(nil)
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
        screenshotSpinner.stopAnimation(nil)

        imageLoadTask = Task { [weak self, cacheKey, url] in
            let image = await Task.detached(priority: .utility) {
                CapturePreviewImageCache.loadUncachedImage(from: url)
            }.value

            guard !Task.isCancelled else {
                return
            }

            guard let self else {
                return
            }

            if let image {
                Self.previewImageCache.store(image, forKey: cacheKey)
            }

            guard self.displayedPreviewImageKey == cacheKey else {
                return
            }

            let resolvedImage = Self.previewImageCache.image(forKey: cacheKey)
            self.screenshotImageView.image = resolvedImage
            self.screenshotSurface.showLoading(false)
            self.screenshotSpinner.stopAnimation(nil)
        }
    }

    private func recomputePreferredPanelHeight() {
        let screenshotHeight = screenshotContainer.isHidden ? 0 : (PrimitiveTokens.Size.captureAttachmentPreviewSize + PrimitiveTokens.Space.sm)
        let editorHeight = max(editorHost.currentMetrics.visibleHeight, CaptureRuntimeMetrics.editorMinimumVisibleHeight)
        let surfaceHeight = Self.minimumSurfaceHeight(
            editorHeight: editorHeight,
            inlineTagSuggestionHeight: 0,
            screenshotHeight: screenshotHeight
        )

        let nextPreferredPanelHeight = Self.preferredPanelHeight(forSurfaceHeight: surfaceHeight)
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

    private static func minimumSurfaceHeight(
        editorHeight: CGFloat,
        inlineTagSuggestionHeight: CGFloat,
        screenshotHeight: CGFloat
    ) -> CGFloat {
        max(
            PrimitiveTokens.Size.searchFieldHeight,
            editorHeight
                + inlineTagSuggestionHeight
                + screenshotHeight
                + (captureSurfaceVerticalInset * 2)
        )
    }

    private static func preferredPanelHeight(forSurfaceHeight surfaceHeight: CGFloat) -> CGFloat {
        ceil(
            PanelMetrics.capturePanelShadowTopInset
                + surfaceHeight
                + PanelMetrics.capturePanelShadowBottomInset
        )
    }

    private func handleSubmit() {
        flushDraftSyncIfNeeded(forceText: editorHost.textView.string)
        model.beginCaptureSubmission { [weak self] in
            self?.onSubmitSuccess?()
        }
    }

    private func handleEditorCommand(_ command: CueEditorCommand) -> Bool {
        if handleInlineTagCommand(command) {
            return true
        }

        return false
    }

    private func handleInlineTagCommand(_ command: CueEditorCommand) -> Bool {
        switch command {
        case .moveSelectionUp:
            return moveInlineTagSelection(by: -1)
        case .moveSelectionDown:
            return moveInlineTagSelection(by: 1)
        case .completeSelection(let trigger):
            guard trigger == .tab else {
                return false
            }

            return completePendingInlineTagIfPossible()
        case .cancelSelection:
            guard !inlineTagSuggestions.isEmpty else {
                return false
            }

            inlineTagSuggestions = []
            selectedInlineTagSuggestionIndex = 0
            lastInlineTagQueryValue = nil
            updateInlineTagSuggestionView()
            return true
        }
    }

    private static func appearanceSignature(for appearance: NSAppearance?) -> String {
        appearance?.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])?.rawValue ?? "unspecified"
    }

    private func makeInlineTagSuggestionView() -> CaptureInlineTagSuggestionView {
        CaptureInlineTagSuggestionView(
            suggestions: inlineTagSuggestions,
            selectedIndex: selectedInlineTagSuggestionIndex,
            onSelectSuggestion: { [weak self] suggestion in
                _ = self?.commitInlineTag(named: suggestion)
            }
        )
    }

    private func refreshInlineTagState(resetSuggestionSelection: Bool = false) {
        guard !editorHost.textView.hasMarkedText() else {
            suspendInlineTagPresentationForMarkedText()
            return
        }

        let inlineTags = CaptureTagText.extractCanonicalInlineTags(in: editorHost.textView.string).matches
        let completionContext = currentInlineTagCompletionContext()
        var highlightedRanges = inlineTags.map(\.range)
        if let completionContext,
           completionContext.replacementRange.length > 0 {
            highlightedRanges.append(completionContext.replacementRange)
        }
        editorHost.highlightedInlineTagRanges = highlightedRanges

        let suggestions = matchingInlineTagSuggestions(
            committedTagNames: Set(inlineTags.map(\.tag.name)),
            completionContext: completionContext
        )
        let queryValue = completionContext?.normalizedPrefix
        let didQueryChange = queryValue != lastInlineTagQueryValue
        lastInlineTagQueryValue = queryValue
        inlineTagSuggestions = Array(suggestions.prefix(4))

        if inlineTagSuggestions.isEmpty {
            selectedInlineTagSuggestionIndex = 0
        } else if resetSuggestionSelection || didQueryChange {
            selectedInlineTagSuggestionIndex = 0
        } else {
            selectedInlineTagSuggestionIndex = max(
                0,
                min(selectedInlineTagSuggestionIndex, inlineTagSuggestions.count - 1)
            )
        }

        updateInlineTagSuggestionView()
    }

    private func suspendInlineTagPresentationForMarkedText() {
        lastInlineTagQueryValue = nil
        inlineTagSuggestions = []
        selectedInlineTagSuggestionIndex = 0
        editorHost.setInlineCompletion(suffix: nil, caretUTF16Offset: nil)
        inlineTagSuggestionView.isHidden = true
        recomputePreferredPanelHeight()
    }

    private func updateInlineTagSuggestionView() {
        let completionContext = currentInlineTagCompletionContext()
        let selectedRange = editorHost.textView.selectedRange()
        let ghostSuffix = inlineTagGhostSuffix(
            completionContext: completionContext,
            selectedCaretLocation: selectedRange.location
        )
        editorHost.setInlineCompletion(
            suffix: ghostSuffix,
            caretUTF16Offset: ghostSuffix == nil ? nil : selectedRange.location
        )
        inlineTagSuggestionView.rootView = makeInlineTagSuggestionView()
        inlineTagSuggestionView.isHidden = true
        recomputePreferredPanelHeight()
    }

    private func inlineTagGhostSuffix(
        completionContext: CaptureTagCompletionContext?,
        selectedCaretLocation: Int
    ) -> String? {
        guard let completionContext,
              let normalizedPrefix = completionContext.normalizedPrefix,
              selectedCaretLocation == NSMaxRange(completionContext.replacementRange) else {
            return nil
        }

        let resolvedSuggestion = inlineTagSuggestions[safe: selectedInlineTagSuggestionIndex]
            ?? inlineTagSuggestions.first
        guard let resolvedSuggestion,
              resolvedSuggestion.hasPrefix(normalizedPrefix) else {
            return nil
        }

        let suffix = String(resolvedSuggestion.dropFirst(normalizedPrefix.count))
        return suffix.isEmpty ? nil : suffix
    }

    private func moveInlineTagSelection(by offset: Int) -> Bool {
        guard !inlineTagSuggestions.isEmpty else {
            return false
        }

        let count = inlineTagSuggestions.count
        let current = max(0, min(selectedInlineTagSuggestionIndex, count - 1))
        selectedInlineTagSuggestionIndex = (current + offset + count) % count
        updateInlineTagSuggestionView()
        return true
    }

    private func completePendingInlineTagIfPossible() -> Bool {
        guard let completionContext = currentInlineTagCompletionContext() else {
            return false
        }

        let exactMatch = inlineTagSuggestions.first(where: {
            $0 == completionContext.normalizedPrefix
        })
        let resolvedName = exactMatch
            ?? inlineTagSuggestions[safe: selectedInlineTagSuggestionIndex]
            ?? (completionContext.normalizedPrefix.flatMap(CaptureTag.init(rawValue:))?.name
                ?? CaptureTag.normalize(completionContext.rawToken)
            )

        guard let resolvedName,
              CaptureTag(rawValue: resolvedName) != nil else {
            return false
        }

        return commitInlineTag(named: resolvedName)
    }

    private func matchingInlineTagSuggestions(
        committedTagNames: Set<String>,
        completionContext: CaptureTagCompletionContext?
    ) -> [String] {
        guard let completionContext,
              let normalizedPrefix = completionContext.normalizedPrefix else {
            return []
        }

        return model.knownCaptureTagNames.filter { candidate in
            (normalizedPrefix.isEmpty || candidate.hasPrefix(normalizedPrefix))
                && !committedTagNames.contains(candidate)
        }
    }

    private func currentInlineTagCompletionContext() -> CaptureTagCompletionContext? {
        let selectedRange = editorHost.textView.selectedRange()
        guard selectedRange.length == 0 else {
            return nil
        }

        return CaptureTagText.completionContext(
            in: editorHost.textView.string,
            caretUTF16Offset: selectedRange.location
        )
    }

    @discardableResult
    private func commitInlineTag(named name: String) -> Bool {
        guard let completionContext = currentInlineTagCompletionContext(),
              let tag = CaptureTag(rawValue: name) else {
            return false
        }

        let nsText = editorHost.textView.string as NSString
        let shouldAppendTrailingSpace = NSMaxRange(completionContext.replacementRange) >= nsText.length
        let replacement = tag.displayText + (shouldAppendTrailingSpace ? " " : "")
        let updatedText = nsText.replacingCharacters(
            in: completionContext.replacementRange,
            with: replacement
        )
        let updatedSelection = NSRange(
            location: completionContext.replacementRange.location + replacement.utf16.count,
            length: 0
        )

        discardPendingDraftSync()
        isApplyingDraftExternally = true
        editorHost.applyExternalText(
            updatedText,
            selectedRange: updatedSelection,
            forceScrollToSelection: true,
            forceMeasure: true
        )
        isApplyingDraftExternally = false
        model.draftText = updatedText
        refreshInlineTagState(resetSuggestionSelection: true)
        editorHost.focusIfPossible()
        return true
    }

    @objc
    private func handleRemoveScreenshot() {
        model.dismissPendingScreenshot()
    }

    func persistDraftIfNeeded() {
        flushDraftSyncIfNeeded(forceText: editorHost.textView.string)
    }

    func discardPendingDraftSync() {
        pendingDraftSyncWorkItem?.cancel()
        pendingDraftSyncWorkItem = nil
        pendingDraftSyncText = nil
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
        let isComposingMarkedText = textView.hasMarkedText()

        if isComposingMarkedText {
            discardPendingDraftSync()
        } else if !isApplyingDraftExternally {
            scheduleDraftSync(currentDraftText)
        }

        refreshInlineTagState()

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

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView === editorHost.textView else {
            return
        }

        refreshInlineTagState()
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
        discardPendingDraftSync()
        let resolvedText = forceText ?? pendingDraftSyncText ?? editorHost.textView.string

        if !isApplyingDraftExternally, model.draftText != resolvedText {
            model.draftText = resolvedText
        }
    }
}

#if DEBUG
extension CapturePanelRuntimeViewController {
    var debugEditorText: String {
        get { editorHost.textView.string }
        set { editorHost.textView.string = newValue }
    }

    var debugInlineCompletionSuffix: String? {
        editorHost.debugInlineCompletionSuffix
    }

    var debugIsInlineCompletionVisible: Bool {
        editorHost.debugIsInlineCompletionVisible
    }

    func debugApplyEditorText(_ text: String, selectedLocation: Int? = nil) {
        let location = max(0, min(selectedLocation ?? text.utf16.count, text.utf16.count))
        editorHost.applyExternalText(
            text,
            selectedRange: NSRange(location: location, length: 0),
            forceScrollToSelection: true,
            forceMeasure: true
        )
        refreshInlineTagState(resetSuggestionSelection: true)
    }

    func debugScheduleDraftSync(_ text: String) {
        scheduleDraftSync(text)
    }

    @discardableResult
    func debugCompleteInlineTagSelection() -> Bool {
        completePendingInlineTagIfPossible()
    }
}
#endif

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
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

private final class CapturePanelAppearanceAwareView: NSView {
    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
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

    func refreshAppearance() {
        updateAppearance()
        needsDisplay = true
    }

    private func updateAppearance() {
        ambientLayer.fillColor = NSColor.white.withAlphaComponent(0.02).cgColor
        ambientLayer.shadowColor = ambientShadowColor.cgColor
        ambientLayer.shadowOpacity = Float(PrimitiveTokens.Shadow.captureAmbientOpacity)
        ambientLayer.shadowRadius = PrimitiveTokens.Shadow.captureAmbientBlur / 2
        // Light is assumed to come from above, so both ambient and key shadow
        // should bias downward instead of blooming symmetrically around the shell.
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

    func refreshAppearance() {
        updateAppearance()
        needsDisplay = true
    }

    private func updateAppearance() {
        let bestMatch = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
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

private final class CaptureScreenshotPreviewView: NSView {
    var image: NSImage? {
        didSet {
            imageLayer.contents = image.flatMap(Self.cgImage(from:))
            imageLayer.isHidden = image == nil
        }
    }

    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.isHidden = true
        layer?.addSublayer(imageLayer)
        updateContentsScale()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        imageLayer.contentsScale = scale
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}

private final class HoverTintButton: NSButton {
    private let normalAlpha: CGFloat = 0.7
    private let hoverAlpha: CGFloat = 1.0
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        contentTintColor = NSColor.white.withAlphaComponent(hoverAlpha)
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = NSColor.white.withAlphaComponent(normalAlpha)
    }
}
