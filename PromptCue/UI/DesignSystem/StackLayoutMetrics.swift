import CoreGraphics

// Canonical horizontal layout ownership for the right-docked stack surface.
// Keep the trailing edge fixed and derive leading/layout math from that.
enum StackLayoutMetrics {
    static let panelHorizontalInset: CGFloat = PanelMetrics.stackPanelHorizontalPadding
    static let columnWidth: CGFloat = PanelMetrics.stackCardColumnWidth
    static let cardContentInset: CGFloat = PrimitiveTokens.Size.notificationCardPadding
    static let compactCardHorizontalInset: CGFloat = PrimitiveTokens.Size.compactCardPaddingHorizontal
    static let actionColumnWidth: CGFloat = PrimitiveTokens.Space.xl
    static let actionColumnGap: CGFloat = PrimitiveTokens.Space.sm
    static let actionColumnReservedWidth: CGFloat = actionColumnWidth + actionColumnGap
    static let activeCardBodyLeadingReserve: CGFloat = 0
    static let primaryTextLeadingInset: CGFloat = cardContentInset
    static let primaryTextTrailingInset: CGFloat = cardContentInset + actionColumnReservedWidth
    static let sectionLeadingInset: CGFloat = primaryTextLeadingInset
    static let sectionTrailingInset: CGFloat = cardContentInset
    static let cardTextWidth: CGFloat =
        columnWidth
        - primaryTextLeadingInset
        - primaryTextTrailingInset
    static let collapsedCopiedSummaryTextWidth: CGFloat =
        columnWidth
        - primaryTextLeadingInset
        - cardContentInset

    static func copiedBackPlateLeadingInset(for index: Int) -> CGFloat {
        switch index {
        case 1:
            return PrimitiveTokens.Space.sm
        case 2:
            return PrimitiveTokens.Space.xl
        default:
            return PrimitiveTokens.Space.xl + (CGFloat(index - 2) * PrimitiveTokens.Space.sm)
        }
    }

    static func cardColumnLeadingRatio(panelWidth: CGFloat = PanelMetrics.stackPanelWidth) -> Double {
        let cardLeadingEdge = panelWidth - panelHorizontalInset - columnWidth
        return min(0.4, max(0.1, Double(cardLeadingEdge / panelWidth)))
    }
}
