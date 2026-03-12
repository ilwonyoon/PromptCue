import AppKit
import PromptCueCore
import SwiftUI

struct CaptureCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let card: CaptureCard
    let classification: ContentClassification
    let availableSuggestedTargets: [CaptureSuggestedTarget]
    let automaticSuggestedTarget: CaptureSuggestedTarget?
    let isSelected: Bool
    let isRecentlyCopied: Bool
    let selectionMode: Bool
    let isExpanded: Bool
    let onCopy: () -> Void
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

    private var actionStyle: CaptureCardActionStyle {
        CaptureCardActionStyle.resolve(
            card: card,
            isSelected: isSelected,
            isRecentlyCopied: isRecentlyCopied,
            selectionMode: selectionMode,
            colorScheme: colorScheme,
            isCardHovered: isCardHovered,
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
        isExpanded: Bool,
        onCopy: @escaping () -> Void,
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
        self.isExpanded = isExpanded
        self.onCopy = onCopy
        self.onCopyRaw = onCopyRaw
        self.onToggleSelection = onToggleSelection
        self.onCmdClick = onCmdClick
        self.onToggleExpansion = onToggleExpansion
        self.onDelete = onDelete
        self.onRefreshSuggestedTargets = onRefreshSuggestedTargets
        self.onAssignSuggestedTarget = onAssignSuggestedTarget
    }

    var body: some View {
        let displayConfiguration = InteractiveDetectedTextView.displayConfiguration(
            text: card.text,
            classification: classification
        )
        let overflowMetrics = StackCardOverflowPolicy.metrics(
            for: displayConfiguration.text,
            cacheIdentity: card.id,
            layoutVariant: displayConfiguration.layoutVariant,
            availableWidth: textContentWidth
        )

        StackNotificationCardSurface(
            isSelected: isSelected,
            isEmphasized: isCardHovered || isCopyHovered || isDeleteHovered || isShowingCopyFeedback
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

                    InteractiveDetectedTextView(
                        text: card.text,
                        classification: classification,
                        baseColor: actionStyle.bodyColor
                    )
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
                        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                            isCopyHovered = hovered
                        }
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
                        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                            isDeleteHovered = hovered
                        }
                    }
                }
                .frame(width: actionColumnWidth, alignment: .topTrailing)
                .zIndex(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Cue: \(card.text)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy Raw", action: onCopyRaw)
        }
        .onTapGesture {
            if isCommandClickEvent {
                onCmdClick()
            } else {
                performPrimaryAction()
            }
        }
        .onContinuousHover { phase in
            let hovered: Bool
            switch phase {
            case .active:
                hovered = true
            case .ended:
                hovered = false
            }
            withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                isCardHovered = hovered
            }
        }
    }

    private var contentSpacing: CGFloat {
        if card.screenshotURL != nil {
            return PrimitiveTokens.Space.sm
        }

        return PrimitiveTokens.Space.xxs
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
            withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                isOverflowAffordanceHovered = hovered
            }
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

        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
            isShowingCopyFeedback = true
        }

        onCopy()
        DispatchQueue.main.asyncAfter(deadline: .now() + PrimitiveTokens.Motion.quick) {
            isShowingCopyFeedback = false
        }
    }

    private var isCommandClickEvent: Bool {
        NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) == true
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
        let isPrimaryCopyHover = isCopyHovered || (isCardHovered && !selectionMode)

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
