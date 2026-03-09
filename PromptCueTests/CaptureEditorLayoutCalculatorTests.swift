import XCTest
@testable import Prompt_Cue

final class CaptureEditorLayoutCalculatorTests: XCTestCase {
    func testCalculatorReturnsVisibleMetricsForMultilineContentBelowClamp() {
        let metrics = CaptureEditorLayoutCalculator.metrics(
            viewportWidth: 320,
            maxContentHeight: 176,
            minimumLineHeight: 22
        ) { _ in
            66
        }

        XCTAssertEqual(metrics.contentHeight, 66, accuracy: 0.5)
        XCTAssertEqual(metrics.visibleHeight, 66, accuracy: 0.5)
        XCTAssertFalse(metrics.isScrollable)
        XCTAssertEqual(metrics.layoutWidth, 320, accuracy: 0.5)
    }

    func testCalculatorClampsVisibleHeightAtMax() {
        let metrics = CaptureEditorLayoutCalculator.metrics(
            viewportWidth: 320,
            maxContentHeight: 176,
            minimumLineHeight: 22
        ) { _ in
            260
        }

        XCTAssertEqual(metrics.contentHeight, 260, accuracy: 0.5)
        XCTAssertEqual(metrics.visibleHeight, 176, accuracy: 0.5)
        XCTAssertTrue(metrics.isScrollable)
        XCTAssertEqual(metrics.layoutWidth, 320, accuracy: 0.5)
    }

    func testCalculatorDoesNotRemeasureUsingReservedWidthOnceScrollingIsNeeded() {
        var measuredWidths: [CGFloat] = []

        let metrics = CaptureEditorLayoutCalculator.metrics(
            viewportWidth: 320,
            maxContentHeight: 100,
            minimumLineHeight: 22
        ) { width in
            measuredWidths.append(width)
            return 140
        }

        XCTAssertEqual(measuredWidths.count, 1)
        XCTAssertEqual(measuredWidths[0], 320, accuracy: 0.5)
        XCTAssertEqual(metrics.contentHeight, 140, accuracy: 0.5)
        XCTAssertEqual(metrics.visibleHeight, 100, accuracy: 0.5)
        XCTAssertEqual(metrics.layoutWidth, 320, accuracy: 0.5)
        XCTAssertTrue(metrics.isScrollable)
    }

    func testCalculatorKeepsViewportWidthForLargePasteLikeLongContent() {
        var measuredWidths: [CGFloat] = []

        let metrics = CaptureEditorLayoutCalculator.metrics(
            viewportWidth: 320,
            maxContentHeight: 176,
            minimumLineHeight: 22
        ) { width in
            measuredWidths.append(width)
            return 540
        }

        XCTAssertEqual(measuredWidths.count, 1)
        XCTAssertEqual(measuredWidths[0], 320, accuracy: 0.5)
        XCTAssertEqual(metrics.contentHeight, 540, accuracy: 0.5)
        XCTAssertEqual(metrics.visibleHeight, 176, accuracy: 0.5)
        XCTAssertTrue(metrics.isScrollable)
        XCTAssertEqual(metrics.layoutWidth, 320, accuracy: 0.5)
    }
}
