import AppKit
import PromptCueCore
import SwiftUI

struct CaptureCardView: View {
    let card: CaptureCard
    let availableSuggestedTargets: [CaptureSuggestedTarget]
    let automaticSuggestedTarget: CaptureSuggestedTarget?
    let isSelected: Bool
    let selectionMode: Bool
    let onCopy: () -> Void
    let onToggleSelection: () -> Void
    let onDelete: () -> Void
    let onRefreshSuggestedTargets: () -> Void
    let onAssignSuggestedTarget: (CaptureSuggestedTarget) -> Void
    @State private var isCardHovered = false
    @State private var isCopyHovered = false
    @State private var isDeleteHovered = false
    @State private var isShowingCopyFeedback = false

    init(
        card: CaptureCard,
        availableSuggestedTargets: [CaptureSuggestedTarget] = [],
        automaticSuggestedTarget: CaptureSuggestedTarget? = nil,
        isSelected: Bool,
        selectionMode: Bool,
        onCopy: @escaping () -> Void,
        onToggleSelection: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRefreshSuggestedTargets: @escaping () -> Void = {},
        onAssignSuggestedTarget: @escaping (CaptureSuggestedTarget) -> Void = { _ in }
    ) {
        self.card = card
        self.availableSuggestedTargets = availableSuggestedTargets
        self.automaticSuggestedTarget = automaticSuggestedTarget
        self.isSelected = isSelected
        self.selectionMode = selectionMode
        self.onCopy = onCopy
        self.onToggleSelection = onToggleSelection
        self.onDelete = onDelete
        self.onRefreshSuggestedTargets = onRefreshSuggestedTargets
        self.onAssignSuggestedTarget = onAssignSuggestedTarget
    }

    var body: some View {
        CardSurface(
            isSelected: isSelected,
            isEmphasized: isCardHovered || isCopyHovered || isDeleteHovered || isShowingCopyFeedback,
            style: .notification
        ) {
            HStack(alignment: .top, spacing: PrimitiveTokens.Space.sm) {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                    VStack(alignment: .leading, spacing: contentSpacing) {
                        if let screenshotURL = card.screenshotURL {
                            LocalImageThumbnail(
                                url: screenshotURL,
                                height: PrimitiveTokens.Size.notificationThumbnailHeight
                            )
                            .opacity(card.isCopied ? PrimitiveTokens.Opacity.soft : 1)
                        }

                        Text(card.text)
                            .font(PrimitiveTokens.Typography.body)
                            .foregroundStyle(bodyColor)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(PrimitiveTokens.Space.xxxs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SuggestedTargetOriginButton(
                        currentTarget: card.suggestedTarget,
                        availableTargets: availableSuggestedTargets,
                        emptyLabel: "Choose working app",
                        onRefreshTargets: onRefreshSuggestedTargets,
                        onSelectTarget: onAssignSuggestedTarget,
                        automaticTarget: automaticSuggestedTarget
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: PrimitiveTokens.Space.xs) {
                    iconButton(
                        systemName: copyIconSystemName,
                        foregroundColor: copyIconColor,
                        backgroundColor: copyIconBackground,
                        action: performCopy
                    )
                    .onHover { hovered in
                        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                            isCopyHovered = hovered
                        }
                    }

                    iconButton(
                        systemName: "trash",
                        foregroundColor: deleteIconColor,
                        backgroundColor: deleteIconBackground,
                        action: onDelete
                    )
                    .onHover { hovered in
                        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                            isDeleteHovered = hovered
                        }
                    }
                }
                .frame(width: actionColumnWidth, alignment: .topTrailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: performPrimaryAction)
            .onHover { hovered in
                withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
                    isCardHovered = hovered
                }
            }
        }
    }

    private var contentSpacing: CGFloat {
        if card.screenshotURL != nil {
            return PrimitiveTokens.Space.sm
        }

        return PrimitiveTokens.Space.xxs
    }

    private var bodyColor: Color {
        if isSelected || isCardHovered || isCopyHovered || isDeleteHovered {
            return SemanticTokens.Text.primary
        }

        if card.isCopied {
            return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.soft)
        }

        return SemanticTokens.Text.primary
    }

    private var copyIconColor: Color {
        if isDeleteHovered {
            return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.subtle)
        }

        if isShowingCopyFeedback {
            return SemanticTokens.Text.primary
        }

        if isCopyHovered || (isCardHovered && !selectionMode) {
            return SemanticTokens.Text.primary
        }

        return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.soft)
    }

    private var copyIconSystemName: String {
        if isShowingCopyFeedback {
            return "checkmark"
        }

        if isCopyHovered || (isCardHovered && !selectionMode) {
            return "doc.on.doc.fill"
        }

        return "doc.on.doc"
    }

    private var deleteIconColor: Color {
        if isDeleteHovered {
            return SemanticTokens.Text.primary
        }

        if card.isCopied {
            return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.subtle)
        }

        return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.soft)
    }

    private var copyIconBackground: Color {
        if isDeleteHovered {
            return .clear
        }

        if isShowingCopyFeedback {
            return SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.strong)
        }

        if isCopyHovered || (isCardHovered && !selectionMode) {
            return SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.strong)
        }

        return .clear
    }

    private var deleteIconBackground: Color {
        if isDeleteHovered {
            return SemanticTokens.Surface.accentFill.opacity(PrimitiveTokens.Opacity.medium)
        }

        return .clear
    }

    private var actionColumnWidth: CGFloat {
        PrimitiveTokens.Space.xl
    }

    private func performPrimaryAction() {
        if selectionMode {
            onToggleSelection()
            return
        }

        performCopy()
    }

    private func performCopy() {
        guard !isShowingCopyFeedback else {
            return
        }

        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.quick)) {
            isShowingCopyFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + PrimitiveTokens.Motion.quick) {
            onCopy()
            isShowingCopyFeedback = false
        }
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

struct SuggestedTargetOriginButton: View {
    let currentTarget: CaptureSuggestedTarget?
    let availableTargets: [CaptureSuggestedTarget]
    let emptyLabel: String
    let onRefreshTargets: () -> Void
    let onSelectTarget: (CaptureSuggestedTarget) -> Void
    let automaticTarget: CaptureSuggestedTarget?
    let isAutomaticSelectionActive: Bool
    let onUseAutomaticTarget: (() -> Void)?
    let onActivateInlineChooser: (() -> Void)?
    let controlWidth: CGFloat?

    @State private var isPopoverPresented = false

    init(
        currentTarget: CaptureSuggestedTarget?,
        availableTargets: [CaptureSuggestedTarget],
        emptyLabel: String,
        onRefreshTargets: @escaping () -> Void,
        onSelectTarget: @escaping (CaptureSuggestedTarget) -> Void,
        automaticTarget: CaptureSuggestedTarget? = nil,
        isAutomaticSelectionActive: Bool = false,
        onUseAutomaticTarget: (() -> Void)? = nil,
        onActivateInlineChooser: (() -> Void)? = nil,
        controlWidth: CGFloat? = nil
    ) {
        self.currentTarget = currentTarget
        self.availableTargets = availableTargets
        self.emptyLabel = emptyLabel
        self.onRefreshTargets = onRefreshTargets
        self.onSelectTarget = onSelectTarget
        self.automaticTarget = automaticTarget
        self.isAutomaticSelectionActive = isAutomaticSelectionActive
        self.onUseAutomaticTarget = onUseAutomaticTarget
        self.onActivateInlineChooser = onActivateInlineChooser
        self.controlWidth = controlWidth
    }

    var body: some View {
        Button {
            if let onActivateInlineChooser {
                onActivateInlineChooser()
            } else {
                onRefreshTargets()
                isPopoverPresented = true
            }
        } label: {
            SuggestedTargetControlChrome(controlWidth: controlWidth) {
                SuggestedTargetIdentityLine(
                    target: displayedTarget,
                    fallbackLabel: emptyLabel,
                    showChevron: true
                )
            }
        }
        .buttonStyle(.plain)
        .help(currentTargetTooltip)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            SuggestedTargetChooserListView(
                selectedTarget: currentTarget ?? automaticTarget,
                highlightedTarget: currentTarget ?? automaticTarget,
                availableTargets: availableTargets,
                emptyLabel: emptyLabel,
                automaticTarget: automaticTarget,
                isAutomaticSelectionActive: isAutomaticSelectionActive,
                isAutomaticHighlighted: isAutomaticSelectionActive,
                onHighlightTarget: nil,
                onHighlightAutomaticTarget: nil,
                controlWidth: nil,
                fixedWidth: 280,
                onRefreshTargets: onRefreshTargets,
                onSelectTarget: { target in
                    onSelectTarget(target)
                    isPopoverPresented = false
                },
                onUseAutomaticTarget: onUseAutomaticTarget.map { action in
                    {
                        action()
                        isPopoverPresented = false
                    }
                }
            )
        }
    }

    private var displayedTarget: CaptureSuggestedTarget? {
        currentTarget ?? automaticTarget ?? availableTargets.first
    }

    private var currentTargetTooltip: String {
        guard let displayedTarget else {
            return emptyLabel
        }

        if let debugDetailText = displayedTarget.debugDetailText {
            return "\(displayedTarget.workspaceLabel)\n\(displayedTarget.chooserSecondaryLabel)\n\(debugDetailText)"
        }

        return "\(displayedTarget.workspaceLabel)\n\(displayedTarget.chooserSecondaryLabel)"
    }
}

struct SuggestedTargetChooserListView: View {
    let selectedTarget: CaptureSuggestedTarget?
    let highlightedTarget: CaptureSuggestedTarget?
    let availableTargets: [CaptureSuggestedTarget]
    let emptyLabel: String
    let automaticTarget: CaptureSuggestedTarget?
    let isAutomaticSelectionActive: Bool
    let isAutomaticHighlighted: Bool
    let onHighlightTarget: ((CaptureSuggestedTarget) -> Void)?
    let onHighlightAutomaticTarget: (() -> Void)?
    let controlWidth: CGFloat?
    let fixedWidth: CGFloat?
    let onRefreshTargets: () -> Void
    let onSelectTarget: (CaptureSuggestedTarget) -> Void
    let onUseAutomaticTarget: (() -> Void)?
    @State private var visibleWindowStartIndex = 0
    @State private var suppressNextAutoScroll = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppUIConstants.captureChooserPromptBottomSpacing) {
            chooserHeader
            chooserBody
        }
        .frame(width: fixedWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppUIConstants.captureChooserSurfaceHorizontalPadding)
        .padding(.vertical, AppUIConstants.captureChooserSurfaceVerticalPadding)
        .onAppear {
            onRefreshTargets()
        }
    }

    private var filteredAvailableTargets: [CaptureSuggestedTarget] {
        guard let automaticTarget else {
            return availableTargets
        }

        return availableTargets.filter { $0.choiceKey != automaticTarget.choiceKey }
    }

    private var displayedTargets: [CaptureSuggestedTarget] {
        if let automaticTarget {
            return [automaticTarget] + filteredAvailableTargets
        }

        return filteredAvailableTargets
    }

    private var hasAnyChoices: Bool {
        automaticTarget != nil || !filteredAvailableTargets.isEmpty
    }

    @ViewBuilder
    private var chooserBody: some View {
        if !hasAnyChoices {
            Text(emptyLabel)
                .font(PrimitiveTokens.Typography.meta)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, PrimitiveTokens.Space.sm)
                .frame(height: chooserViewportHeight, alignment: .top)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppUIConstants.captureChooserSectionSpacing) {
                        ForEach(displayedTargets, id: \.choiceKey) { target in
                            chooserRow(
                                target: target,
                                isSelected: target == selectedTarget || (isAutomaticSelectionActive && target == automaticTarget),
                                isHighlighted: target == automaticTarget ? isAutomaticHighlighted : (!isAutomaticHighlighted && target == highlightedTarget),
                                isRecent: target == automaticTarget,
                                onHoverHighlight: {
                                    suppressNextAutoScroll = true
                                    if target == automaticTarget {
                                        if let onHighlightAutomaticTarget {
                                            onHighlightAutomaticTarget()
                                        } else {
                                            onHighlightTarget?(target)
                                        }
                                    } else {
                                        onHighlightTarget?(target)
                                    }
                                }
                            ) {
                                if target == automaticTarget {
                                    if let onUseAutomaticTarget {
                                        onUseAutomaticTarget()
                                    } else {
                                        onSelectTarget(target)
                                    }
                                } else {
                                    onSelectTarget(target)
                                }
                            }
                            .id(choiceID(for: target))
                        }
                    }
                }
                .frame(height: chooserViewportHeight, alignment: .top)
                .scrollIndicators(.hidden)
                .onAppear {
                    visibleWindowStartIndex = 0
                    scrollHighlightedRowIfNeeded(using: proxy)
                }
                .onChange(of: highlightedChoiceID) { _, _ in
                    if suppressNextAutoScroll {
                        suppressNextAutoScroll = false
                        return
                    }
                    scrollHighlightedRowIfNeeded(using: proxy)
                }
            }
        }
    }

    private var chooserViewportHeight: CGFloat {
        let visibleRowUnits = AppUIConstants.captureChooserVisibleRowUnits(for: totalVisibleRowCount)
        let fullRowCount = max(Int(floor(visibleRowUnits)), 1)
        let partialRowUnits = max(visibleRowUnits - CGFloat(fullRowCount), 0)

        return (CGFloat(fullRowCount) * AppUIConstants.captureChooserRowHeight)
            + (CGFloat(max(0, fullRowCount - 1)) * AppUIConstants.captureChooserRowSpacing)
            + (partialRowUnits * AppUIConstants.captureChooserRowHeight)
    }

    private var totalVisibleRowCount: Int {
        let automaticCount = automaticTarget == nil ? 0 : 1
        return automaticCount + filteredAvailableTargets.count
    }

    private var automaticChoiceID: String {
        "__automatic__"
    }

    private var highlightedChoiceID: String? {
        if isAutomaticHighlighted, automaticTarget != nil {
            return automaticChoiceID
        }

        return highlightedTarget?.choiceKey
    }

    private var highlightedChoiceIndex: Int? {
        guard let highlightedChoiceID else {
            return nil
        }

        return displayedTargets.firstIndex { choiceID(for: $0) == highlightedChoiceID }
    }

    private var keyboardVisibleRowCapacity: Int {
        min(max(totalVisibleRowCount, 1), AppUIConstants.captureChooserMaxVisibleRows)
    }

    private var selectableTargetCount: Int {
        Set(displayedTargets.map(\.choiceKey)).count
    }

    private func scrollHighlightedRowIfNeeded(using proxy: ScrollViewProxy) {
        guard let highlightedChoiceIndex else {
            return
        }

        let visibleCapacity = max(keyboardVisibleRowCapacity, 1)
        let maxStartIndex = max(displayedTargets.count - visibleCapacity, 0)
        let clampedVisibleStart = min(visibleWindowStartIndex, maxStartIndex)

        if highlightedChoiceIndex < clampedVisibleStart {
            visibleWindowStartIndex = highlightedChoiceIndex
            let targetID = choiceID(for: displayedTargets[highlightedChoiceIndex])
            DispatchQueue.main.async {
                proxy.scrollTo(targetID, anchor: .top)
            }
            return
        }

        if highlightedChoiceIndex >= clampedVisibleStart + visibleCapacity {
            visibleWindowStartIndex = min(highlightedChoiceIndex - visibleCapacity + 1, maxStartIndex)
            let targetID = choiceID(for: displayedTargets[highlightedChoiceIndex])
            DispatchQueue.main.async {
                proxy.scrollTo(targetID, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func chooserRow(
        target: CaptureSuggestedTarget,
        isSelected: Bool,
        isHighlighted: Bool,
        isRecent: Bool,
        onHoverHighlight: (() -> Void)?,
            action: @escaping () -> Void
    ) -> some View {
        SuggestedTargetChooserRow(
            target: target,
            controlWidth: controlWidth,
            isSelected: isSelected,
            isHighlighted: isHighlighted,
            isRecent: isRecent,
            onHoverHighlight: onHoverHighlight,
            action: action
        )
    }

    private func choiceID(for target: CaptureSuggestedTarget) -> String {
        if target == automaticTarget {
            return automaticChoiceID
        }

        return target.choiceKey
    }

    private var chooserHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: PrimitiveTokens.Space.sm) {
            Text("For which AI workflow?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SemanticTokens.Text.primary.opacity(0.98))

            Text(selectableTargetCountLabel)
                .font(PrimitiveTokens.Typography.meta)
                .foregroundStyle(SemanticTokens.Text.secondary)

            Spacer(minLength: PrimitiveTokens.Space.md)

            chooserTabAffordance
        }
        .frame(height: AppUIConstants.captureChooserPromptLineHeight, alignment: .leading)
        .padding(.vertical, AppUIConstants.captureChooserPromptVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectableTargetCountLabel: String {
        "\(selectableTargetCount)"
    }

    private var chooserTabAffordance: some View {
        Text("Tab")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(SemanticTokens.Text.secondary.opacity(0.9))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.36))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 0.8)
            }
            .accessibilityLabel("Tab to select")
    }
}

private struct SuggestedTargetChooserRow: View {
    let target: CaptureSuggestedTarget
    let controlWidth: CGFloat?
    let isSelected: Bool
    let isHighlighted: Bool
    let isRecent: Bool
    let onHoverHighlight: (() -> Void)?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            SuggestedTargetControlChrome(
                controlWidth: controlWidth,
                minimumHeight: AppUIConstants.captureChooserRowHeight,
                backgroundFill: backgroundFill,
                borderColor: borderColor
            ) {
                SuggestedTargetIdentityLine(
                    target: target,
                    fallbackLabel: target.fallbackDisplayLabel,
                    style: .chooser,
                    showsRecent: isRecent,
                    isSelected: isSelected
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            isHovered = hovered
        }
        .help(target.helpText)
    }

    private var backgroundFill: Color {
        if isHighlighted {
            return Color(nsColor: .controlColor).opacity(0.56)
        }

        if isHovered {
            return Color(nsColor: .controlColor).opacity(0.34)
        }

        return Color.black.opacity(0.028)
    }

    private var borderColor: Color {
        if isHighlighted {
            return Color(nsColor: .separatorColor).opacity(0.42)
        }

        if isHovered {
            return Color(nsColor: .separatorColor).opacity(0.28)
        }

        return Color(nsColor: .separatorColor).opacity(0.18)
    }
}

private struct SuggestedTargetControlChrome<Content: View>: View {
    let controlWidth: CGFloat?
    let minimumHeight: CGFloat?
    let backgroundFill: Color
    let borderColor: Color
    @ViewBuilder let content: Content

    init(
        controlWidth: CGFloat?,
        minimumHeight: CGFloat? = nil,
        backgroundFill: Color = Color.black.opacity(0.045),
        borderColor: Color = Color(nsColor: .separatorColor).opacity(0.42),
        @ViewBuilder content: () -> Content
    ) {
        self.controlWidth = controlWidth
        self.minimumHeight = minimumHeight
        self.backgroundFill = backgroundFill
        self.borderColor = borderColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, PrimitiveTokens.Space.xs + 1)
            .padding(.vertical, PrimitiveTokens.Space.xxxs + 3)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(borderColor)
                    }
            }
            .frame(width: controlWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: controlWidth == nil ? .leading : .center)
    }
}

private struct SuggestedTargetIdentityLine: View {
    enum Style {
        case accessory
        case chooser
    }

    let target: CaptureSuggestedTarget?
    let fallbackLabel: String
    var style: Style = .accessory
    var showChevron: Bool = false
    var showsRecent: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: PrimitiveTokens.Space.xxxs + 3) {
            Image(nsImage: SuggestedTargetIconProvider.icon(for: target?.bundleIdentifier))
                .resizable()
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(primaryLabel)
                .font(.system(size: PrimitiveTokens.FontSize.meta, weight: .medium))
                .foregroundStyle(primaryColor)
                .lineLimit(1)
                .truncationMode(.tail)

            if let secondaryLabel {
                Text("· \(secondaryLabel)")
                    .font(.system(size: PrimitiveTokens.FontSize.micro, weight: .regular))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: PrimitiveTokens.Space.xxxs)

            if showsRecent {
                Text("Recent")
                    .font(.system(size: PrimitiveTokens.FontSize.micro, weight: .medium))
                    .foregroundStyle(secondaryColor)
                    .padding(.horizontal, PrimitiveTokens.Space.xxxs + 1)
                    .padding(.vertical, 2)
                    .background {
                        Capsule(style: .continuous)
                            .fill(recentFillColor)
                    }
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SemanticTokens.Text.accent)
            }

            if showChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(SemanticTokens.Text.secondary.opacity(0.5))
            }
        }
    }

    private var primaryLabel: String {
        target?.workspaceLabel ?? fallbackLabel
    }

    private var secondaryLabel: String? {
        guard let target,
              let shortBranchLabel = target.shortBranchLabel,
              shortBranchLabel.localizedCaseInsensitiveCompare(target.workspaceLabel) != .orderedSame else {
            return nil
        }

        return shortBranchLabel
    }

    private var primaryColor: Color {
        switch style {
        case .accessory:
            return SemanticTokens.Text.secondary.opacity(0.92)
        case .chooser:
            return SemanticTokens.Text.primary.opacity(0.96)
        }
    }

    private var secondaryColor: Color {
        switch style {
        case .accessory:
            return SemanticTokens.Text.secondary.opacity(0.62)
        case .chooser:
            return SemanticTokens.Text.secondary.opacity(0.82)
        }
    }

    private var recentFillColor: Color {
        switch style {
        case .accessory:
            return Color.black.opacity(0.04)
        case .chooser:
            return Color(nsColor: .controlColor).opacity(0.52)
        }
    }
}

private extension CaptureSuggestedTarget {
    var helpText: String {
        if let debugDetailText {
            return "\(workspaceLabel)\n\(chooserSecondaryLabel)\n\(debugDetailText)"
        }

        return "\(workspaceLabel)\n\(chooserSecondaryLabel)"
    }
}

@MainActor
private enum SuggestedTargetIconProvider {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleIdentifier: String?) -> NSImage {
        guard let bundleIdentifier else {
            let image = NSWorkspace.shared.icon(for: .application)
            image.size = NSSize(width: 14, height: 14)
            return image
        }

        if let cached = cache[bundleIdentifier] {
            return cached
        }

        let image: NSImage
        if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        } else {
            image = NSWorkspace.shared.icon(for: .application)
        }

        image.size = NSSize(width: 14, height: 14)
        cache[bundleIdentifier] = image
        return image
    }
}
