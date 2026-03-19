import AppKit
import PromptCueCore
import SwiftUI

struct CaptureSuggestedTargetAccessoryView: View {
    let currentTarget: CaptureSuggestedTarget?
    let availableTargets: [CaptureSuggestedTarget]
    let automaticTarget: CaptureSuggestedTarget?
    let isAutomaticSelectionActive: Bool
    let onRefreshTargets: () -> Void
    let onSelectTarget: (CaptureSuggestedTarget) -> Void
    let onUseAutomaticTarget: () -> Void
    let onActivateInlineChooser: () -> Void

    var body: some View {
        SuggestedTargetOriginControl(
            currentTarget: currentTarget,
            availableTargets: availableTargets,
            emptyLabel: "Choose working app",
            onRefreshTargets: onRefreshTargets,
            onSelectTarget: onSelectTarget,
            automaticTarget: automaticTarget,
            isAutomaticSelectionActive: isAutomaticSelectionActive,
            onUseAutomaticTarget: onUseAutomaticTarget,
            onActivateInlineChooser: onActivateInlineChooser,
            controlWidth: AppUIConstants.captureSelectorControlWidth,
            chromeStyle: .capturePanel
        )
        .frame(
            maxWidth: .infinity,
            minHeight: AppUIConstants.captureDebugLineHeight,
            alignment: .leading
        )
    }
}

struct CaptureCardSuggestedTargetAccessoryView: View {
    let currentTarget: CaptureSuggestedTarget?
    let availableTargets: [CaptureSuggestedTarget]
    let automaticTarget: CaptureSuggestedTarget?
    let onRefreshTargets: () -> Void
    let onAssignTarget: (CaptureSuggestedTarget) -> Void

    var body: some View {
        SuggestedTargetOriginControl(
            currentTarget: currentTarget,
            availableTargets: availableTargets,
            emptyLabel: "Choose working app",
            onRefreshTargets: onRefreshTargets,
            onSelectTarget: onAssignTarget,
            automaticTarget: automaticTarget,
            isAutomaticSelectionActive: false,
            onUseAutomaticTarget: nil,
            onActivateInlineChooser: nil,
            controlWidth: nil,
            chromeStyle: .stackCard
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CaptureSuggestedTargetChooserPanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SuggestedTargetChooserListView(
            selectedTarget: model.captureChooserTarget,
            focusedTarget: model.focusedCaptureSuggestedTarget,
            availableTargets: model.availableSuggestedTargets,
            emptyLabel: "No open supported apps",
            automaticTarget: model.automaticSuggestedTarget,
            isAutomaticSelected: model.isCaptureSuggestedTargetAutomatic,
            isAutomaticFocused: model.isAutomaticCaptureSuggestedTargetFocused,
            controlWidth: AppUIConstants.captureSelectorControlWidth,
            fixedWidth: nil,
            surfaceTopPadding: 0,
            surfaceBottomPadding: 0,
            headerTopPadding: AppUIConstants.captureChooserPanelHeaderTopPadding,
            headerBottomPadding: AppUIConstants.captureChooserPanelHeaderBottomPadding,
            allowsPeekRow: false,
            onRefreshTargets: model.refreshAvailableSuggestedTargets,
            onSelectTarget: model.chooseDraftSuggestedTarget,
            onUseAutomaticTarget: model.clearDraftSuggestedTargetOverride
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SuggestedTargetOriginControl: View {
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
    let chromeStyle: SuggestedTargetAccessoryChromeStyle

    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            if let onActivateInlineChooser {
                onActivateInlineChooser()
            } else {
                onRefreshTargets()
                isPopoverPresented = true
            }
        } label: {
            SuggestedTargetAccessoryChrome(
                controlWidth: controlWidth,
                style: chromeStyle
            ) {
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
                focusedTarget: currentTarget ?? automaticTarget,
                availableTargets: availableTargets,
                emptyLabel: emptyLabel,
                automaticTarget: automaticTarget,
                isAutomaticSelected: isAutomaticSelectionActive,
                isAutomaticFocused: isAutomaticSelectionActive,
                controlWidth: nil,
                fixedWidth: nil,
                surfaceTopPadding: AppUIConstants.captureChooserSurfaceVerticalPadding,
                surfaceBottomPadding: AppUIConstants.captureChooserSurfaceVerticalPadding,
                headerTopPadding: AppUIConstants.captureChooserPromptVerticalPadding,
                headerBottomPadding: AppUIConstants.captureChooserPromptVerticalPadding,
                allowsPeekRow: true,
                identityStyle: .accessory,
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
            .padding(.horizontal, PrimitiveTokens.Space.md)
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

private enum SuggestedTargetChooserRowState {
    case selected
    case hovered
    case idle
}

private enum SuggestedTargetAccessoryChromeStyle {
    case capturePanel
    case stackCard

    var backgroundFill: Color {
        SemanticTokens.Surface.captureChooserRowFill
    }

    var hoverFill: Color {
        switch self {
        case .capturePanel:
            return SemanticTokens.Surface.captureChooserRowHoverFill
        case .stackCard:
            return SemanticTokens.adaptiveColor(
                light: NSColor.black.withAlphaComponent(0.082),
                dark: NSColor.white.withAlphaComponent(0.058)
            )
        }
    }
}

private struct SuggestedTargetChooserListView: View {
    let selectedTarget: CaptureSuggestedTarget?
    let focusedTarget: CaptureSuggestedTarget?
    let availableTargets: [CaptureSuggestedTarget]
    let emptyLabel: String
    let automaticTarget: CaptureSuggestedTarget?
    let isAutomaticSelected: Bool
    let isAutomaticFocused: Bool
    let controlWidth: CGFloat?
    let fixedWidth: CGFloat?
    let surfaceTopPadding: CGFloat
    let surfaceBottomPadding: CGFloat
    let headerTopPadding: CGFloat
    let headerBottomPadding: CGFloat
    let allowsPeekRow: Bool
    var identityStyle: SuggestedTargetIdentityLine.Style = .chooser
    let onRefreshTargets: () -> Void
    let onSelectTarget: (CaptureSuggestedTarget) -> Void
    let onUseAutomaticTarget: (() -> Void)?

    @State private var visibleWindowStartIndex = 0
    var body: some View {
        VStack(alignment: .leading, spacing: AppUIConstants.captureChooserPromptBottomSpacing) {
            chooserHeader
            chooserBody
        }
        .frame(width: fixedWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppUIConstants.captureChooserSurfaceHorizontalPadding)
        .padding(.top, surfaceTopPadding)
        .padding(.bottom, surfaceBottomPadding)
        .onAppear {
            onRefreshTargets()
        }
    }

    private var filteredAvailableTargets: [CaptureSuggestedTarget] {
        guard let automaticTarget else {
            return availableTargets
        }

        return availableTargets.filter {
            $0.canonicalIdentityKey != automaticTarget.canonicalIdentityKey
        }
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
                        ForEach(displayedTargets, id: \.canonicalIdentityKey) { target in
                            chooserRow(
                                target: target,
                                rowState: rowState(for: target),
                                isRecent: target == automaticTarget
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
                .onChange(of: focusedChoiceID) { _, _ in
                    scrollHighlightedRowIfNeeded(using: proxy)
                }
            }
        }
    }

    private var chooserViewportHeight: CGFloat {
        let visibleRowUnits = AppUIConstants.captureChooserVisibleRowUnits(
            for: totalVisibleRowCount,
            allowsPeekRow: allowsPeekRow
        )
        let fullRowCount = max(Int(floor(visibleRowUnits)), 1)
        let partialRowUnits = max(visibleRowUnits - CGFloat(fullRowCount), 0)
        let interRowSpacing = AppUIConstants.captureChooserSectionSpacing

        return (CGFloat(fullRowCount) * AppUIConstants.captureChooserRowHeight)
            + (CGFloat(max(0, fullRowCount - 1)) * interRowSpacing)
            + (partialRowUnits * AppUIConstants.captureChooserRowHeight)
    }

    private var totalVisibleRowCount: Int {
        let automaticCount = automaticTarget == nil ? 0 : 1
        return automaticCount + filteredAvailableTargets.count
    }

    private var automaticChoiceID: String {
        "__automatic__"
    }

    private var selectedChoiceID: String? {
        if isAutomaticSelected, automaticTarget != nil {
            return automaticChoiceID
        }

        return selectedTarget?.canonicalIdentityKey
    }

    private var focusedChoiceID: String? {
        if isAutomaticFocused, automaticTarget != nil {
            return automaticChoiceID
        }

        return focusedTarget?.canonicalIdentityKey
    }

    private var highlightedChoiceIndex: Int? {
        guard let focusedChoiceID else {
            return nil
        }

        return displayedTargets.firstIndex { choiceID(for: $0) == focusedChoiceID }
    }

    private var keyboardVisibleRowCapacity: Int {
        min(max(totalVisibleRowCount, 1), AppUIConstants.captureChooserMaxVisibleRows)
    }

    private var selectableTargetCount: Int {
        Set(displayedTargets.map(\.canonicalIdentityKey)).count
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
        rowState: SuggestedTargetChooserRowState,
        isRecent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        SuggestedTargetChooserRow(
            target: target,
            controlWidth: controlWidth,
            identityStyle: identityStyle,
            rowState: rowState,
            isRecent: isRecent,
            action: action
        )
    }

    private func rowState(for target: CaptureSuggestedTarget) -> SuggestedTargetChooserRowState {
        let targetChoiceID = choiceID(for: target)
        let activeChoiceID = focusedChoiceID ?? selectedChoiceID

        if targetChoiceID == activeChoiceID {
            return .selected
        }

        return .idle
    }

    private func choiceID(for target: CaptureSuggestedTarget) -> String {
        if target == automaticTarget {
            return automaticChoiceID
        }

        return target.canonicalIdentityKey
    }

    private var chooserHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: PrimitiveTokens.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("For which AI workflow?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SemanticTokens.Text.primary.opacity(0.98))

                Text("\(selectableTargetCount)")
                    .font(PrimitiveTokens.Typography.meta)
                    .foregroundStyle(SemanticTokens.Text.secondary)
            }

            Spacer(minLength: PrimitiveTokens.Space.md)

            Text("tab to select")
                .font(.system(size: PrimitiveTokens.FontSize.micro, weight: .regular))
                .foregroundStyle(SemanticTokens.Text.secondary.opacity(0.72))
                .accessibilityLabel("Tab to select")
        }
        .frame(height: AppUIConstants.captureChooserPromptLineHeight, alignment: .leading)
        .padding(.top, headerTopPadding)
        .padding(.bottom, headerBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SuggestedTargetChooserRow: View {
    let target: CaptureSuggestedTarget
    let controlWidth: CGFloat?
    var identityStyle: SuggestedTargetIdentityLine.Style = .chooser
    let rowState: SuggestedTargetChooserRowState
    let isRecent: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            SuggestedTargetChooserRowChrome(
                controlWidth: controlWidth,
                minimumHeight: AppUIConstants.captureChooserRowHeight,
                rowState: renderState
            ) {
                SuggestedTargetIdentityLine(
                    target: target,
                    fallbackLabel: target.fallbackDisplayLabel,
                    style: identityStyle,
                    showsRecent: isRecent,
                    isSelected: renderState == .selected
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            isHovered = hovered
        }
        .help(target.helpText)
    }

    private var renderState: SuggestedTargetChooserRowState {
        switch rowState {
        case .selected:
            return rowState
        case .hovered, .idle:
            return isHovered ? .hovered : .idle
        }
    }
}

private struct SuggestedTargetAccessoryChrome<Content: View>: View {
    let controlWidth: CGFloat?
    let minimumHeight: CGFloat?
    let style: SuggestedTargetAccessoryChromeStyle
    @ViewBuilder let content: Content
    @State private var isHovered = false

    init(
        controlWidth: CGFloat?,
        minimumHeight: CGFloat? = nil,
        style: SuggestedTargetAccessoryChromeStyle = .capturePanel,
        @ViewBuilder content: () -> Content
    ) {
        self.controlWidth = controlWidth
        self.minimumHeight = minimumHeight
        self.style = style
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, PrimitiveTokens.Space.xs + 1)
            .padding(.vertical, PrimitiveTokens.Space.xxxs + 3)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .background {
                chromeShape
                    .fill(isHovered ? style.hoverFill : style.backgroundFill)
            }
            .clipShape(chromeShape)
            .contentShape(chromeShape)
            .frame(width: controlWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: controlWidth == nil ? .leading : .center)
            .onHover { hovered in
                isHovered = hovered
            }
    }

    private var chromeShape: Capsule {
        Capsule(style: .continuous)
    }
}

private struct SuggestedTargetChooserRowChrome<Content: View>: View {
    let controlWidth: CGFloat?
    let minimumHeight: CGFloat?
    let rowState: SuggestedTargetChooserRowState
    @ViewBuilder let content: Content

    init(
        controlWidth: CGFloat?,
        minimumHeight: CGFloat? = nil,
        rowState: SuggestedTargetChooserRowState,
        @ViewBuilder content: () -> Content
    ) {
        self.controlWidth = controlWidth
        self.minimumHeight = minimumHeight
        self.rowState = rowState
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
            }
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .frame(width: controlWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: controlWidth == nil ? .leading : .center)
    }

    private var backgroundFill: Color {
        switch rowState {
        case .selected:
            return SemanticTokens.Surface.captureChooserRowSelectedFill
        case .hovered:
            return SemanticTokens.Surface.captureChooserRowHoverFill
        case .idle:
            return SemanticTokens.Surface.captureChooserRowFill
        }
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
    var showChevron = false
    var showsRecent = false
    var isSelected = false

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

            HStack(alignment: .center, spacing: PrimitiveTokens.Space.xxs + 1) {
                if showsRecent {
                    Text("Recent")
                        .font(.system(size: PrimitiveTokens.FontSize.micro, weight: .medium))
                        .foregroundStyle(secondaryColor)
                        .padding(.horizontal, PrimitiveTokens.Space.xs - 1)
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
        guard let target else {
            return nil
        }

        switch style {
        case .accessory:
            guard let shortBranchLabel = target.shortBranchLabel,
                  shortBranchLabel.localizedCaseInsensitiveCompare(target.workspaceLabel) != .orderedSame else {
                return nil
            }

            return shortBranchLabel

        case .chooser:
            guard let chooserDetailLabel = target.chooserDetailLabel,
                  chooserDetailLabel.localizedCaseInsensitiveCompare(target.workspaceLabel) != .orderedSame else {
                return nil
            }

            return chooserDetailLabel
        }
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
