import PromptCueCore
import SwiftUI

struct CardStackView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppModel
    let onBackdropTap: () -> Void
    let onDismissAfterCopy: () -> Void
    let onEditCard: (CaptureCard) -> Void
    let onDeleteCard: (CaptureCard) -> Void
    private let ttlTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var stackFilter: StackRailFilter = .all
    @State private var isCopiedStackExpanded = ProcessInfo.processInfo.environment["PROMPTCUE_EXPAND_COPIED_STACK_ON_START"] == "1"
    @State private var expandedCardIDs = Set<CaptureCard.ID>()
    @State private var isCopiedStackHovered = false
    @State private var isConfirmingOffstageDelete = false
    @State private var classificationCache: [CaptureCard.ID: ContentClassification]
    @State private var cardSections: CardSections
    @State private var stagedCopiedCardIDSet: Set<CaptureCard.ID>
    @State private var isCmdPressed = false
    @State private var flagsMonitor: Any?
    @State private var ttlNow = Date()

    init(
        model: AppModel,
        onBackdropTap: @escaping () -> Void = {},
        onDismissAfterCopy: @escaping () -> Void = {},
        onEditCard: @escaping (CaptureCard) -> Void,
        onDeleteCard: @escaping (CaptureCard) -> Void
    ) {
        self.model = model
        self.onBackdropTap = onBackdropTap
        self.onDismissAfterCopy = onDismissAfterCopy
        self.onEditCard = onEditCard
        self.onDeleteCard = onDeleteCard
        let initialSections = Self.partitionedCards(from: model.cards)
        _cardSections = State(initialValue: initialSections)
        _classificationCache = State(
            initialValue: Self.buildClassificationCache(
                for: Self.classificationRelevantCards(
                    sections: initialSections,
                    filter: .all,
                    isCopiedStackExpanded: ProcessInfo.processInfo.environment["PROMPTCUE_EXPAND_COPIED_STACK_ON_START"] == "1"
                )
            )
        )
        _stagedCopiedCardIDSet = State(initialValue: Set(model.stagedCopiedCardIDs))
    }

    var body: some View {
        let allSections = cardSections
        let railState = StackRailState(
            activeCount: allSections.active.count,
            copiedCount: allSections.copied.count,
            stagedCount: model.stagedCopiedCount,
            filter: stackFilter
        )
        let visibleSections = filteredSections(from: allSections, state: railState)

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackdropTap)

            VStack(alignment: .trailing, spacing: PrimitiveTokens.Space.xs) {
                header(railState: railState)

                if visibleSections.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: PrimitiveTokens.Size.cardStackSpacing) {
                            if railState.filter == .offstage {
                                ForEach(visibleSections.copied) { card in
                                    cardRow(for: card)
                                }
                            } else {
                                if !visibleSections.active.isEmpty {
                                    ForEach(visibleSections.active) { card in
                                        cardRow(for: card)
                                    }
                                }

                                if !visibleSections.copied.isEmpty {
                                    copiedSection(
                                        copiedCards: visibleSections.copied,
                                        forceExpanded: railState.forcesExpandedCopiedSection
                                    )
                                        .padding(.top, PrimitiveTokens.Space.sm)
                                }
                            }
                        }
                        .padding(.vertical, PrimitiveTokens.Space.xxxs)
                        .frame(width: PanelMetrics.stackCardColumnWidth, alignment: .trailing)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, PanelMetrics.stackPanelHorizontalPadding)
            .padding(.top, PrimitiveTokens.Space.md)
            .padding(.bottom, PrimitiveTokens.Space.md)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onAppear {
            refreshDerivedState(
                cards: model.cards,
                filter: stackFilter,
                isCopiedStackExpanded: isCopiedStackExpanded
            )
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isCmdPressed = event.modifierFlags.contains(.command)
                return event
            }
        }
        .onDisappear {
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
        }
        .onChange(of: model.cards) { _, newCards in
            refreshDerivedState(
                cards: newCards,
                filter: stackFilter,
                isCopiedStackExpanded: isCopiedStackExpanded
            )
        }
        .onChange(of: model.stagedCopiedCardIDs) { _, newIDs in
            stagedCopiedCardIDSet = Set(newIDs)
        }
        .onChange(of: stackFilter) { _, newFilter in
            classificationCache = Self.buildClassificationCache(
                for: Self.classificationRelevantCards(
                    sections: cardSections,
                    filter: newFilter,
                    isCopiedStackExpanded: isCopiedStackExpanded
                )
            )
        }
        .onChange(of: isCopiedStackExpanded) { _, expanded in
            classificationCache = Self.buildClassificationCache(
                for: Self.classificationRelevantCards(
                    sections: cardSections,
                    filter: stackFilter,
                    isCopiedStackExpanded: expanded
                )
            )
        }
        .onReceive(ttlTicker) { now in
            ttlNow = now
        }
    }

    private func header(railState: StackRailState) -> some View {
        HStack(alignment: .center, spacing: PrimitiveTokens.Space.sm) {
            if selectionMode {
                Text("\(railState.stagedCount) Copied")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SemanticTokens.Text.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: PrimitiveTokens.Space.xs) {
                    Text(railState.headerTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SemanticTokens.Text.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !selectionMode {
                CmdIndicatorButton(isActive: isCmdPressed) {
                    isCmdPressed.toggle()
                }
            }
        }
        .padding(.leading, PrimitiveTokens.Space.xxxs)
        .padding(.trailing, PrimitiveTokens.Space.xs)
        .padding(.vertical, PrimitiveTokens.Space.xxxs)
        .frame(height: 32)
        .frame(width: PanelMetrics.stackCardColumnWidth, alignment: .leading)
    }

    private var emptyState: some View {
        CardSurface {
            Text("No cues yet")
                .font(PrimitiveTokens.Typography.body)
                .foregroundStyle(SemanticTokens.Text.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(maxWidth: .infinity)
                .frame(height: PrimitiveTokens.Size.thumbnailHeight)
                .accessibilityLabel("No cues yet")
        }
        .frame(width: PanelMetrics.stackCardColumnWidth, alignment: .trailing)
    }

    private var selectionMode: Bool {
        model.hasStagedCopiedCards
    }

    private func cardRow(for card: CaptureCard) -> some View {
        let isStagedCopied = stagedCopiedCardIDSet.contains(card.id)
        let ttlProgress = ttlProgressRemaining(for: card)

        return stackColumnContent {
            CaptureCardView(
                card: card,
                classification: resolveClassification(for: card),
                availableSuggestedTargets: model.availableSuggestedTargets,
                automaticSuggestedTarget: model.automaticSuggestedTarget,
                isSelected: isStagedCopied,
                isRecentlyCopied: isStagedCopied,
                selectionMode: selectionMode,
                ttlProgressRemaining: ttlProgress,
                isExpanded: expandedCardIDs.contains(card.id),
                onCopy: {
                    _ = model.copySingleCard(card)
                    onDismissAfterCopy()
                },
                onEdit: {
                    onEditCard(card)
                },
                onCopyRaw: {
                    _ = model.copyRaw(card: card)
                },
                onToggleSelection: {
                    _ = model.toggleMultiCopiedCard(card)
                },
                onCmdClick: {
                    _ = model.toggleMultiCopiedCard(card)
                },
                onToggleExpansion: {
                    toggleExpansion(for: card)
                },
                onDelete: {
                    onDeleteCard(card)
                },
                onRefreshSuggestedTargets: {
                    model.refreshAvailableSuggestedTargets()
                },
                onAssignSuggestedTarget: { target in
                    model.assignSuggestedTarget(target, to: card)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func copiedSection(copiedCards: [CaptureCard], forceExpanded: Bool) -> some View {
        if forceExpanded || isCopiedStackExpanded {
            LazyVStack(alignment: .leading, spacing: PrimitiveTokens.Size.cardStackSpacing) {
                copiedSectionHeader(copiedCards: copiedCards, isExpanded: true, isCollapsible: !forceExpanded)

                ForEach(copiedCards) { card in
                    cardRow(for: card)
                }
            }
            .id("copied-expanded")
        } else {
            LazyVStack(alignment: .leading, spacing: PrimitiveTokens.Space.xs) {
                copiedSectionHeader(copiedCards: copiedCards, isExpanded: false, isCollapsible: true)
                collapsedCopiedStack(copiedCards: copiedCards)
            }
                .id("copied-collapsed")
        }
    }

    private func copiedSectionHeader(copiedCards: [CaptureCard], isExpanded: Bool, isCollapsible: Bool) -> some View {
        HStack(spacing: PrimitiveTokens.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: PrimitiveTokens.Space.xxs) {
                Text("Copied")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SemanticTokens.Text.secondary)

                Text("\(copiedCards.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SemanticTokens.Text.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            offstageControlCluster(
                copiedCards: copiedCards,
                isExpanded: isExpanded,
                isCollapsible: isCollapsible
            )
        }
        .accessibilityLabel("Copied section, \(copiedCards.count) cues")
    }

    private func collapsedCopiedStack(copiedCards: [CaptureCard]) -> some View {
        ZStack(alignment: .topLeading) {
            StackNotificationCardSurface(isEmphasized: isCopiedStackHovered) {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                    if let card = copiedCards.first {
                        let classification = resolveClassification(for: card)
                        let visibleInlineText = card.visibleInlineText
                        InteractiveDetectedTextView(
                            text: visibleInlineText,
                            classification: classification,
                            baseColor: copiedPreviewTextColor,
                            highlightedRanges: card.visibleInlineTagRanges,
                            multilineLineLimit: StackCardOverflowPolicy.collapsedCopiedLineLimit
                        )
                    }

                    if let footer = collapsedCopiedFooterText(copiedCards: copiedCards) {
                        Text(footer)
                            .font(PrimitiveTokens.Typography.meta)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: collapsedCopiedCardHeight)
            .zIndex(1)
        }
        .padding(.bottom, PrimitiveTokens.Space.sm)
        .opacity(isCopiedStackHovered ? 1 : PrimitiveTokens.Opacity.copiedCard)
        .animation(.easeOut(duration: PrimitiveTokens.Motion.hoverQuick), value: isCopiedStackHovered)
        .onHover { hovered in
            isCopiedStackHovered = hovered
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isCopiedStackExpanded = true
        }
        .accessibilityLabel("Copied prompts, \(copiedCards.count) items")
        .accessibilityHint("Tap to expand")
    }

    private func collapsedBackPlateIndices(for copiedCards: [CaptureCard]) -> [Int] {
        CopiedStackRecipe.collapsedBackPlateIndices(for: copiedCards.count)
    }

    private func stackedBackPlate(index: Int) -> some View {
        RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
            .fill(
                SemanticTokens.Surface.notificationStackPlateBase
                    .opacity(CopiedStackRecipe.backPlateFillOpacity(index: index, colorScheme: colorScheme))
            )
            .overlay {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                    .fill(CopiedStackRecipe.backPlateShade(index: index, colorScheme: colorScheme))
            }
            .overlay {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                    .stroke(
                        SemanticTokens.Border.notificationCard.opacity(
                            CopiedStackRecipe.backPlateBorderOpacity(index: index, colorScheme: colorScheme)
                        )
                    )
            }
            .frame(height: collapsedCopiedCardHeight)
            .padding(.horizontal, CGFloat(index) * PrimitiveTokens.Space.xs)
    }

    private func collapsedBackPlateBottomPadding(copiedCards: [CaptureCard]) -> CGFloat {
        CopiedStackRecipe.collapsedBottomPadding(for: collapsedBackPlateIndices(for: copiedCards))
    }

    private var collapsedCopiedCardHeight: CGFloat {
        PrimitiveTokens.Size.notificationStackPlateHeight
    }

    private var copiedPreviewTextColor: Color {
        CopiedStackRecipe.previewTextColor(colorScheme: colorScheme)
    }

    private var copiedHeaderTextColor: Color {
        CopiedStackRecipe.headerTextColor(colorScheme: colorScheme)
    }

    private func offstageControlCluster(
        copiedCards: [CaptureCard],
        isExpanded: Bool,
        isCollapsible: Bool
    ) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: PrimitiveTokens.Space.xs) {
                if isConfirmingOffstageDelete {
                    Button {
                        isConfirmingOffstageDelete = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .frame(height: 16)
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.deleteOffstageCards()
                        isConfirmingOffstageDelete = false
                    } label: {
                        Text("Delete all")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(nsColor: .systemRed))
                            .frame(height: 16)
                    }
                    .buttonStyle(.plain)
                } else if !copiedCards.isEmpty {
                    Button {
                        isConfirmingOffstageDelete = true
                    } label: {
                        Text("Delete all")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .frame(height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isCollapsible {
                StackRailControlButton(
                    systemName: "chevron.down",
                    accessibilityLabel: isExpanded ? "Collapse off stage cues" : "Expand off stage cues",
                    glyphSize: 12,
                    controlSize: 20,
                    isActive: isExpanded,
                    rotationDegrees: isExpanded ? 180 : 0
                ) {
                    isCopiedStackExpanded.toggle()
                    isConfirmingOffstageDelete = false
                }
                .frame(height: 16)
            }
        }
        .frame(height: 16, alignment: .center)
    }

    private func copiedSummaryMetrics(copiedCards: [CaptureCard]) -> StackCardOverflowPolicy.Metrics? {
        guard let firstCopiedCard = copiedCards.first else {
            return nil
        }

        let styledText = InteractiveDetectedTextView.styledText(
            text: firstCopiedCard.visibleInlineText,
            classification: resolveClassification(for: firstCopiedCard),
            baseColor: copiedPreviewTextColor,
            highlightedRanges: firstCopiedCard.visibleInlineTagRanges
        )

        return StackCardOverflowPolicy.metrics(
            for: styledText.measurementText,
            cacheIdentity: firstCopiedCard.id,
            layoutVariant: styledText.displayConfiguration.layoutVariant,
            styleSignature: styledText.cacheSignature,
            availableWidth: collapsedCopiedSummaryTextWidth
        )
    }

    private func collapsedCopiedFooterText(copiedCards: [CaptureCard]) -> String? {
        var segments: [String] = []

        if let copiedSummaryMetrics = copiedSummaryMetrics(copiedCards: copiedCards),
           copiedSummaryMetrics.hiddenCollapsedCopiedLineCount > 0 {
            segments.append(
                StackCardOverflowPolicy.overflowLabel(
                    hiddenLineCount: copiedSummaryMetrics.hiddenCollapsedCopiedLineCount
                )
            )
        }

        if copiedCards.count > 1 {
            segments.append("+\(copiedCards.count - 1) more")
        }

        guard !segments.isEmpty else {
            return nil
        }

        return segments.joined(separator: " · ")
    }

    private var collapsedCopiedSummaryTextWidth: CGFloat {
        StackCardOverflowPolicy.collapsedCopiedSummaryTextWidth
    }

    private func toggleExpansion(for card: CaptureCard) {
        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.standard)) {
            if expandedCardIDs.contains(card.id) {
                expandedCardIDs.remove(card.id)
            } else {
                expandedCardIDs.insert(card.id)
            }
        }
    }

    private func resolveClassification(for card: CaptureCard) -> ContentClassification {
        classificationCache[card.id] ?? ContentClassifier.classify(card.visibleInlineText)
    }

    private static func buildClassificationCache(for cards: [CaptureCard]) -> [CaptureCard.ID: ContentClassification] {
        var cache: [CaptureCard.ID: ContentClassification] = [:]
        cache.reserveCapacity(cards.count)
        for card in cards {
            cache[card.id] = ContentClassifier.classify(card.visibleInlineText)
        }
        return cache
    }

    private func stackColumnSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        StackNotificationCardSurface {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: PanelMetrics.stackCardColumnWidth, alignment: .trailing)
    }

    private func stackColumnContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: PanelMetrics.stackCardColumnWidth, alignment: .trailing)
    }

    private static func partitionedCards(from cards: [CaptureCard]) -> CardSections {
        var active: [CaptureCard] = []
        var copied: [CaptureCard] = []
        active.reserveCapacity(cards.count)
        copied.reserveCapacity(cards.count / 2)

        for card in cards {
            if card.isCopied {
                copied.append(card)
            } else {
                active.append(card)
            }
        }

        return CardSections(active: active, copied: copied)
    }

    private func filteredSections(from sections: CardSections, state: StackRailState) -> CardSections {
        CardSections(
            active: state.showsActiveCards ? sections.active : [],
            copied: state.showsCopiedCards ? sections.copied : []
        )
    }

    private func refreshDerivedState(
        cards: [CaptureCard],
        filter: StackRailFilter,
        isCopiedStackExpanded: Bool
    ) {
        let sections = Self.partitionedCards(from: cards)
        cardSections = sections
        classificationCache = Self.buildClassificationCache(
            for: Self.classificationRelevantCards(
                sections: sections,
                filter: filter,
                isCopiedStackExpanded: isCopiedStackExpanded
            )
        )
    }

    private static func classificationRelevantCards(
        sections: CardSections,
        filter: StackRailFilter,
        isCopiedStackExpanded: Bool
    ) -> [CaptureCard] {
        switch filter {
        case .all:
            if isCopiedStackExpanded {
                return sections.active + sections.copied
            }
            return sections.active + sections.copied.prefix(1)

        case .onStage:
            return sections.active

        case .offstage:
            return isCopiedStackExpanded ? sections.copied : Array(sections.copied.prefix(1))
        }
    }

    private func ttlProgressRemaining(for card: CaptureCard) -> Double? {
        guard card.isCopied == false,
              let ttl = CardRetentionPreferences.load().effectiveTTL
        else {
            return nil
        }

        return card.ttlProgressRemaining(relativeTo: ttlNow, ttl: ttl)
    }
}

private struct CardSections {
    let active: [CaptureCard]
    let copied: [CaptureCard]

    static let empty = CardSections(active: [], copied: [])

    var isEmpty: Bool {
        active.isEmpty && copied.isEmpty
    }
}
