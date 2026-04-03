import AppKit
import PromptCueCore
import SwiftUI

struct CollapsedCopiedStackView: View {
    let copiedCards: [CaptureCard]
    let classificationCache: [CaptureCard.ID: ContentClassification]
    let inheritedAppearance: NSAppearance?
    @Binding var isHovered: Bool
    let onExpand: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(backPlateIndices, id: \.self) { index in
                stackedBackPlate(index: index)
                    .offset(y: CopiedStackRecipe.collapsedVerticalOffset(for: index))
                    .zIndex(Double(-index))
            }

            StackNotificationCardSurface(isEmphasized: isHovered) {
                VStack(alignment: .leading, spacing: PrimitiveTokens.Space.xxs) {
                    if let card = copiedCards.first {
                        let classification = resolveClassification(for: card)
                        let visibleInlineText = card.visibleInlineText
                        InteractiveDetectedTextView(
                            text: visibleInlineText,
                            classification: classification,
                            baseColor: frontTextColor,
                            highlightedRanges: card.visibleInlineTagRanges,
                            multilineLineLimit: StackCardOverflowPolicy.collapsedCopiedLineLimit
                        )
                    }

                    if let footer = collapsedFooterText {
                        Text(footer)
                            .font(PrimitiveTokens.Typography.meta)
                            .foregroundStyle(SemanticTokens.Text.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.leading, StackLayoutMetrics.activeCardBodyLeadingReserve)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: cardHeight)
            .zIndex(1)
        }
        .padding(.bottom, CopiedStackRecipe.collapsedBottomPadding(for: backPlateIndices))
        .animation(.easeOut(duration: PrimitiveTokens.Motion.hoverQuick), value: isHovered)
        .onHover { hovered in
            isHovered = hovered
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .accessibilityLabel("Copied prompts, \(copiedCards.count) items")
        .accessibilityHint("Tap to expand")
    }

    private var backPlateIndices: [Int] {
        CopiedStackRecipe.collapsedBackPlateIndices(for: copiedCards.count)
    }

    private var cardHeight: CGFloat {
        PrimitiveTokens.Size.notificationStackPlateHeight
    }

    private var frontTextColor: Color {
        SemanticTokens.resolvedAdaptiveColor(
            light: NSColor.labelColor.withAlphaComponent(0.74),
            dark: NSColor.secondaryLabelColor.withAlphaComponent(0.78),
            appearance: inheritedAppearance
        )
    }

    private var collapsedFooterText: String? {
        var segments: [String] = []

        if let metrics = copiedSummaryMetrics,
           metrics.hiddenCollapsedCopiedLineCount > 0 {
            segments.append(
                StackCardOverflowPolicy.overflowLabel(
                    hiddenLineCount: metrics.hiddenCollapsedCopiedLineCount
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

    private var copiedSummaryMetrics: StackCardOverflowPolicy.Metrics? {
        guard let firstCopiedCard = copiedCards.first else {
            return nil
        }

        let styledText = InteractiveDetectedTextView.styledText(
            text: firstCopiedCard.visibleInlineText,
            classification: resolveClassification(for: firstCopiedCard),
            baseColor: frontTextColor,
            highlightedRanges: firstCopiedCard.visibleInlineTagRanges
        )

        return StackCardOverflowPolicy.metrics(
            for: styledText.measurementText,
            cacheIdentity: firstCopiedCard.id,
            layoutVariant: styledText.displayConfiguration.layoutVariant,
            styleSignature: styledText.cacheSignature,
            availableWidth: StackCardOverflowPolicy.collapsedCopiedSummaryTextWidth
        )
    }

    private func resolveClassification(for card: CaptureCard) -> ContentClassification {
        classificationCache[card.id] ?? ContentClassifier.classify(card.visibleInlineText)
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
            .frame(height: cardHeight)
            .padding(.horizontal, CopiedStackRecipe.collapsedHorizontalInset(for: index) / 2)
            .frame(maxWidth: .infinity, alignment: .center)
            .promptCueDepthShadow(
                color: CopiedStackRecipe.backPlateShadowColor(index: index),
                radius: CopiedStackRecipe.backPlateShadowRadius(index: index),
                y: CopiedStackRecipe.backPlateShadowYOffset(index: index)
            )
    }
}
