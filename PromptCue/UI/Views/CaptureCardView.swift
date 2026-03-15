import AppKit
import Foundation
import PromptCueCore
import SwiftUI

#if DEBUG
private func logCardHoverTrace(_ line: String) {
    guard ProcessInfo.processInfo.environment["PROMPTCUE_TRACE_STACK_CARD_HOVER"] == "1" else {
        return
    }

    print(line)
    fflush(stdout)

    let logURL = URL(fileURLWithPath: "/tmp/promptcue-hover.log")
    let data = (line + "\n").data(using: .utf8) ?? Data()
    guard let handle = try? FileHandle(forWritingTo: logURL) else {
        do {
            try data.write(to: logURL)
        } catch {
            return
        }
        return
    }

    defer { try? handle.close() }
    try? handle.seekToEnd()
    handle.write(data)
}

private func cardHoverTracingEnabled() -> Bool {
    ProcessInfo.processInfo.environment["PROMPTCUE_TRACE_STACK_CARD_HOVER"] == "1"
}
#endif

struct CaptureCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let card: CaptureCard
    let classification: ContentClassification
    let availableSuggestedTargets: [CaptureSuggestedTarget]
    let automaticSuggestedTarget: CaptureSuggestedTarget?
    let isSelected: Bool
    let isRecentlyCopied: Bool
    let selectionMode: Bool
    let ttlProgressRemaining: Double?
    let isExpanded: Bool
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onCopyRaw: () -> Void
    let onToggleSelection: () -> Void
    let onCmdClick: () -> Void
    let onToggleExpansion: () -> Void
    let onDelete: () -> Void
    let onRefreshSuggestedTargets: () -> Void
    let onAssignSuggestedTarget: (CaptureSuggestedTarget) -> Void
    @State private var isCardHovered = false
    @State private var isCopyHovered = false
    @State private var isDeleteHovered = false
    @State private var isShowingCopyFeedback = false
    @State private var isOverflowAffordanceHovered = false
    #if DEBUG
    @State private var lastRawHoverNanos: UInt64?
    @State private var lastEmphasizedNanos: UInt64?
    #endif

    private var actionStyle: CaptureCardActionStyle {
        CaptureCardActionStyle.resolve(
            card: card,
            isSelected: isSelected,
            isRecentlyCopied: isRecentlyCopied,
            selectionMode: selectionMode,
            colorScheme: colorScheme,
            isCardHovered: isCardHoveredState,
            isCopyHovered: isCopyHovered,
            isDeleteHovered: isDeleteHovered,
            isShowingCopyFeedback: isShowingCopyFeedback
        )
    }

    init(
        card: CaptureCard,
        classification: ContentClassification = .plain,
        availableSuggestedTargets: [CaptureSuggestedTarget] = [],
        automaticSuggestedTarget: CaptureSuggestedTarget? = nil,
        isSelected: Bool,
        isRecentlyCopied: Bool = false,
        selectionMode: Bool,
        ttlProgressRemaining: Double? = nil,
        isExpanded: Bool,
        onCopy: @escaping () -> Void,
        onEdit: @escaping () -> Void = {},
        onCopyRaw: @escaping () -> Void = {},
        onToggleSelection: @escaping () -> Void,
        onCmdClick: @escaping () -> Void = {},
        onToggleExpansion: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRefreshSuggestedTargets: @escaping () -> Void = {},
        onAssignSuggestedTarget: @escaping (CaptureSuggestedTarget) -> Void = { _ in }
    ) {
        self.card = card
        self.classification = classification
        self.availableSuggestedTargets = availableSuggestedTargets
        self.automaticSuggestedTarget = automaticSuggestedTarget
        self.isSelected = isSelected
        self.isRecentlyCopied = isRecentlyCopied
        self.selectionMode = selectionMode
        self.ttlProgressRemaining = ttlProgressRemaining
        self.isExpanded = isExpanded
        self.onCopy = onCopy
        self.onEdit = onEdit
        self.onCopyRaw = onCopyRaw
        self.onToggleSelection = onToggleSelection
        self.onCmdClick = onCmdClick
        self.onToggleExpansion = onToggleExpansion
        self.onDelete = onDelete
        self.onRefreshSuggestedTargets = onRefreshSuggestedTargets
        self.onAssignSuggestedTarget = onAssignSuggestedTarget
    }

    var body: some View {
        let visibleInlineText = card.visibleInlineText
        let styledText = InteractiveDetectedTextView.styledText(
            text: visibleInlineText,
            classification: classification,
            baseColor: actionStyle.bodyColor,
            highlightedRanges: card.visibleInlineTagRanges
        )
        let displayConfiguration = styledText.displayConfiguration
        let overflowMetrics = StackCardOverflowPolicy.metrics(
            for: styledText.measurementText,
            cacheIdentity: card.id,
            layoutVariant: displayConfiguration.layoutVariant,
            styleSignature: styledText.cacheSignature,
            availableWidth: textContentWidth
        )

        StackNotificationCardSurface(
            isSelected: isSelected,
            isEmphasized: isCardHoveredState
        ) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    if let screenshotURL = card.screenshotURL {
                        LocalImageThumbnail(
                            url: screenshotURL,
                            height: PrimitiveTokens.Size.notificationThumbnailHeight
                        )
                        .opacity(card.isCopied ? PrimitiveTokens.Opacity.soft : 1)
                    }

                    InteractiveDetectedTextView(styledText: styledText)
                    .frame(
                        height: displayConfiguration.prefersSingleLine
                            ? nil
                            : visibleTextHeight(for: overflowMetrics),
                        alignment: .top
                    )
                    .clipped()

                    if !displayConfiguration.prefersSingleLine && overflowMetrics.overflowsAtRest {
                        overflowAffordance(metrics: overflowMetrics)
                            .padding(.top, StackCardOverflowPolicy.affordanceTopSpacing)
                    }

                    CaptureCardSuggestedTargetAccessoryView(
                        currentTarget: card.suggestedTarget,
                        availableTargets: availableSuggestedTargets,
                        automaticTarget: automaticSuggestedTarget,
                        onRefreshTargets: onRefreshSuggestedTargets,
                        onAssignTarget: onAssignSuggestedTarget
                    )
                    .padding(.top, PrimitiveTokens.Space.xxxs)
                }
                .padding(.trailing, actionColumnReservedWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: PrimitiveTokens.Motion.standard), value: isExpanded)

                VStack(spacing: PrimitiveTokens.Space.xs) {
                    iconButton(
                        systemName: actionStyle.primaryIconSystemName,
                        foregroundColor: actionStyle.primaryIconColor,
                        backgroundColor: actionStyle.primaryIconBackground,
                        action: performCopy
                    )
                    .accessibilityLabel(selectionMode ? "Toggle staged cue copy" : "Copy cue")
                    .accessibilityHint(
                        selectionMode
                            ? "Adds or removes this cue from the current grouped clipboard"
                            : "Copies this cue to the clipboard"
                    )
                    .onHover { hovered in
                        isCopyHovered = hovered
                    }

                    iconButton(
                        systemName: "trash",
                        foregroundColor: actionStyle.deleteIconColor,
                        backgroundColor: actionStyle.deleteIconBackground,
                        action: onDelete
                    )
                    .accessibilityLabel("Delete cue")
                    .accessibilityHint("Permanently removes this cue")
                    .onHover { hovered in
                        isDeleteHovered = hovered
                    }
                }
                .frame(width: actionColumnWidth, alignment: .topTrailing)
                .zIndex(1)

                if let ttlProgressRemaining {
                    ttlIndicator(progressRemaining: ttlProgressRemaining)
                        .padding(.trailing, PrimitiveTokens.Space.xxxs)
                        .padding(.bottom, PrimitiveTokens.Space.xxxs)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .zIndex(1)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel(displayText: visibleInlineText))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Copy Raw", action: onCopyRaw)
        }
        .onTapGesture {
            if isCommandClickEvent {
                onCmdClick()
            } else {
                performPrimaryAction()
            }
        }
        .overlay(alignment: .topLeading) {
            HoverTrackingArea { hovered in
                setCardHovered(hovered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
        #if DEBUG
        .onChange(of: isCardHoveredState) { isEmphasized in
            guard cardHoverTracingEnabled() else {
                return
            }

            let now = DispatchTime.now().uptimeNanoseconds
            if isEmphasized, let rawNanos = lastRawHoverNanos {
                let latencyMs = Double(now - rawNanos) / 1_000_000
                logCardHoverTrace(
                    String(
                        format: "PROMPTCUE_CARD_HOVER_LATENCY_MS card=%@ hasImage=%d latency_ms=%.3f",
                        card.id.uuidString,
                        card.screenshotURL != nil ? 1 : 0,
                        latencyMs
                    )
                )
            }

            if let lastEmphasizedNanos {
                let sinceMs = Double(now - lastEmphasizedNanos) / 1_000_000
                logCardHoverTrace(
                    String(
                        format: "PROMPTCUE_CARD_HOVER_STATE card=%@ hasImage=%d emphasized=%d changed_since_ms=%.3f",
                        card.id.uuidString,
                        card.screenshotURL != nil ? 1 : 0,
                        isEmphasized ? 1 : 0,
                        sinceMs
                    )
                )
            } else {
                logCardHoverTrace(
                    String(
                        format: "PROMPTCUE_CARD_HOVER_STATE card=%@ hasImage=%d emphasized=%d changed_since_ms=NA",
                        card.id.uuidString,
                        card.screenshotURL != nil ? 1 : 0,
                        isEmphasized ? 1 : 0
                    )
                )
            }

            lastEmphasizedNanos = now
        }
        #endif
    }

    private func setCardHovered(_ hovered: Bool) {
        if hovered {
            isCardHovered = true
            #if DEBUG
            if cardHoverTracingEnabled() {
                let now = DispatchTime.now().uptimeNanoseconds
                lastRawHoverNanos = now
                logCardHoverTrace(
                    String(
                        format: "PROMPTCUE_CARD_HOVER_EVENT card=%@ hasImage=%d state=entered raw_nanos=%llu",
                        card.id.uuidString,
                        card.screenshotURL != nil ? 1 : 0,
                        now
                    )
                )
            }
            #endif
            return
        }

        if !isCardHovered {
            return
        }
        guard !isCopyHovered, !isDeleteHovered, !isOverflowAffordanceHovered else {
            return
        }
        isCardHovered = false
        #if DEBUG
        if cardHoverTracingEnabled() {
            let now = DispatchTime.now().uptimeNanoseconds
            logCardHoverTrace(
                String(
                    format: "PROMPTCUE_CARD_HOVER_EVENT card=%@ hasImage=%d state=exited raw_nanos=%llu",
                    card.id.uuidString,
                    card.screenshotURL != nil ? 1 : 0,
                    now
                )
            )
        }
        #endif
    }

    private var isCardHoveredState: Bool {
        isCardHovered
            || isCopyHovered
            || isDeleteHovered
            || isShowingCopyFeedback
            || isOverflowAffordanceHovered
    }

    private var contentSpacing: CGFloat {
        if card.screenshotURL != nil {
            return PrimitiveTokens.Space.sm
        }

        return PrimitiveTokens.Space.xxs
    }

    private struct HoverTrackingArea: NSViewRepresentable {
        let onHover: (Bool) -> Void

        func makeNSView(context: Context) -> NSView {
            let view = HoverTrackingContainerView()
            view.onHover = onHover
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard let trackingView = nsView as? HoverTrackingContainerView else {
                return
            }
            trackingView.onHover = onHover
            trackingView.reinstallTrackingAreaIfNeeded()
        }

        final class HoverTrackingContainerView: NSView {
            var onHover: (Bool) -> Void = { _ in }
            private var isMouseInside = false
            private var trackingArea: NSTrackingArea?

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                postsBoundsChangedNotifications = true
            }

            required init?(coder: NSCoder) {
                super.init(coder: coder)
                postsBoundsChangedNotifications = true
            }

            deinit {
                removeTrackingAreaIfNeeded()
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                reinstallTrackingAreaIfNeeded()
            }

            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                reinstallTrackingAreaIfNeeded()
            }

            private func removeTrackingAreaIfNeeded() {
                if let trackingArea {
                    removeTrackingArea(trackingArea)
                    self.trackingArea = nil
                }
            }

            func reinstallTrackingAreaIfNeeded() {
            guard window != nil else {
                isMouseInside = false
                removeTrackingAreaIfNeeded()
                if cardHoverTracingEnabled() {
                    logCardHoverTrace(
                        "PROMPTCUE_HOVER_TRACKER_EVENT state=window_missing_card_area_released"
                    )
                }
                return
            }

                if let trackingArea {
                    removeTrackingArea(trackingArea)
                }

                let options: NSTrackingArea.Options = [
                    .mouseEnteredAndExited,
                    .mouseMoved,
                    .activeInKeyWindow,
                    .inVisibleRect
                ]
                trackingArea = NSTrackingArea(
                    rect: bounds,
                    options: options,
                    owner: self,
                    userInfo: nil
                )
                addTrackingArea(trackingArea!)
                syncMouseStateToCursor()
            }

            private func syncMouseStateToCursor() {
                guard let window else {
                    return
                }

                let cursorLocation = window.mouseLocationOutsideOfEventStream
                let localLocation = convert(cursorLocation, from: nil)
                let cursorInside = bounds.contains(localLocation)
                if cursorInside == isMouseInside {
                    return
                }

                isMouseInside = cursorInside
                onHover(cursorInside)
                if cardHoverTracingEnabled() {
                    logCardHoverTrace(
                        String(
                            format: "PROMPTCUE_HOVER_TRACKER_EVENT rect_sync entered=%d",
                            cursorInside ? 1 : 0
                        )
                    )
                }
            }

            override func hitTest(_ point: NSPoint) -> NSView? {
                return nil
            }

            override func mouseEntered(with event: NSEvent) {
                super.mouseEntered(with: event)
                guard !isMouseInside else {
                    return
                }
                isMouseInside = true
                onHover(true)
            }

            override func mouseExited(with event: NSEvent) {
                super.mouseExited(with: event)
                guard isMouseInside else {
                    return
                }
                isMouseInside = false
                onHover(false)
            }

            override func mouseMoved(with event: NSEvent) {
                super.mouseMoved(with: event)
                guard window != nil else {
                    return
                }

                let locationInView = convert(event.locationInWindow, from: nil)
                let inside = bounds.contains(locationInView)
                if inside, !isMouseInside {
                    isMouseInside = true
                    onHover(true)
                } else if !inside, isMouseInside {
                    isMouseInside = false
                    onHover(false)
                }
            }
        }
    }

    private var actionColumnWidth: CGFloat {
        PrimitiveTokens.Space.xl
    }

    private var actionColumnReservedWidth: CGFloat {
        actionColumnWidth + PrimitiveTokens.Space.sm
    }

    private var textContentWidth: CGFloat {
        StackCardOverflowPolicy.cardTextWidth
    }

    private func visibleTextHeight(for metrics: StackCardOverflowPolicy.Metrics) -> CGFloat {
        if isExpanded {
            return metrics.expandedVisibleTextHeight
        }

        return metrics.restingVisibleTextHeight
    }

    @ViewBuilder
    private func overflowAffordance(metrics: StackCardOverflowPolicy.Metrics) -> some View {
        let label = isExpanded
            ? StackCardOverflowPolicy.collapseLabel()
            : StackCardOverflowPolicy.overflowLabel(hiddenLineCount: metrics.hiddenRestingLineCount)

        Button(action: onToggleExpansion) {
            Text(label)
                .font(PrimitiveTokens.Typography.meta)
                .foregroundStyle(
                    isOverflowAffordanceHovered
                        ? SemanticTokens.Text.primary
                        : SemanticTokens.Text.secondary
                )
                .underline(isOverflowAffordanceHovered, color: SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.soft))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovered in
            isOverflowAffordanceHovered = hovered
        }
        .accessibilityLabel(label)
        .accessibilityHint(isExpanded ? "Collapse this cue" : "Show more of this cue")
    }

    private func performPrimaryAction() {
        if selectionMode {
            onToggleSelection()
            return
        }

        performCopy()
    }

    private func performCopy() {
        if selectionMode {
            onToggleSelection()
            return
        }

        guard !isShowingCopyFeedback else {
            return
        }

        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.hoverQuick)) {
            isShowingCopyFeedback = true
        }

        onCopy()
        DispatchQueue.main.asyncAfter(deadline: .now() + PrimitiveTokens.Motion.hoverQuick) {
            isShowingCopyFeedback = false
        }
    }

    private var isCommandClickEvent: Bool {
        NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) == true
    }

    private func accessibilityLabel(displayText: String) -> String {
        "Cue: \(displayText)"
    }

    @ViewBuilder
    private func ttlIndicator(progressRemaining: Double) -> some View {
        let lineWidth: CGFloat = 1.5
        let trackColor = SemanticTokens.Border.subtle.opacity(0.9)
        let progressColor = SemanticTokens.Text.secondary.opacity(0.88)

        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(progressRemaining, 0.02))
                .stroke(progressColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private func iconButton(
        systemName: String,
        foregroundColor: Color,
        backgroundColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(PrimitiveTokens.Typography.accessoryIcon)
                .foregroundStyle(foregroundColor)
                .frame(width: PrimitiveTokens.Space.lg, height: PrimitiveTokens.Space.lg)
                .background(
                    RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.sm, style: .continuous)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CaptureCardActionStyle {
    let bodyColor: Color
    let primaryIconColor: Color
    let primaryIconSystemName: String
    let primaryIconBackground: Color
    let deleteIconColor: Color
    let deleteIconBackground: Color

    static func resolve(
        card: CaptureCard,
        isSelected: Bool,
        isRecentlyCopied: Bool,
        selectionMode: Bool,
        colorScheme: ColorScheme,
        isCardHovered: Bool,
        isCopyHovered: Bool,
        isDeleteHovered: Bool,
        isShowingCopyFeedback: Bool
    ) -> CaptureCardActionStyle {
        let usesPersistentActionBackdrop = card.screenshotURL != nil
        let isPrimaryCopyHover = isCopyHovered || isCardHovered

        let bodyColor: Color
        if isSelected || isCardHovered || isCopyHovered || isDeleteHovered {
            bodyColor = SemanticTokens.Text.primary
        } else if isRecentlyCopied || card.isCopied {
            switch colorScheme {
            case .light:
                bodyColor = SemanticTokens.Text.primary.opacity(0.74)
            case .dark:
                bodyColor = SemanticTokens.Text.secondary.opacity(0.78)
            @unknown default:
                bodyColor = SemanticTokens.Text.secondary.opacity(0.78)
            }
        } else {
            bodyColor = SemanticTokens.Text.primary
        }

        let primaryIconColor: Color
        if isDeleteHovered {
            primaryIconColor = SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.subtle)
        } else if isShowingCopyFeedback {
            primaryIconColor = SemanticTokens.Text.primary
        } else if selectionMode, isSelected {
            primaryIconColor = SemanticTokens.Text.primary
        } else if selectionMode {
            primaryIconColor = SemanticTokens.Text.secondary.opacity(0.78)
        } else if isPrimaryCopyHover {
            primaryIconColor = SemanticTokens.Text.primary
        } else {
            switch colorScheme {
            case .light:
                primaryIconColor = SemanticTokens.Text.secondary.opacity(0.80)
            case .dark:
                primaryIconColor = SemanticTokens.Text.secondary.opacity(0.86)
            @unknown default:
                primaryIconColor = SemanticTokens.Text.secondary.opacity(0.86)
            }
        }

        let primaryIconSystemName: String
        if isShowingCopyFeedback {
            primaryIconSystemName = "checkmark"
        } else if selectionMode, isSelected {
            primaryIconSystemName = "checkmark.circle.fill"
        } else if selectionMode {
            primaryIconSystemName = "circle"
        } else if isPrimaryCopyHover {
            primaryIconSystemName = "doc.on.doc.fill"
        } else {
            primaryIconSystemName = "doc.on.doc"
        }

        let deleteIconColor: Color
        if isDeleteHovered {
            deleteIconColor = SemanticTokens.Text.primary
        } else if card.isCopied {
            switch colorScheme {
            case .light:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.62)
            case .dark:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.56)
            @unknown default:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.56)
            }
        } else {
            switch colorScheme {
            case .light:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.76)
            case .dark:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.82)
            @unknown default:
                deleteIconColor = SemanticTokens.Text.secondary.opacity(0.82)
            }
        }

        let primaryIconBackground: Color
        if isDeleteHovered {
            primaryIconBackground = .clear
        } else if isShowingCopyFeedback {
            primaryIconBackground = SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.strong)
        } else if selectionMode, isSelected {
            primaryIconBackground = SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.strong)
        } else if selectionMode {
            primaryIconBackground = .clear
        } else if isPrimaryCopyHover {
            primaryIconBackground = SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.strong)
        } else if usesPersistentActionBackdrop {
            switch colorScheme {
            case .light:
                primaryIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.72)
            case .dark:
                primaryIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.54)
            @unknown default:
                primaryIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.54)
            }
        } else {
            primaryIconBackground = .clear
        }

        let deleteIconBackground: Color
        if isDeleteHovered {
            deleteIconBackground = SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.medium)
        } else if usesPersistentActionBackdrop {
            switch colorScheme {
            case .light:
                deleteIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.60)
            case .dark:
                deleteIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.46)
            @unknown default:
                deleteIconBackground = SemanticTokens.Surface.notificationCardBackdrop.opacity(0.46)
            }
        } else {
            deleteIconBackground = .clear
        }

        return CaptureCardActionStyle(
            bodyColor: bodyColor,
            primaryIconColor: primaryIconColor,
            primaryIconSystemName: primaryIconSystemName,
            primaryIconBackground: primaryIconBackground,
            deleteIconColor: deleteIconColor,
            deleteIconBackground: deleteIconBackground
        )
    }
}
