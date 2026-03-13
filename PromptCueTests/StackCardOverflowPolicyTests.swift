import CoreGraphics
import Foundation
import PromptCueCore
import XCTest
@testable import Prompt_Cue

final class StackCardOverflowPolicyTests: XCTestCase {
    private let stackCardTextWidth: CGFloat =
        PanelMetrics.stackCardColumnWidth
        - (PrimitiveTokens.Size.notificationCardPadding * 2)
        - (PrimitiveTokens.Space.xl + PrimitiveTokens.Space.sm)

    func testShortTextDoesNotOverflowAtRest() {
        let metrics = StackCardOverflowPolicy.metrics(for: "Short cue", availableWidth: stackCardTextWidth)

        XCTAssertFalse(metrics.overflowsAtRest)
        XCTAssertEqual(metrics.hiddenRestingLineCount, 0)
        XCTAssertEqual(metrics.hiddenCollapsedCopiedLineCount, 0)
    }

    func testLongTextComputesHiddenLinesForRestingAndExpandedStates() {
        let text = Array(repeating: "Backtick keeps Stack scannable while long cues remain readable on demand.", count: 20)
            .joined(separator: " ")

        let metrics = StackCardOverflowPolicy.metrics(for: text, availableWidth: stackCardTextWidth)

        XCTAssertTrue(metrics.overflowsAtRest)
        XCTAssertGreaterThan(metrics.hiddenRestingLineCount, 0)
        XCTAssertEqual(metrics.hiddenExpandedLineCount, 0)
        XCTAssertGreaterThan(metrics.expandedVisibleTextHeight, metrics.restingVisibleTextHeight)
    }

    func testCollapsedCopiedSummaryUsesTwoLineCap() {
        let text = Array(repeating: "This copied summary should remain visually stable even with very long content.", count: 14)
            .joined(separator: " ")

        let metrics = StackCardOverflowPolicy.metrics(
            for: text,
            availableWidth: PanelMetrics.stackCardColumnWidth - (PrimitiveTokens.Size.notificationCardPadding * 2)
        )

        XCTAssertGreaterThan(metrics.hiddenCollapsedCopiedLineCount, 0)
        XCTAssertEqual(
            StackCardOverflowPolicy.overflowLabel(hiddenLineCount: metrics.hiddenCollapsedCopiedLineCount),
            "+\(metrics.hiddenCollapsedCopiedLineCount) lines"
        )
    }

    func testAttributedMeasurementRespectsStyledFontChanges() {
        let text = "tag tag tag tag tag tag tag tag tag tag tag tag"
        let plainText = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.body),
            ]
        )
        let emphasizedText = NSMutableAttributedString(attributedString: plainText)
        emphasizedText.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.body + 2, weight: .medium),
            range: NSRange(location: 0, length: 11)
        )

        let plainMetrics = StackCardOverflowPolicy.metrics(
            for: plainText,
            cacheIdentity: UUID(),
            styleSignature: 1,
            availableWidth: 110
        )
        let emphasizedMetrics = StackCardOverflowPolicy.metrics(
            for: emphasizedText,
            cacheIdentity: UUID(),
            styleSignature: 2,
            availableWidth: 110
        )

        XCTAssertGreaterThanOrEqual(emphasizedMetrics.fullTextHeight, plainMetrics.fullTextHeight)
        XCTAssertGreaterThanOrEqual(emphasizedMetrics.totalLineCount, plainMetrics.totalLineCount)
    }

    func testTaggedInlineDisplayUsesStyledMeasurementForCopiedSummaryWidths() {
        let card = CaptureCard(
            text: "Ship the stack header rail",
            tags: [
                CaptureTag(rawValue: "stack")!,
                CaptureTag(rawValue: "launch")!,
            ],
            createdAt: Date(),
            screenshotPath: nil,
            lastCopiedAt: Date(),
            sortOrder: 10
        )

        let styledText = InteractiveDetectedTextView.styledText(
            text: card.visibleInlineText,
            classification: .plain,
            baseColor: .primary,
            highlightedRanges: card.visibleInlineTagRanges
        )
        let metrics = StackCardOverflowPolicy.metrics(
            for: styledText.measurementText,
            cacheIdentity: card.id,
            layoutVariant: styledText.displayConfiguration.layoutVariant,
            styleSignature: styledText.cacheSignature,
            availableWidth: PanelMetrics.stackCardColumnWidth - (PrimitiveTokens.Size.notificationCardPadding * 2)
        )

        XCTAssertEqual(styledText.displayConfiguration.text, "#stack #launch Ship the stack header rail")
        XCTAssertFalse(styledText.measurementText.string.isEmpty)
        XCTAssertGreaterThan(metrics.totalLineCount, 0)
    }
}
