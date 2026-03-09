import XCTest
@testable import Prompt_Cue

final class CaptureEditorLayoutCalculatorTests: XCTestCase {
    func testCalculatorReturnsVisibleMetricsForMultilineContentBelowClamp() {
        let metrics = CaptureEditorLayoutCalculator.metrics(
            viewportWidth: 320,
            maxContentHeight: 176,
            minimumLineHeight: 22,
            scrollerReservationWidth: 16
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
            minimumLineHeight: 22,
            scrollerReservationWidth: 16
        ) { _ in
            260
        }

        XCTAssertEqual(metrics.contentHeight, 260, accuracy: 0.5)
        XCTAssertEqual(metrics.visibleHeight, 176, accuracy: 0.5)
        XCTAssertTrue(metrics.isScrollable)
        XCTAssertEqual(metrics.layoutWidth, 304, accuracy: 0.5)
    }

    func testCalculatorRemeasuresUsingReservedWidthOnceScrollingIsNeeded() {
        var measuredWidths: [CGFloat] = []

        let metrics = CaptureEditorLayoutCalculator.metrics(
            viewportWidth: 320,
            maxContentHeight: 100,
            minimumLineHeight: 22,
            scrollerReservationWidth: 16
        ) { width in
            measuredWidths.append(width)
            return width == 320 ? 140 : 180
        }

        XCTAssertEqual(measuredWidths.count, 2)
        XCTAssertEqual(measuredWidths[0], 320, accuracy: 0.5)
        XCTAssertEqual(measuredWidths[1], 304, accuracy: 0.5)
        XCTAssertEqual(metrics.contentHeight, 180, accuracy: 0.5)
        XCTAssertEqual(metrics.visibleHeight, 100, accuracy: 0.5)
        XCTAssertEqual(metrics.layoutWidth, 304, accuracy: 0.5)
        XCTAssertTrue(metrics.isScrollable)
    }

    func testCalculatorKeepsReservedWidthForLargePasteLikeLongContent() {
        var measuredWidths: [CGFloat] = []

        let metrics = CaptureEditorLayoutCalculator.metrics(
            viewportWidth: 320,
            maxContentHeight: 176,
            minimumLineHeight: 22,
            scrollerReservationWidth: 16
        ) { width in
            measuredWidths.append(width)
            return width == 320 ? 540 : 612
        }

        XCTAssertEqual(measuredWidths.count, 2)
        XCTAssertEqual(measuredWidths[0], 320, accuracy: 0.5)
        XCTAssertEqual(measuredWidths[1], 304, accuracy: 0.5)
        XCTAssertEqual(metrics.contentHeight, 612, accuracy: 0.5)
        XCTAssertEqual(metrics.visibleHeight, 176, accuracy: 0.5)
        XCTAssertTrue(metrics.isScrollable)
        XCTAssertEqual(metrics.layoutWidth, 304, accuracy: 0.5)
    }
}
