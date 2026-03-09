import SwiftUI

struct CardStackView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppModel
    let onCopyCard: (CaptureCard) -> Void
    let onCopySelection: () -> Void
    let onDeleteCard: (CaptureCard) -> Void
    @State private var isCopiedStackExpanded = ProcessInfo.processInfo.environment["PROMPTCUE_EXPAND_COPIED_STACK_ON_START"] == "1"
    @State private var stackBackdropDensity = 4.0
    @State private var stackBackdropGrayscale = 2.0

    private let stackBackdropDebugEnabled = ProcessInfo.processInfo.environment["BACKTICK_STACK_BLUR_DEBUG"] == "1"

    var body: some View {
        ZStack {
            stackBackdrop

            VStack(alignment: .leading, spacing: PrimitiveTokens.Size.panelSectionSpacing) {
                header

                if model.cards.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: PrimitiveTokens.Size.cardStackSpacing) {
                            if stackBackdropDebugEnabled {
                                stackBackdropDebugCard
                            }

                            if !activeCards.isEmpty {
                                ForEach(activeCards) { card in
                                    cardRow(for: card)
                                }
                            }

                            if !copiedCards.isEmpty {
                                copiedSection
                            }
                        }
                        .padding(.vertical, PrimitiveTokens.Space.xxxs)
                        .frame(width: AppUIConstants.stackCardColumnWidth, alignment: .trailing)
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
    }

    private var header: some View {
        Group {
            if selectionMode {
                selectionHeader
            }
        }
    }

    private var selectionHeader: some View {
        HStack(alignment: .center, spacing: PrimitiveTokens.Space.xs) {
            Text("\(model.selectionCount) selected")
                .font(PrimitiveTokens.Typography.bodyStrong)
                .foregroundStyle(SemanticTokens.Text.primary)

            Spacer(minLength: PrimitiveTokens.Space.xs)

            Button(action: onCopySelection) {
                PromptCueChip(
                    fill: SemanticTokens.Surface.accentFill,
                    border: SemanticTokens.Border.emphasis
                ) {
                    Text("Copy Selected")
                        .font(PrimitiveTokens.Typography.chip)
                        .foregroundStyle(SemanticTokens.Text.selection)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(model.selectionCount) selected cues")

            Button(action: model.clearSelection) {
                PromptCueChip {
                    Text("Clear")
                        .font(PrimitiveTokens.Typography.chip)
                        .foregroundStyle(SemanticTokens.Text.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear selection")
        }
        .frame(width: AppUIConstants.stackCardColumnWidth, alignment: .trailing)
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
        .frame(width: AppUIConstants.stackCardColumnWidth, alignment: .trailing)
    }

    private var activeCards: [CaptureCard] {
        model.cards.filter { !$0.isCopied }
    }

    private var copiedCards: [CaptureCard] {
        model.cards.filter(\.isCopied)
    }

    private var selectionMode: Bool {
        model.selectionCount > 0
    }

    private func cardRow(for card: CaptureCard) -> some View {
        CaptureCardView(
            card: card,
            isSelected: model.selectedCardIDs.contains(card.id),
            selectionMode: selectionMode,
            onCopy: {
                onCopyCard(card)
            },
            onToggleSelection: {
                model.toggleSelection(for: card)
            },
            onDelete: {
                onDeleteCard(card)
            }
        )
    }

    @ViewBuilder
    private var copiedSection: some View {
        if isCopiedStackExpanded {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Size.cardStackSpacing) {
                copiedSectionHeader

                ForEach(copiedCards) { card in
                    cardRow(for: card)
                }
            }
            .id("copied-expanded")
        } else {
            collapsedCopiedStack
                .id("copied-collapsed")
        }
    }

    private var copiedSectionHeader: some View {
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

    private var collapsedCopiedStack: some View {
        Button {
            isCopiedStackExpanded = true
        } label: {
            ZStack(alignment: .topLeading) {
                ForEach(collapsedBackPlateIndices, id: \.self) { index in
                    stackedBackPlate(index: index)
                        .offset(y: CGFloat(index) * PrimitiveTokens.Space.xs)
                        .zIndex(Double(-index))
                }

                StackNotificationCardSurface {
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
                            Text(card.text)
                                .font(PrimitiveTokens.Typography.body)
                                .foregroundStyle(copiedPreviewTextColor)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if copiedCards.count > 1 {
                            Text("+\(copiedCards.count - 1) more")
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
            .padding(.bottom, collapsedBackPlateBottomPadding)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copied cues, \(copiedCards.count) items")
        .accessibilityHint("Tap to expand")
    }

    private var collapsedBackPlateIndices: [Int] {
        switch copiedCards.count {
        case ...1:
            return []
        case 2:
            return [1]
        default:
            return [2, 1]
        }
    }

    private func stackedBackPlate(index: Int) -> some View {
        RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
            .fill(
                SemanticTokens.Surface.notificationStackPlateBase
                    .opacity(stackedBackPlateOpacity(for: index))
            )
            .overlay {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                    .fill(stackedBackPlateShade(for: index))
            }
            .overlay {
                RoundedRectangle(cornerRadius: PrimitiveTokens.Radius.md, style: .continuous)
                    .stroke(SemanticTokens.Border.notificationCard.opacity(stackedBackPlateBorderOpacity(for: index)))
            }
            .frame(height: collapsedCopiedCardHeight)
            .padding(.horizontal, CGFloat(index) * PrimitiveTokens.Space.xs)
    }

    private var collapsedBackPlateBottomPadding: CGFloat {
        CGFloat(collapsedBackPlateIndices.max() ?? 0) * PrimitiveTokens.Space.xs + PrimitiveTokens.Space.sm
    }

    private var collapsedCopiedCardHeight: CGFloat {
        PrimitiveTokens.Size.notificationStackPlateHeight
    }

    private var stackBackdrop: some View {
        StackPanelBackdrop(
            densityScale: stackBackdropDensity,
            grayscaleBias: stackBackdropGrayscale
        )
    }

    private var stackBackdropDebugCard: some View {
        StackNotificationCardSurface {
            VStack(alignment: .leading, spacing: PrimitiveTokens.Space.sm) {
                HStack {
                    Text("Backdrop Blur Debug")
                        .font(PrimitiveTokens.Typography.metaStrong)
                        .foregroundStyle(SemanticTokens.Text.primary)

                    Spacer(minLength: PrimitiveTokens.Space.sm)

                    Text(String(format: "%.2fx", stackBackdropDensity))
                        .font(PrimitiveTokens.Typography.meta)
                        .foregroundStyle(SemanticTokens.Text.secondary)
                }

                Slider(value: $stackBackdropDensity, in: 0.1 ... 4.0, step: 0.05)

                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                    HStack {
                        Text("Gray")
                        Spacer(minLength: PrimitiveTokens.Space.sm)
                        Text("White")
                    }
                    .font(PrimitiveTokens.Typography.meta)
                    .foregroundStyle(SemanticTokens.Text.secondary)

                    Slider(value: $stackBackdropGrayscale, in: 0 ... 2, step: 0.02)
                }

                Text("Adjust density live without changing card styling.")
                    .font(PrimitiveTokens.Typography.meta)
                    .foregroundStyle(SemanticTokens.Text.secondary)
            }
        }
    }

    private var copiedPreviewTextColor: Color {
        if colorScheme == .light {
            return SemanticTokens.Text.primary.opacity(PrimitiveTokens.Opacity.strong)
        }

        return SemanticTokens.Text.secondary.opacity(PrimitiveTokens.Opacity.soft)
    }

    private var copiedHeaderTextColor: Color {
        if colorScheme == .light {
            return SemanticTokens.Text.primary.opacity(PrimitiveTokens.Opacity.strong)
        }

        return SemanticTokens.Text.secondary
    }

    private func stackedBackPlateBorderOpacity(for index: Int) -> Double {
        if colorScheme == .light {
            return 0.42
        }

        switch index {
        case 1:
            return 0.42
        case 2:
            return 0.32
        default:
            return 0.28
        }
    }

    private func stackedBackPlateOpacity(for index: Int) -> Double {
        if colorScheme == .light {
            return 0.36 - (Double(index - 1) * 0.08)
        }

        switch index {
        case 1:
            return 0.72
        case 2:
            return 0.60
        default:
            return 0.52
        }
    }

    private func stackedBackPlateShade(for index: Int) -> Color {
        if colorScheme == .light {
            switch index {
            case 1:
                return Color.black.opacity(0.02)
            case 2:
                return Color.black.opacity(0.04)
            default:
                return Color.black.opacity(0.05)
            }
        }

        switch index {
        case 1:
            return Color.black.opacity(0.14)
        case 2:
            return Color.black.opacity(0.22)
        default:
            return Color.black.opacity(0.26)
        }
    }
}
