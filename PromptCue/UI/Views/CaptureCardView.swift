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
    _ = try? handle.seekToEnd()
    handle.write(data)
}

private func cardHoverTracingEnabled() -> Bool {
    ProcessInfo.processInfo.environment["PROMPTCUE_TRACE_STACK_CARD_HOVER"] == "1"
}
#endif

struct CaptureCardView: View {
    let card: CaptureCard
    let classification: ContentClassification
    let isSelected: Bool
    let isRecentlyCopied: Bool
    let selectionMode: Bool
    let ttlProgressRemaining: Double?
    let ttlRemainingMinutes: Int?
    let isExpanded: Bool
    let inheritedAppearance: NSAppearance?
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onCopyRaw: () -> Void
    let onMarkCopied: () -> Void
    let onToggleSelection: () -> Void
    let onCmdClick: () -> Void
    let onToggleExpansion: () -> Void
    let onDelete: () -> Void
    var onTogglePin: (() -> Void)?
    var compactMode: Bool = false
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
            appearance: inheritedAppearance,
            isCardHovered: isCardHoveredState,
            isCopyHovered: isCopyHovered,
            isDeleteHovered: isDeleteHovered,
            isShowingCopyFeedback: isShowingCopyFeedback
        )
    }

    init(
        card: CaptureCard,
        classification: ContentClassification = .plain,
        isSelected: Bool,
        isRecentlyCopied: Bool = false,
        selectionMode: Bool,
        ttlProgressRemaining: Double? = nil,
        ttlRemainingMinutes: Int? = nil,
        isExpanded: Bool,
        inheritedAppearance: NSAppearance? = NSApp.effectiveAppearance,
        onCopy: @escaping () -> Void,
        onEdit: @escaping () -> Void = {},
        onCopyRaw: @escaping () -> Void = {},
        onMarkCopied: @escaping () -> Void = {},
        onToggleSelection: @escaping () -> Void,
        onCmdClick: @escaping () -> Void = {},
        onToggleExpansion: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onTogglePin: (() -> Void)? = nil,
        compactMode: Bool = false
    ) {
        self.card = card
        self.classification = classification
        self.isSelected = isSelected
        self.isRecentlyCopied = isRecentlyCopied
        self.selectionMode = selectionMode
        self.ttlProgressRemaining = ttlProgressRemaining
        self.ttlRemainingMinutes = ttlRemainingMinutes
        self.isExpanded = isExpanded
        self.inheritedAppearance = inheritedAppearance
        self.onCopy = onCopy
        self.onEdit = onEdit
        self.onCopyRaw = onCopyRaw
        self.onMarkCopied = onMarkCopied
        self.onToggleSelection = onToggleSelection
        self.onCmdClick = onCmdClick
        self.onToggleExpansion = onToggleExpansion
        self.onDelete = onDelete
        self.onTogglePin = onTogglePin
        self.compactMode = compactMode
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
            isEmphasized: isCardHoveredState,
            contentPadding: compactMode
                ? EdgeInsets(
                    top: PrimitiveTokens.Size.compactCardPadding,
                    leading: StackLayoutMetrics.compactCardHorizontalInset,
                    bottom: PrimitiveTokens.Size.compactCardPadding,
                    trailing: StackLayoutMetrics.compactCardHorizontalInset
                )
                : EdgeInsets(
                    top: StackLayoutMetrics.cardContentInset,
                    leading: StackLayoutMetrics.cardContentInset,
                    bottom: StackLayoutMetrics.cardContentInset,
                    trailing: StackLayoutMetrics.cardContentInset
                ),
            cornerRadius: compactMode ? PrimitiveTokens.Radius.compactCard : PrimitiveTokens.Radius.md
        ) {
            ZStack(alignment: compactMode ? .leading : .topTrailing) {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    if !compactMode, let screenshotURL = card.screenshotURL {
                        LocalImageThumbnail(
                            url: screenshotURL,
                            height: PrimitiveTokens.Size.notificationThumbnailHeight,
                            accessPolicy: .managedAttachmentOnly
                        )
                    }

                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                        if compactMode {
                            Text(card.text)
                                .font(.system(size: PrimitiveTokens.FontSize.meta, weight: .medium))
                                .foregroundStyle(SemanticTokens.Text.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            let textView = InteractiveDetectedTextView(
                                styledText: styledText
                            )
                                .frame(
                                    height: displayConfiguration.prefersSingleLine
                                        ? nil
                                        : visibleTextHeight(for: overflowMetrics),
                                    alignment: .top
                                )

                            if overflowMetrics.overflowsAtRest || isExpanded {
                                textView.clipped()
                            } else {
                                textView
                            }
                        }

                        if !compactMode && !displayConfiguration.prefersSingleLine && overflowMetrics.overflowsAtRest {
                            overflowAffordance(metrics: overflowMetrics)
                                .padding(.top, StackCardOverflowPolicy.affordanceTopSpacing)
                        }
                    }
                    .padding(.leading, compactMode ? 0 : StackLayoutMetrics.activeCardBodyLeadingReserve)
                }
                .padding(.trailing, compactMode ? 0 : actionColumnReservedWidth)
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

                    if !compactMode {
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
                }
                .frame(width: compactMode ? 0 : actionColumnWidth, alignment: .topTrailing)
                .opacity(compactMode ? 0 : 1)
                .zIndex(1)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel(displayText: visibleInlineText))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .contentShape(Rectangle())
        .overlay {
            CardContextMenuTrigger(menuItems: makeContextMenuItems())
        }
        .onTapGesture {
            if isCommandClickEvent {
                onCmdClick()
            } else if isOptionClickEvent {
                onCopyRaw()
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
        .onChange(of: isCardHoveredState) { _, isEmphasized in
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
                #if DEBUG
                if cardHoverTracingEnabled() {
                    logCardHoverTrace(
                        "PROMPTCUE_HOVER_TRACKER_EVENT state=window_missing_card_area_released"
                    )
                }
                #endif
                return
            }

                if let trackingArea {
                    removeTrackingArea(trackingArea)
                }

                let options: NSTrackingArea.Options = [
                    .mouseEnteredAndExited,
                    .mouseMoved,
                    .activeAlways,
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
                #if DEBUG
                if cardHoverTracingEnabled() {
                    logCardHoverTrace(
                        String(
                            format: "PROMPTCUE_HOVER_TRACKER_EVENT rect_sync entered=%d",
                            cursorInside ? 1 : 0
                        )
                    )
                }
                #endif
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
        StackLayoutMetrics.actionColumnWidth
    }

    private var actionColumnReservedWidth: CGFloat {
        StackLayoutMetrics.actionColumnReservedWidth
    }

    private var textContentWidth: CGFloat {
        StackLayoutMetrics.cardTextWidth
    }

    private func visibleTextHeight(for metrics: StackCardOverflowPolicy.Metrics) -> CGFloat? {
        if isExpanded {
            return nil
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

        if isOptionClickEvent {
            onCopyRaw()
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

    private var isOptionClickEvent: Bool {
        NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option) == true
    }

    private func accessibilityLabel(displayText: String) -> String {
        "Cue: \(displayText)"
    }

    private func makeContextMenuItems() -> [CardContextMenuItem] {
        var items: [CardContextMenuItem] = []
        var tag = 0

        if let onTogglePin {
            items.append(CardContextMenuItem(
                title: card.isPinned ? "Unpin" : "Pin",
                shortcutHint: nil,
                systemImage: card.isPinned ? "pin.slash" : "pin",
                tag: tag,
                isSeparator: false,
                action: onTogglePin
            ))
            tag += 1
            items.append(.separator())
        }

        items.append(CardContextMenuItem(
            title: "Copy Raw",
            shortcutHint: nil,
            systemImage: nil,
            tag: tag,
            isSeparator: false,
            action: onCopyRaw
        ))
        tag += 1
        items.append(CardContextMenuItem(
            title: "Edit",
            shortcutHint: nil,
            systemImage: nil,
            tag: tag,
            isSeparator: false,
            action: onEdit
        ))
        tag += 1

        if !card.isCopied {
            items.append(CardContextMenuItem(
                title: "Mark as Copied",
                shortcutHint: "⌥ click",
                systemImage: nil,
                tag: tag,
                isSeparator: false,
                action: onMarkCopied
            ))
        }

        return items
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

    // Adaptive tokens — resolve at draw time via NSColor, independent of
    // SwiftUI's @Environment(\.colorScheme) propagation timing.
    private static func restingBodyColor(appearance: NSAppearance?) -> Color {
        SemanticTokens.resolvedAdaptiveColor(
            light: NSColor.labelColor.withAlphaComponent(0.74),
            dark: NSColor.secondaryLabelColor.withAlphaComponent(0.78),
            appearance: appearance
        )
    }
    private static func defaultPrimaryIconColor(appearance: NSAppearance?) -> Color {
        SemanticTokens.resolvedAdaptiveColor(
            light: NSColor.secondaryLabelColor.withAlphaComponent(0.80),
            dark: NSColor.white.withAlphaComponent(0.50),
            appearance: appearance
        )
    }
    private static func defaultDeleteIconColor(appearance: NSAppearance?) -> Color {
        SemanticTokens.resolvedAdaptiveColor(
            light: NSColor.secondaryLabelColor.withAlphaComponent(0.76),
            dark: NSColor.white.withAlphaComponent(0.45),
            appearance: appearance
        )
    }
    private static func screenshotPrimaryIconBg(appearance: NSAppearance?) -> Color {
        SemanticTokens.resolvedAdaptiveColor(
            light: NSColor.black.withAlphaComponent(0.02 * 0.72),
            dark: NSColor.white.withAlphaComponent(0.006 * 0.54),
            appearance: appearance
        )
    }
    private static func screenshotDeleteIconBg(appearance: NSAppearance?) -> Color {
        SemanticTokens.resolvedAdaptiveColor(
            light: NSColor.black.withAlphaComponent(0.02 * 0.60),
            dark: NSColor.white.withAlphaComponent(0.006 * 0.46),
            appearance: appearance
        )
    }

    static func resolve(
        card: CaptureCard,
        isSelected: Bool,
        isRecentlyCopied: Bool,
        selectionMode: Bool,
        appearance: NSAppearance?,
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
        } else {
            bodyColor = restingBodyColor(appearance: appearance)
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
            primaryIconColor = defaultPrimaryIconColor(appearance: appearance)
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
        } else {
            deleteIconColor = defaultDeleteIconColor(appearance: appearance)
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
            primaryIconBackground = screenshotPrimaryIconBg(appearance: appearance)
        } else {
            primaryIconBackground = .clear
        }

        let deleteIconBackground: Color
        if isDeleteHovered {
            deleteIconBackground = SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.medium)
        } else if usesPersistentActionBackdrop {
            deleteIconBackground = screenshotDeleteIconBg(appearance: appearance)
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
