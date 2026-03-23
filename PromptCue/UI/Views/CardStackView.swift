import PromptCueCore
import SwiftUI

struct CardStackView: View {
    @ObservedObject var model: AppModel
    let onBackdropTap: () -> Void
    let onDismissAfterCopy: () -> Void
    let onEditCard: (CaptureCard) -> Void
    let onDeleteCard: (CaptureCard) -> Void
    private let ttlTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var isCopiedStackExpanded = ProcessInfo.processInfo.environment["PROMPTCUE_EXPAND_COPIED_STACK_ON_START"] == "1"
    @State private var expandedCardIDs = Set<CaptureCard.ID>()
    @State private var isCopiedStackHovered = false
    @State private var isConfirmingCopiedDelete = false
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
            stagedCount: model.stagedCopiedCount
        )

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackdropTap)

            VStack(alignment: .trailing, spacing: 0) {
                if allSections.isEmpty {
                    header(railState: railState)
                    emptyState
                } else {
                    let pinnedCards = allSections.active.filter(\.isPinned)
                    let unpinnedCards = allSections.active.filter { !$0.isPinned }

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            header(railState: railState)

                            if !pinnedCards.isEmpty {
                                pinnedCarousel(cards: pinnedCards)
                                    .padding(.bottom, PrimitiveTokens.Size.cardStackSpacing)
                            }

                            if !unpinnedCards.isEmpty {
                                LazyVStack(spacing: PrimitiveTokens.Size.cardStackSpacing) {
                                    ForEach(unpinnedCards) { card in
                                        cardRow(for: card)
                                    }
                                }
                            }

                            if !allSections.copied.isEmpty {
                                copiedSectionHeader(
                                    copiedCards: allSections.copied,
                                    isExpanded: isCopiedStackExpanded,
                                    isCollapsible: true
                                )
                                .padding(.top, PrimitiveTokens.Space.md)

                                copiedSectionContent(
                                    copiedCards: allSections.copied,
                                    forceExpanded: false
                                )
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
                isCopiedStackExpanded: isCopiedStackExpanded
            )
        }
        .onChange(of: model.stagedCopiedCardIDs) { _, newIDs in
            stagedCopiedCardIDSet = Set(newIDs)
        }
        .onChange(of: isCopiedStackExpanded) { _, expanded in
            classificationCache = Self.buildClassificationCache(
                for: Self.classificationRelevantCards(
                    sections: cardSections,
                    isCopiedStackExpanded: expanded
                )
            )
        }
        .onReceive(ttlTicker) { now in
            ttlNow = now
        }
    }

    @ViewBuilder
    private func header(railState: StackRailState) -> some View {
        if selectionMode {
            StackSectionHeader(title: "\(railState.stagedCount) Copied")
        } else {
            StackSectionHeader(title: railState.headerTitle) {
                CmdIndicatorButton(isActive: isCmdPressed) {
                    isCmdPressed.toggle()
                }
            }
        }
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

    private func pinnedCarousel(cards: [CaptureCard]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PrimitiveTokens.Space.xs) {
                ForEach(cards) { card in
                    pinnedCardRow(for: card)
                }
            }
            .padding(.horizontal, PrimitiveTokens.Space.xxxs)
        }
        .contentMargins(0)
        .scrollContentBackground(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: PanelMetrics.stackCardColumnWidth, alignment: .leading)
    }

    private func pinnedCardRow(for card: CaptureCard) -> some View {
        CaptureCardView(
            card: card,
            classification: resolveClassification(for: card),
            isSelected: stagedCopiedCardIDSet.contains(card.id),
            isRecentlyCopied: false,
            selectionMode: selectionMode,
            isExpanded: false,
            onCopy: {
                _ = model.copySingleCard(card)
            },
            onEdit: {
                onEditCard(card)
            },
            onCopyRaw: {
                _ = model.copyRaw(card: card)
            },
            onMarkCopied: {
                model.markCardCopiedWithoutCopy(card)
            },
            onToggleSelection: {
                _ = model.toggleMultiCopiedCard(card)
            },
            onToggleExpansion: {},
            onDelete: {
                onDeleteCard(card)
            },
            onTogglePin: {
                model.togglePin(card: card)
            },
            compactMode: true
        )
        .frame(width: PrimitiveTokens.Size.pinnedCardWidth)
    }

    private var selectionMode: Bool {
        model.hasStagedCopiedCards
    }

    private func cardRow(for card: CaptureCard) -> some View {
        let isStagedCopied = stagedCopiedCardIDSet.contains(card.id)
        let ttlProgress = ttlProgressRemaining(for: card)
        let ttlMinutes = ttlRemainingMinutes(for: card)

        return stackColumnContent {
            CaptureCardView(
                card: card,
                classification: resolveClassification(for: card),
                isSelected: isStagedCopied,
                isRecentlyCopied: isStagedCopied,
                selectionMode: selectionMode,
                ttlProgressRemaining: ttlProgress,
                ttlRemainingMinutes: ttlMinutes,
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
                onMarkCopied: {
                    model.markCardCopiedWithoutCopy(card)
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
                onTogglePin: {
                    model.togglePin(card: card)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func copiedSectionContent(copiedCards: [CaptureCard], forceExpanded: Bool) -> some View {
        if forceExpanded || isCopiedStackExpanded {
            LazyVStack(spacing: PrimitiveTokens.Size.cardStackSpacing) {
                ForEach(copiedCards) { card in
                    cardRow(for: card)
                }
            }
            .id("copied-expanded")
        } else {
            collapsedCopiedStack(copiedCards: copiedCards)
                .id("copied-collapsed")
        }
    }

    private func copiedSectionHeader(copiedCards: [CaptureCard], isExpanded: Bool, isCollapsible: Bool) -> some View {
        StackSectionHeader(title: "Copied", count: copiedCards.count) {
            copiedControlCluster(
                copiedCards: copiedCards,
                isExpanded: isExpanded,
                isCollapsible: isCollapsible
            )
        }
        .accessibilityLabel("Copied section, \(copiedCards.count) prompts")
    }

    private func collapsedCopiedStack(copiedCards: [CaptureCard]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(collapsedBackPlateIndices(for: copiedCards), id: \.self) { index in
                stackedBackPlate(index: index)
                    .offset(y: CopiedStackRecipe.collapsedVerticalOffset(for: index))
                    .zIndex(Double(-index))
            }

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
            .shadow(
                color: isCopiedStackHovered ? .clear : CopiedStackRecipe.backPlateShadowColor(index: 1),
                radius: CopiedStackRecipe.backPlateShadowRadius(index: 1),
                x: PrimitiveTokens.Shadow.zeroX,
                y: CopiedStackRecipe.backPlateShadowYOffset(index: 1)
            )
            .zIndex(1)
        }
        .padding(.bottom, collapsedBackPlateBottomPadding(copiedCards: copiedCards))
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
        RoundedRectangle(cornerRadius: CopiedStackRecipe.backPlateCornerRadius(for: index), style: .continuous)
            .fill(CopiedStackRecipe.backPlateFill(index: index))
            .overlay {
                RoundedRectangle(cornerRadius: CopiedStackRecipe.backPlateCornerRadius(for: index), style: .continuous)
                    .fill(CopiedStackRecipe.backPlateShade(index: index))
            }
            .overlay {
                RoundedRectangle(cornerRadius: CopiedStackRecipe.backPlateCornerRadius(for: index), style: .continuous)
                    .stroke(CopiedStackRecipe.backPlateBorder(index: index))
            }
            .frame(height: collapsedCopiedCardHeight)
            .padding(.horizontal, CopiedStackRecipe.collapsedHorizontalInset(for: index))
            .shadow(
                color: CopiedStackRecipe.backPlateShadowColor(index: index),
                radius: CopiedStackRecipe.backPlateShadowRadius(index: index),
                x: PrimitiveTokens.Shadow.zeroX,
                y: CopiedStackRecipe.backPlateShadowYOffset(index: index)
            )
    }

    private func collapsedBackPlateBottomPadding(copiedCards: [CaptureCard]) -> CGFloat {
        CopiedStackRecipe.collapsedBottomPadding(for: collapsedBackPlateIndices(for: copiedCards))
    }

    private var collapsedCopiedCardHeight: CGFloat {
        PrimitiveTokens.Size.notificationStackPlateHeight
    }

    private var copiedPreviewTextColor: Color {
        CopiedStackRecipe.previewTextColor
    }

    private var copiedHeaderTextColor: Color {
        CopiedStackRecipe.headerTextColor
    }

    private func copiedControlCluster(
        copiedCards: [CaptureCard],
        isExpanded: Bool,
        isCollapsible: Bool
    ) -> some View {
        HStack(spacing: PrimitiveTokens.Size.copiedControlClusterSpacing) {
            HStack(spacing: PrimitiveTokens.Space.xs) {
                if isConfirmingCopiedDelete {
                    Button {
                        isConfirmingCopiedDelete = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .frame(height: 16)
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.deleteOffstageCards()
                        isConfirmingCopiedDelete = false
                    } label: {
                        Text("Delete all")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(nsColor: .systemRed))
                            .frame(height: 16)
                    }
                    .buttonStyle(.plain)
                } else if !copiedCards.isEmpty {
                    Button {
                        isConfirmingCopiedDelete = true
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
                    accessibilityLabel: isExpanded ? "Collapse copied prompts" : "Expand copied prompts",
                    glyphSize: 10,
                    controlSize: 16,
                    isActive: isExpanded,
                    rotationDegrees: isExpanded ? 180 : 0
                ) {
                    isCopiedStackExpanded.toggle()
                    isConfirmingCopiedDelete = false
                }
            }
        }
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
            if card.isPinned {
                active.append(card)
            } else if card.isCopied {
                copied.append(card)
            } else {
                active.append(card)
            }
        }

        return CardSections(active: active, copied: copied)
    }

    private func refreshDerivedState(
        cards: [CaptureCard],
        isCopiedStackExpanded: Bool
    ) {
        let sections = Self.partitionedCards(from: cards)
        cardSections = sections
        classificationCache = Self.buildClassificationCache(
            for: Self.classificationRelevantCards(
                sections: sections,
                isCopiedStackExpanded: isCopiedStackExpanded
            )
        )
    }

    private static func classificationRelevantCards(
        sections: CardSections,
        isCopiedStackExpanded: Bool
    ) -> [CaptureCard] {
        if isCopiedStackExpanded {
            return sections.active + sections.copied
        }
        return sections.active + sections.copied.prefix(1)
    }

    private func ttlProgressRemaining(for card: CaptureCard) -> Double? {
        guard !card.isPinned,
              card.isCopied == false,
              let ttl = CardRetentionPreferences.load().effectiveTTL
        else {
            return nil
        }

        return card.ttlProgressRemaining(relativeTo: ttlNow, ttl: ttl)
    }

    private func ttlRemainingMinutes(for card: CaptureCard) -> Int? {
        guard !card.isPinned,
              card.isCopied == false,
              let ttl = CardRetentionPreferences.load().effectiveTTL
        else {
            return nil
        }

        return card.ttlRemainingMinutes(relativeTo: ttlNow, ttl: ttl)
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
