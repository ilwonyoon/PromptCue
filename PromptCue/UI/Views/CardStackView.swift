import PromptCueCore
import SwiftUI

struct CardStackView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppModel
    let onDeleteCard: (CaptureCard) -> Void
    @State private var isCopiedStackExpanded = ProcessInfo.processInfo.environment["PROMPTCUE_EXPAND_COPIED_STACK_ON_START"] == "1"
    @State private var expandedCardIDs = Set<CaptureCard.ID>()
    @State private var isCopiedStackHovered = false
    @State private var classificationCache: [CaptureCard.ID: ContentClassification] = [:]

    var body: some View {
        let sections = partitionedCards(from: model.cards)

        ZStack {
            stackBackdrop

            VStack(alignment: .trailing, spacing: PrimitiveTokens.Size.panelSectionSpacing) {
                header

                if sections.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: PrimitiveTokens.Size.cardStackSpacing) {
                            if !sections.active.isEmpty {
                                ForEach(sections.active) { card in
                                    cardRow(for: card)
                                }
                            }

                            if !sections.copied.isEmpty {
                                copiedSection(copiedCards: sections.copied)
                                    .padding(.top, PrimitiveTokens.Space.sm)
                            }
                        }
                        .padding(.vertical, PrimitiveTokens.Space.xxxs)
                        .frame(width: PanelMetrics.stackCardColumnWidth, alignment: .trailing)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, PrimitiveTokens.Space.sm)
            .padding(.top, PrimitiveTokens.Space.sm)
            .padding(.bottom, PrimitiveTokens.Space.md)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onAppear {
            classificationCache = buildClassificationCache(for: model.cards)
        }
        .onChange(of: model.cards) { _, newCards in
            let currentIDs = Set(newCards.map(\.id))
            classificationCache = classificationCache.filter { currentIDs.contains($0.key) }
            for card in newCards where classificationCache[card.id] == nil {
                classificationCache[card.id] = ContentClassifier.classify(card.text)
            }
        }
    }

    private var header: some View {
        Group {
            if model.stagedCopiedCount > 0 {
                stagedCopyHeader
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var stagedCopyHeader: some View {
        stackColumnSurface {
            HStack(alignment: .center, spacing: PrimitiveTokens.Space.xs) {
                Text("\(model.stagedCopiedCount) staged")
                    .font(PrimitiveTokens.Typography.bodyStrong)
                    .foregroundStyle(SemanticTokens.Text.primary)

                Spacer(minLength: PrimitiveTokens.Space.xs)
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

    private var selectionMode: Bool {
        model.hasStagedCopiedCards
    }

    private func cardRow(for card: CaptureCard) -> some View {
        let isStagedCopied = model.stagedCopiedCardIDs.contains(card.id)

        return stackColumnContent {
            CaptureCardView(
                card: card,
                classification: resolveClassification(for: card),
                availableSuggestedTargets: model.availableSuggestedTargets,
                automaticSuggestedTarget: model.automaticSuggestedTarget,
                isSelected: isStagedCopied,
                isRecentlyCopied: isStagedCopied,
                selectionMode: selectionMode,
                isExpanded: expandedCardIDs.contains(card.id),
                onCopy: {
                    _ = model.toggleMultiCopiedCard(card)
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
    private func copiedSection(copiedCards: [CaptureCard]) -> some View {
        if isCopiedStackExpanded {
            LazyVStack(alignment: .leading, spacing: PrimitiveTokens.Size.cardStackSpacing) {
                copiedSectionHeader(copiedCards: copiedCards)

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

    private func copiedSectionHeader(copiedCards: [CaptureCard]) -> some View {
        HStack(spacing: PrimitiveTokens.Space.xs) {
            Text("Copied")
                .font(PrimitiveTokens.Typography.metaStrong)
                .foregroundStyle(SemanticTokens.Text.secondary)

            Spacer(minLength: PrimitiveTokens.Space.xs)

            Image(systemName: "chevron.down")
                .font(PrimitiveTokens.Typography.chipIcon)
                .foregroundStyle(SemanticTokens.Text.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Copied section, \(copiedCards.count) cues")
        .accessibilityHint("Tap to collapse")
        .onTapGesture {
            isCopiedStackExpanded = false
        }
    }

    private func collapsedCopiedStack(copiedCards: [CaptureCard]) -> some View {
        Button {
            isCopiedStackExpanded = true
        } label: {
            ZStack(alignment: .topLeading) {
                ForEach(collapsedBackPlateIndices(for: copiedCards), id: \.self) { index in
                    stackedBackPlate(index: index)
                        .offset(y: CGFloat(index) * PrimitiveTokens.Space.xs)
                        .zIndex(Double(-index))
                }

                StackNotificationCardSurface(isEmphasized: isCopiedStackHovered) {
                    VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                        HStack(alignment: .center, spacing: PrimitiveTokens.Space.xs) {
                            Text("Copied")
                                .font(PrimitiveTokens.Typography.metaStrong)
                                .foregroundStyle(copiedHeaderTextColor)

                            Spacer(minLength: PrimitiveTokens.Space.xs)

                            Text("\(copiedCards.count)")
                                .font(PrimitiveTokens.Typography.meta)
                                .foregroundStyle(SemanticTokens.Text.secondary)
                        }

                        if let card = copiedCards.first {
                            let classification = resolveClassification(for: card)
                            let displayConfiguration = ContentDisplayFormatter.configuration(
                                for: card.text,
                                classification: classification
                            )

                            Text(displayConfiguration.text)
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(copiedPreviewTextColor)
                                .lineLimit(
                                    displayConfiguration.prefersSingleLine
                                        ? 1
                                        : StackCardOverflowPolicy.collapsedCopiedLineLimit
                                )
                                .truncationMode(
                                    displayConfiguration.truncation == .head ? .head : .tail
                                )
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.bottom, collapsedBackPlateBottomPadding(copiedCards: copiedCards))
            .opacity(isCopiedStackHovered ? 1 : PrimitiveTokens.Opacity.copiedCard)
            .animation(.easeOut(duration: PrimitiveTokens.Motion.quick), value: isCopiedStackHovered)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isCopiedStackHovered = true
            case .ended:
                isCopiedStackHovered = false
            }
        }
        .accessibilityLabel("Copied cues, \(copiedCards.count) items")
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

    private var stackBackdrop: some View {
        StackPanelBackdrop()
    }

    private var copiedPreviewTextColor: Color {
        CopiedStackRecipe.previewTextColor(colorScheme: colorScheme)
    }

    private var copiedHeaderTextColor: Color {
        CopiedStackRecipe.headerTextColor(colorScheme: colorScheme)
    }

    private func copiedSummaryMetrics(copiedCards: [CaptureCard]) -> StackCardOverflowPolicy.Metrics? {
        guard let firstCopiedCard = copiedCards.first else {
            return nil
        }

        return StackCardOverflowPolicy.metrics(
            for: firstCopiedCard.text,
            cacheIdentity: firstCopiedCard.id,
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
        if let cachedClassification = classificationCache[card.id] {
            return cachedClassification
        }

        let classification = ContentClassifier.classify(card.text)
        DispatchQueue.main.async {
            classificationCache[card.id] = classification
        }
        return classification
    }

    private func buildClassificationCache(for cards: [CaptureCard]) -> [CaptureCard.ID: ContentClassification] {
        var cache: [CaptureCard.ID: ContentClassification] = [:]
        cache.reserveCapacity(cards.count)
        for card in cards {
            cache[card.id] = ContentClassifier.classify(card.text)
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

    private func partitionedCards(from cards: [CaptureCard]) -> CardSections {
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
}

private struct CardSections {
    let active: [CaptureCard]
    let copied: [CaptureCard]

    var isEmpty: Bool {
        active.isEmpty && copied.isEmpty
    }
}
