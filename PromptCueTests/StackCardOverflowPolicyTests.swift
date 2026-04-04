import CoreGraphics
import XCTest
@testable import Prompt_Cue

final class StackCardOverflowPolicyTests: XCTestCase {
    private let stackCardTextWidth: CGFloat = StackLayoutMetrics.cardTextWidth

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

    func testRestingLongTextCollapseUsesStackSpecificScanBand() {
        let text = Array(
            repeating: "This fixture should cross the stack scan band so the active card collapses and shows a +N lines affordance.",
            count: 16
        )
        .joined(separator: " ")

        let metrics = StackCardOverflowPolicy.metrics(for: text, availableWidth: stackCardTextWidth)

        XCTAssertGreaterThan(
            metrics.totalLineCount,
            StackCardOverflowPolicy.restingVisibleLineLimit + StackCardOverflowPolicy.restingOverflowToleranceLines
        )
        XCTAssertTrue(metrics.overflowsAtRest)
        XCTAssertGreaterThan(metrics.hiddenRestingLineCount, 0)
    }

    func testCollapsedCopiedSummaryUsesTwoLineCap() {
        let text = Array(repeating: "This copied summary should remain visually stable even with very long content.", count: 14)
            .joined(separator: " ")

        let metrics = StackCardOverflowPolicy.metrics(
            for: text,
            availableWidth: StackLayoutMetrics.collapsedCopiedSummaryTextWidth
        )

        XCTAssertGreaterThan(metrics.hiddenCollapsedCopiedLineCount, 0)
        XCTAssertEqual(
            StackCardOverflowPolicy.overflowLabel(hiddenLineCount: metrics.hiddenCollapsedCopiedLineCount),
            "+\(metrics.hiddenCollapsedCopiedLineCount) lines"
        )
    }

    func testHighlightedLongTextDoesNotMeasureShorterThanPlainText() {
        let text = Array(
            repeating: "#memory_mcp Descender-heavy wrapping text keeps going so the stack card has to measure multiple lines with tags and vividness guidance.",
            count: 8
        )
        .joined(separator: " ")
        let displayText = InteractiveDetectedTextView.layoutText(text: text, classification: .plain)
        let nsDisplayText = displayText as NSString
        let firstTagRange = nsDisplayText.range(of: "#memory_mcp")
        XCTAssertNotEqual(firstTagRange.location, NSNotFound)
        let styledText = InteractiveDetectedTextView.styledText(
            text: text,
            classification: .plain,
            baseColor: .primary,
            highlightedRanges: [firstTagRange]
        )

        let plainMetrics = StackCardOverflowPolicy.metrics(
            for: displayText,
            availableWidth: stackCardTextWidth
        )
        let highlightedMetrics = StackCardOverflowPolicy.metrics(
            for: styledText.measurementText,
            cacheIdentity: UUID(),
            styleSignature: styledText.cacheSignature,
            availableWidth: stackCardTextWidth
        )

        XCTAssertGreaterThanOrEqual(
            highlightedMetrics.fullTextHeight,
            plainMetrics.fullTextHeight,
            "Highlight styling should not cause stack card measurement to shrink and clip the last line."
        )
        XCTAssertGreaterThan(
            highlightedMetrics.expandedVisibleTextHeight,
            highlightedMetrics.fullTextHeight,
            "Expanded stack cards should reserve explicit bottom breathing room so the final line does not clip."
        )
    }
}
