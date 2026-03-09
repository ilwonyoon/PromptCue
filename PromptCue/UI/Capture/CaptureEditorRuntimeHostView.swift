import AppKit

// Runtime-owned AppKit editor host.
// This file owns live editor sizing, scrolling, and placeholder behavior.
final class CaptureEditorRuntimeHostView: NSView {
    let scrollView = IndicatorAwareScrollView()
    let textView = WrappingCueTextView()
    private let placeholderField = ClickThroughTextField(labelWithString: "")
    private let bottomBreathingRoomView = NSView()
    private let scrollIndicatorThumbView = NSView()

    var maxMeasuredHeight: CGFloat = CaptureRuntimeMetrics.editorMaxHeight {
        didSet {
            updateMeasuredMetrics(forceMeasure: true)
        }
    }

    var onMetricsChange: ((CaptureEditorMetrics) -> Void)?
    var onResolvedPreferredHeightChange: ((CGFloat) -> Void)?
    var placeholderText: String = "" {
        didSet {
            placeholderField.stringValue = placeholderText
        }
    }

    private var lastEmittedMetrics = CaptureEditorMetrics.empty
    private var currentResolvedHeight = CaptureEditorResolvedHeight.empty
    private var pendingMetrics: CaptureEditorMetrics?
    private var lastEmittedPreferredHeight: CGFloat = CaptureEditorResolvedHeight.empty.preferredHeight
    private var lastMeasuredViewportWidth: CGFloat = 0
    private var pendingScrollToSelection = false
    private var scrollBoundsObserver: NSObjectProtocol?
    private var scrollIndicatorHideWorkItem: DispatchWorkItem?
    private let shouldLogMetrics = ProcessInfo.processInfo.environment["PROMPTCUE_LOG_EDITOR_METRICS"] == "1"

    private lazy var scrollViewHeightConstraint = scrollView.heightAnchor.constraint(
        equalToConstant: minimumBodyVisibleHeight
    )
    private lazy var bottomBreathingHeightConstraint = bottomBreathingRoomView.heightAnchor.constraint(
        equalToConstant: CaptureRuntimeMetrics.editorBottomBreathingRoom
    )
    private lazy var scrollIndicatorTopConstraint = scrollIndicatorThumbView.topAnchor.constraint(equalTo: topAnchor)
    private lazy var scrollIndicatorHeightConstraint = scrollIndicatorThumbView.heightAnchor.constraint(equalToConstant: 0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }
        scrollIndicatorHideWorkItem?.cancel()
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: currentResolvedHeight.preferredHeight)
    }

    var currentMetrics: CaptureEditorMetrics {
        currentResolvedHeight.metrics
    }

    override func layout() {
        super.layout()
        let width = stableViewportWidth
        guard width > 0 else {
            return
        }

        if abs(width - lastMeasuredViewportWidth) > 0.5 {
            updateMeasuredMetrics(forceMeasure: true)
        }

        updateScrollIndicatorFrame()
    }

    func applyExternalText(
        _ text: String,
        forceScrollToSelection: Bool = false,
        forceMeasure: Bool = false
    ) {
        if textView.string != text {
            textView.string = text
            applyTextStorageAttributes()
            textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
            updatePlaceholderVisibility()
        }

        updateMeasuredMetrics(
            forceScrollToSelection: forceScrollToSelection,
            forceMeasure: forceMeasure
        )
    }

    func configureRuntime(
        text: String,
        placeholder: String,
        maxContentHeight: CGFloat,
        onMetricsChange: ((CaptureEditorMetrics) -> Void)?,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.maxMeasuredHeight = maxContentHeight
        self.onMetricsChange = onMetricsChange
        self.placeholderText = placeholder
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        textView.onPaste = { [weak self] in
            self?.requestScrollToSelectionOnNextMeasurement()
        }
        applyExternalText(text, forceScrollToSelection: !text.isEmpty, forceMeasure: true)
    }

    func focusIfPossible() {
        DispatchQueue.main.async {
            guard let window = self.window else {
                return
            }

            guard NSApp.isActive, window.isKeyWindow else {
                return
            }

            if window.firstResponder !== self.textView {
                window.makeFirstResponder(self.textView)
            }
        }
    }

    func requestScrollToSelectionOnNextMeasurement() {
        pendingScrollToSelection = true
    }

    func flushPendingMetricsIfNeeded() {
        guard let pendingMetrics else {
            return
        }

        self.pendingMetrics = nil
        emitMetricsIfNeeded(pendingMetrics)
    }

    func resolvePreferredHeight(forceMeasure: Bool = false) {
        updateMeasuredMetrics(forceMeasure: forceMeasure)
    }

    func updateMeasuredMetrics(
        forceScrollToSelection: Bool = false,
        forceMeasure: Bool = false,
        emitMetrics: Bool = true
    ) {
        let viewportWidth = stableViewportWidth
        guard viewportWidth > 0 else {
            return
        }

        let viewportWidthChanged = abs(viewportWidth - lastMeasuredViewportWidth) > 0.5
        guard forceMeasure || viewportWidthChanged else {
            return
        }

        lastMeasuredViewportWidth = viewportWidth

        let measurement = measureResolvedHeight(for: viewportWidth)

        let shouldScrollToSelection = forceScrollToSelection || pendingScrollToSelection
        pendingScrollToSelection = false

        apply(resolvedHeight: measurement, viewportWidth: viewportWidth)
        emitPreferredHeightIfNeeded(measurement.preferredHeight)

        if emitMetrics {
            pendingMetrics = nil
            emitMetricsIfNeeded(measurement.metrics)
        } else {
            pendingMetrics = measurement.metrics
        }

        if shouldScrollToSelection {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.textView.scrollRangeToVisible(self.textView.selectedRange())
                self.flashScrollIndicatorIfNeeded()
            }
        } else if scrollView.contentView.bounds.origin.y > 0.5 || scrollView.contentView.bounds.origin.x > 0.5 {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            updateScrollIndicatorFrame()
        }
    }

    private func setup() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.onUserScroll = { [weak self] in
            self?.flashScrollIndicatorIfNeeded()
        }

        addSubview(scrollView)

        bottomBreathingRoomView.translatesAutoresizingMaskIntoConstraints = false
        bottomBreathingRoomView.wantsLayer = true
        bottomBreathingRoomView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(bottomBreathingRoomView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollViewHeightConstraint,
            bottomBreathingRoomView.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bottomBreathingRoomView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBreathingRoomView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBreathingRoomView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBreathingHeightConstraint,
        ])

        scrollIndicatorThumbView.translatesAutoresizingMaskIntoConstraints = false
        scrollIndicatorThumbView.wantsLayer = true
        scrollIndicatorThumbView.layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(
            CaptureRuntimeMetrics.scrollIndicatorShowAlpha
        ).cgColor
        scrollIndicatorThumbView.layer?.cornerRadius = CaptureRuntimeMetrics.scrollIndicatorWidth / 2
        scrollIndicatorThumbView.alphaValue = 0
        addSubview(scrollIndicatorThumbView)

        NSLayoutConstraint.activate([
            scrollIndicatorThumbView.widthAnchor.constraint(equalToConstant: CaptureRuntimeMetrics.scrollIndicatorWidth),
            scrollIndicatorThumbView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -CaptureRuntimeMetrics.scrollIndicatorTrailingInset),
            scrollIndicatorTopConstraint,
            scrollIndicatorHeightConstraint,
        ])

        scrollView.documentView = textView
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        configureTextView()

        placeholderField.translatesAutoresizingMaskIntoConstraints = false
        placeholderField.font = NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.capture)
        placeholderField.textColor = NSColor.secondaryLabelColor.withAlphaComponent(PrimitiveTokens.Opacity.soft)
        placeholderField.lineBreakMode = .byTruncatingTail
        placeholderField.maximumNumberOfLines = 1
        placeholderField.isBordered = false
        placeholderField.backgroundColor = .clear
        addSubview(placeholderField)

        NSLayoutConstraint.activate([
            placeholderField.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            placeholderField.topAnchor.constraint(equalTo: topAnchor, constant: CaptureRuntimeMetrics.editorVerticalInset),
        ])

        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.handleScrollBoundsDidChange()
        }

        updatePlaceholderVisibility()
    }

    private func measureResolvedHeight(for viewportWidth: CGFloat) -> CaptureEditorResolvedHeight {
        let metrics = CaptureEditorLayoutCalculator.metrics(
            viewportWidth: viewportWidth,
            maxContentHeight: maxMeasuredHeight,
            minimumLineHeight: CaptureRuntimeMetrics.editorMinimumVisibleHeight
        ) { [weak self] layoutWidth in
            self?.measuredTotalHeight(for: layoutWidth) ?? CaptureRuntimeMetrics.editorMinimumVisibleHeight
        }

        return CaptureEditorResolvedHeight(
            contentHeight: metrics.contentHeight,
            visibleHeight: metrics.visibleHeight,
            preferredHeight: metrics.visibleHeight,
            isScrollable: metrics.isScrollable,
            layoutWidth: metrics.layoutWidth
        )
    }

    private func apply(resolvedHeight: CaptureEditorResolvedHeight, viewportWidth: CGFloat) {
        currentResolvedHeight = resolvedHeight
        updatePlaceholderVisibility()

        let bodyVisibleHeight = max(
            resolvedHeight.visibleHeight - CaptureRuntimeMetrics.editorBottomBreathingRoom,
            minimumBodyVisibleHeight
        )
        let documentHeight = max(
            resolvedHeight.contentHeight - CaptureRuntimeMetrics.editorBottomBreathingRoom,
            bodyVisibleHeight
        )
        scrollViewHeightConstraint.constant = bodyVisibleHeight

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(
                width: max(resolvedHeight.layoutWidth, 1),
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: viewportWidth,
            height: documentHeight
        )

        invalidateIntrinsicContentSize()
        needsLayout = true
        updateScrollIndicatorFrame()
    }

    private func emitMetricsIfNeeded(_ metrics: CaptureEditorMetrics) {
        guard metrics != lastEmittedMetrics else {
            return
        }

        lastEmittedMetrics = metrics
        onMetricsChange?(metrics)

        if shouldLogMetrics {
            NSLog(
                "CaptureEditor runtime width=%.1f content=%.1f visible=%.1f scroll=%@",
                metrics.layoutWidth,
                metrics.contentHeight,
                metrics.visibleHeight,
                metrics.isScrollable ? "true" : "false"
            )
        }
    }

    private func emitPreferredHeightIfNeeded(_ preferredHeight: CGFloat) {
        guard abs(preferredHeight - lastEmittedPreferredHeight) > 0.5 else {
            return
        }

        lastEmittedPreferredHeight = preferredHeight
        onResolvedPreferredHeightChange?(preferredHeight)
    }

    private var minimumBodyVisibleHeight: CGFloat {
        CaptureRuntimeMetrics.editorMinimumVisibleHeight - CaptureRuntimeMetrics.editorBottomBreathingRoom
    }

    private func measuredTotalHeight(for layoutWidth: CGFloat) -> CGFloat {
        measuredBodyHeight(for: layoutWidth) + CaptureRuntimeMetrics.editorBottomBreathingRoom
    }

    private func measuredBodyHeight(for layoutWidth: CGFloat) -> CGFloat {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return minimumBodyVisibleHeight
        }

        textContainer.widthTracksTextView = false
        textContainer.containerSize = NSSize(
            width: max(layoutWidth, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        let insetHeight = textView.textContainerInset.height * 2
        return max(minimumBodyVisibleHeight, usedHeight + insetHeight)
    }

    private func applyTextStorageAttributes() {
        guard let textStorage = textView.textStorage, textStorage.length > 0 else {
            return
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = PrimitiveTokens.LineHeight.capture
        paragraphStyle.maximumLineHeight = PrimitiveTokens.LineHeight.capture
        let font = NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.capture)

        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ], range: NSRange(location: 0, length: textStorage.length))
        textStorage.endEditing()
    }

    private func updatePlaceholderVisibility() {
        placeholderField.isHidden = !textView.string.isEmpty
    }

    private var stableViewportWidth: CGFloat {
        max(scrollView.frame.width, bounds.width, 1)
    }

    private func handleScrollBoundsDidChange() {
        updateScrollIndicatorFrame()
    }

    private func updateScrollIndicatorFrame() {
        guard currentResolvedHeight.isScrollable else {
            scrollIndicatorTopConstraint.constant = 0
            scrollIndicatorHeightConstraint.constant = 0
            hideScrollIndicatorImmediately()
            return
        }

        let visibleHeight = scrollViewHeightConstraint.constant
        let contentHeight = max(
            currentResolvedHeight.contentHeight - CaptureRuntimeMetrics.editorBottomBreathingRoom,
            visibleHeight
        )
        let trackInset = CaptureRuntimeMetrics.scrollIndicatorVerticalInset
        let trackHeight = max(visibleHeight - (trackInset * 2), 1)
        let thumbHeight = max(
            CaptureRuntimeMetrics.scrollIndicatorMinHeight,
            (visibleHeight / contentHeight) * trackHeight
        )
        let maxOffset = max(contentHeight - visibleHeight, 1)
        let scrollOffset = min(max(scrollView.contentView.bounds.origin.y, 0), maxOffset)
        let progress = scrollOffset / maxOffset
        let thumbTravel = max(trackHeight - thumbHeight, 0)
        let thumbY = trackInset + (thumbTravel * progress)

        scrollIndicatorTopConstraint.constant = thumbY
        scrollIndicatorHeightConstraint.constant = thumbHeight
    }

    private func flashScrollIndicatorIfNeeded() {
        guard currentResolvedHeight.isScrollable else {
            hideScrollIndicatorImmediately()
            return
        }

        scrollIndicatorHideWorkItem?.cancel()
        scrollIndicatorThumbView.animator().alphaValue = 1

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = CaptureRuntimeMetrics.scrollIndicatorFadeDuration
                self.scrollIndicatorThumbView.animator().alphaValue = 0
            }
        }

        scrollIndicatorHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + CaptureRuntimeMetrics.scrollIndicatorFadeDelay,
            execute: workItem
        )
    }

    private func hideScrollIndicatorImmediately() {
        scrollIndicatorHideWorkItem?.cancel()
        scrollIndicatorThumbView.alphaValue = 0
    }

    private func configureTextView() {
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        let font = NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.capture)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = PrimitiveTokens.LineHeight.capture
        paragraphStyle.maximumLineHeight = PrimitiveTokens.LineHeight.capture
        textView.font = font
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 0, height: CaptureRuntimeMetrics.editorVerticalInset)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.alignment = .left
        textView.defaultParagraphStyle = paragraphStyle
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
    }
}

final class IndicatorAwareScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        super.scrollWheel(with: event)
    }
}
