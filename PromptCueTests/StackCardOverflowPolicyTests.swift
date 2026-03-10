import CoreGraphics
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
}
