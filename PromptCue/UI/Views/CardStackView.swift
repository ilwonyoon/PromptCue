import AppKit
import PromptCueCore
import SwiftUI

@MainActor
final class CardStackViewState: ObservableObject {
    @Published var isCopiedStackExpanded =
        ProcessInfo.processInfo.environment["PROMPTCUE_EXPAND_COPIED_STACK_ON_START"] == "1"
    @Published private(set) var expandedCardIDs = Set<CaptureCard.ID>()
    @Published var isCopiedStackHovered = false
    @Published var isConfirmingCopiedDelete = false
    @Published var isCmdPressed = false
    @Published private(set) var inheritedAppearance: NSAppearance? = NSApp.effectiveAppearance
    @Published private(set) var appearanceEpoch: UInt64 = 0

    func toggleExpansion(for cardID: CaptureCard.ID) {
        var nextExpandedIDs = expandedCardIDs
        if nextExpandedIDs.contains(cardID) {
            nextExpandedIDs.remove(cardID)
        } else {
            nextExpandedIDs.insert(cardID)
        }
        expandedCardIDs = nextExpandedIDs
    }

    func applyInheritedAppearance(_ appearance: NSAppearance?) {
        inheritedAppearance = appearance
        appearanceEpoch &+= 1
    }
}

struct CardStackView: View {
    private enum CardRowNamespace: String {
        case active
        case copied
        case pinned
    }

    @ObservedObject var model: AppModel
    @ObservedObject var viewState: CardStackViewState
    let onBackdropTap: () -> Void
    let onDismissAfterCopy: (@escaping () -> Void) -> Void
    let onEditCard: (CaptureCard) -> Void
    let onDeleteCard: (CaptureCard) -> Void
    private let ttlTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var flagsMonitor: Any?
    @State private var ttlNow = Date()

    init(
        model: AppModel,
        viewState: CardStackViewState,
        onBackdropTap: @escaping () -> Void = {},
        onDismissAfterCopy: @escaping (@escaping () -> Void) -> Void = { action in action() },
        onEditCard: @escaping (CaptureCard) -> Void,
        onDeleteCard: @escaping (CaptureCard) -> Void
    ) {
        self.model = model
        self.viewState = viewState
        self.onBackdropTap = onBackdropTap
        self.onDismissAfterCopy = onDismissAfterCopy
        self.onEditCard = onEditCard
        self.onDeleteCard = onDeleteCard
    }

    var body: some View {
        let allSections = Self.partitionedCards(from: model.cards)
        let stagedCopiedCardIDSet = Set(model.stagedCopiedCardIDs)
        let classificationCache = Self.buildClassificationCache(
            for: Self.classificationRelevantCards(
                sections: allSections,
                isCopiedStackExpanded: viewState.isCopiedStackExpanded
            )
        )
        let railState = StackRailState(
            activeCount: allSections.active.count,
            copiedCount: allSections.copied.count,
            stagedCount: model.stagedCopiedCount
        )

        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackdropTap)

            VStack(spacing: 0) {
                if allSections.isEmpty {
                    stackColumnContent {
                        header(railState: railState)
                    }
                    emptyState
                } else {
                    let pinnedCards = allSections.active.filter(\.isPinned)
                    let unpinnedCards = allSections.active.filter { !$0.isPinned }

                    StackOwnedScrollView {
                        VStack(spacing: 0) {
                            stackColumnContent {
                                header(railState: railState)
                            }

                            if !pinnedCards.isEmpty {
                                stackColumnContent {
                                    pinnedCarousel(
                                        cards: pinnedCards,
                                        classificationCache: classificationCache,
                                        stagedCopiedCardIDSet: stagedCopiedCardIDSet
                                    )
                                }
                                    .padding(.bottom, PrimitiveTokens.Size.cardStackSpacing)
                            }

                            if !unpinnedCards.isEmpty {
                                VStack(spacing: PrimitiveTokens.Size.cardStackSpacing) {
                                    ForEach(unpinnedCards) { card in
                                        cardRow(
                                            for: card,
                                            namespace: .active,
                                            classificationCache: classificationCache,
                                            stagedCopiedCardIDSet: stagedCopiedCardIDSet
                                        )
                                    }
                                }
                            }

                            if !allSections.copied.isEmpty {
                                stackColumnContent {
                                    copiedSectionHeader(
                                        copiedCards: allSections.copied,
                                        isExpanded: viewState.isCopiedStackExpanded,
                                        isCollapsible: true
                                    )
                                }
                                .padding(.top, PrimitiveTokens.Space.md)

                                copiedSectionContent(
                                    copiedCards: allSections.copied,
                                    forceExpanded: false,
                                    classificationCache: classificationCache,
                                    stagedCopiedCardIDSet: stagedCopiedCardIDSet
                                )
                            }
                        }
                        .padding(.vertical, PrimitiveTokens.Space.xxxs)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.top, PrimitiveTokens.Space.md)
            .padding(.bottom, PrimitiveTokens.Space.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                viewState.isCmdPressed = event.modifierFlags.contains(.command)
                return event
            }
        }
        .onDisappear {
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
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
                CmdIndicatorButton(isActive: viewState.isCmdPressed) {
                    viewState.isCmdPressed.toggle()
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
        .frame(width: StackLayoutMetrics.columnWidth, alignment: .trailing)
    }

    private func pinnedCarousel(
        cards: [CaptureCard],
        classificationCache: [CaptureCard.ID: ContentClassification],
        stagedCopiedCardIDSet: Set<CaptureCard.ID>
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PrimitiveTokens.Space.xs) {
                ForEach(cards) { card in
                    pinnedCardRow(
                        for: card,
                        namespace: .pinned,
                        classificationCache: classificationCache,
                        stagedCopiedCardIDSet: stagedCopiedCardIDSet
                    )
                }
            }
            .padding(.horizontal, PrimitiveTokens.Space.xxxs)
        }
        .contentMargins(0)
        .scrollContentBackground(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: StackLayoutMetrics.columnWidth, alignment: .leading)
    }

    private func pinnedCardRow(
        for card: CaptureCard,
        namespace: CardRowNamespace,
        classificationCache: [CaptureCard.ID: ContentClassification],
        stagedCopiedCardIDSet: Set<CaptureCard.ID>
    ) -> some View {
        CaptureCardView(
            card: card,
            classification: resolveClassification(for: card, classificationCache: classificationCache),
            isSelected: stagedCopiedCardIDSet.contains(card.id),
            isRecentlyCopied: false,
            selectionMode: selectionMode,
            isExpanded: false,
            inheritedAppearance: viewState.inheritedAppearance,
            onCopy: {
                onDismissAfterCopy {
                    _ = model.copySingleCard(card)
                }
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
        .id(rowIdentity(for: card, namespace: namespace))
    }

    private var selectionMode: Bool {
        model.hasStagedCopiedCards
    }

    private func cardRow(
        for card: CaptureCard,
        namespace: CardRowNamespace,
        classificationCache: [CaptureCard.ID: ContentClassification],
        stagedCopiedCardIDSet: Set<CaptureCard.ID>
    ) -> some View {
        let isStagedCopied = stagedCopiedCardIDSet.contains(card.id)
        let ttlProgress = ttlProgressRemaining(for: card)
        let ttlMinutes = ttlRemainingMinutes(for: card)

        return stackColumnContent {
            CaptureCardView(
                card: card,
                classification: resolveClassification(for: card, classificationCache: classificationCache),
                isSelected: isStagedCopied,
                isRecentlyCopied: isStagedCopied,
                selectionMode: selectionMode,
                ttlProgressRemaining: ttlProgress,
                ttlRemainingMinutes: ttlMinutes,
                isExpanded: viewState.expandedCardIDs.contains(card.id),
                inheritedAppearance: viewState.inheritedAppearance,
                onCopy: {
                    onDismissAfterCopy {
                        _ = model.copySingleCard(card)
                    }
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
            .id(rowIdentity(for: card, namespace: namespace))
    }

    @ViewBuilder
    private func copiedSectionContent(
        copiedCards: [CaptureCard],
        forceExpanded: Bool,
        classificationCache: [CaptureCard.ID: ContentClassification],
        stagedCopiedCardIDSet: Set<CaptureCard.ID>
    ) -> some View {
        if forceExpanded || viewState.isCopiedStackExpanded {
            stackColumnContent {
                VStack(spacing: PrimitiveTokens.Size.cardStackSpacing) {
                    ForEach(copiedCards) { card in
                        cardRow(
                            for: card,
                            namespace: .copied,
                            classificationCache: classificationCache,
                            stagedCopiedCardIDSet: stagedCopiedCardIDSet
                        )
                    }
                }
            }
            .id("copied-expanded-\(viewState.appearanceEpoch)")
        } else {
            stackColumnContent {
                CollapsedCopiedStackView(
                    copiedCards: copiedCards,
                    classificationCache: classificationCache,
                    inheritedAppearance: viewState.inheritedAppearance,
                    isHovered: $viewState.isCopiedStackHovered
                ) {
                    viewState.isCopiedStackExpanded = true
                }
            }
                .padding(.top, CopiedStackRecipe.collapsedTopShadowCompensation)
                .id("copied-collapsed-\(viewState.appearanceEpoch)")
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

    private func copiedControlCluster(
        copiedCards: [CaptureCard],
        isExpanded: Bool,
        isCollapsible: Bool
    ) -> some View {
        HStack(spacing: PrimitiveTokens.Size.copiedControlClusterSpacing) {
            HStack(spacing: PrimitiveTokens.Space.xs) {
                if viewState.isConfirmingCopiedDelete {
                    Button {
                        viewState.isConfirmingCopiedDelete = false
                    } label: {
                        Text("Cancel")
                            .font(PrimitiveTokens.Typography.metaMedium)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .frame(height: PrimitiveTokens.Size.compactTrailingControlHeight)
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.deleteOffstageCards()
                        viewState.isConfirmingCopiedDelete = false
                    } label: {
                        Text("Delete all")
                            .font(PrimitiveTokens.Typography.metaMedium)
                            .foregroundStyle(SemanticTokens.Accent.destructive)
                            .frame(height: PrimitiveTokens.Size.compactTrailingControlHeight)
                    }
                    .buttonStyle(.plain)
                } else if !copiedCards.isEmpty {
                    Button {
                        viewState.isConfirmingCopiedDelete = true
                    } label: {
                        Text("Delete all")
                            .font(PrimitiveTokens.Typography.metaMedium)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                            .frame(height: PrimitiveTokens.Size.compactTrailingControlHeight)
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
                    viewState.isCopiedStackExpanded.toggle()
                    viewState.isConfirmingCopiedDelete = false
                }
            }
        }
        .frame(minHeight: PrimitiveTokens.Size.sectionHeaderTrailingHeight)
    }

    private func toggleExpansion(for card: CaptureCard) {
        withAnimation(.easeOut(duration: PrimitiveTokens.Motion.standard)) {
            viewState.toggleExpansion(for: card.id)
        }
    }

    private func resolveClassification(
        for card: CaptureCard,
        classificationCache: [CaptureCard.ID: ContentClassification]
    ) -> ContentClassification {
        classificationCache[card.id] ?? ContentClassifier.classify(card.visibleInlineText)
    }

    private func rowIdentity(for card: CaptureCard, namespace: CardRowNamespace) -> String {
        "\(namespace.rawValue)-\(card.id.uuidString)-\(viewState.appearanceEpoch)"
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
        .frame(width: StackLayoutMetrics.columnWidth, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func stackColumnContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: StackLayoutMetrics.columnWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .center)
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

private struct StackOwnedScrollView<Content: View>: NSViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> StackOwnedNSScrollView {
        let scrollView = StackOwnedNSScrollView()
        scrollView.update(rootView: AnyView(content))
        return scrollView
    }

    func updateNSView(_ nsView: StackOwnedNSScrollView, context: Context) {
        nsView.update(rootView: AnyView(content))
    }
}

private final class StackOwnedNSScrollView: NSScrollView {
    private let documentContainer = StackScrollDocumentView()
    private let hostingView = StackContentHostingView(rootView: AnyView(EmptyView()))

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = false
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        automaticallyAdjustsContentInsets = false
        verticalScroller = nil
        horizontalScroller = nil
        contentInsets = NSEdgeInsetsZero
        contentView.drawsBackground = false
        contentView.automaticallyAdjustsContentInsets = false

        documentContainer.wantsLayer = true
        documentContainer.layer?.backgroundColor = NSColor.clear.cgColor

        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        documentContainer.addSubview(hostingView)
        documentView = documentContainer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layoutDocumentView()
    }

    override func tile() {
        super.tile()
        configureScrollers()
    }

    func update(rootView: AnyView) {
        hostingView.rootView = AnyView(rootView.ignoresSafeArea(.container, edges: .top))
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        configureScrollers()
        layoutDocumentView()
    }

    private func configureScrollers() {
        hasVerticalScroller = false
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScroller = nil
        horizontalScroller = nil
    }

    private func layoutDocumentView() {
        let targetWidth = contentView.bounds.width
        guard targetWidth > 0 else {
            return
        }

        hostingView.setFrameSize(NSSize(width: targetWidth, height: 1))
        hostingView.layoutSubtreeIfNeeded()

        let contentHeight = hostingView.fittingSize.height
        let containerHeight = max(contentHeight, contentView.bounds.height)
        documentContainer.frame = NSRect(x: 0, y: 0, width: targetWidth, height: containerHeight)
        hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: contentHeight)
    }
}

private final class StackScrollDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private final class StackContentHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsetsZero
    }

    override var safeAreaRect: NSRect {
        bounds
    }
}
