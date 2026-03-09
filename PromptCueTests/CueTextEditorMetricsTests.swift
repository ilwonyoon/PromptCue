import AppKit
import XCTest
@testable import Prompt_Cue

@MainActor
final class CueTextEditorMetricsTests: XCTestCase {
    private var container: CueEditorContainerView!
    private var reportedMetrics: [CaptureEditorMetrics] = []

    override func setUpWithError() throws {
        try super.setUpWithError()

        container = CueEditorContainerView()
        container.maxMeasuredHeight = AppUIConstants.captureEditorMaxHeight
        container.onMetricsChange = { [weak self] metrics in
            self?.reportedMetrics.append(metrics)
        }
        applyProductionTypingStyle(to: container.textView)

        layoutEditor(width: AppUIConstants.captureEditorViewportWidth)
    }

    override func tearDownWithError() throws {
        container = nil
        reportedMetrics = []
        try super.tearDownWithError()
    }

    func testEmptyEditorReportsSingleLineMinimumMetrics() {
        setText("")

        XCTAssertEqual(lastReportedMetrics.contentHeight, AppUIConstants.captureEditorMinimumVisibleHeight, accuracy: 0.5)
        XCTAssertEqual(lastReportedMetrics.visibleHeight, AppUIConstants.captureEditorMinimumVisibleHeight, accuracy: 0.5)
        XCTAssertFalse(lastReportedMetrics.isScrollable)
        XCTAssertFalse(container.scrollView.hasVerticalScroller)
    }

    func testWrapToTwoLinesUsesR7BVisibleHeightContract() {
        let metrics = estimatedMetrics(
            for: "Prompt Cue wraps short capture notes cleanly."
        )

        XCTAssertEqual(metrics.contentHeight, expectedVisibleHeight(forLineCount: 2), accuracy: 0.5)
        XCTAssertEqual(metrics.visibleHeight, expectedVisibleHeight(forLineCount: 2), accuracy: 0.5)
        XCTAssertFalse(metrics.isScrollable)
        XCTAssertEqual(metrics.layoutWidth, AppUIConstants.captureEditorViewportWidth, accuracy: 0.5)
    }

    func testBottomBreathingRoomPersistsAcrossSingleAndTwoLineMetrics() {
        let singleLineMetrics = estimatedMetrics(for: "Quick cue.")
        let twoLineMetrics = estimatedMetrics(
            for: "Prompt Cue wraps short capture notes cleanly."
        )

        XCTAssertEqual(singleLineMetrics.visibleHeight, expectedVisibleHeight(forLineCount: 1), accuracy: 0.5)
        XCTAssertEqual(twoLineMetrics.visibleHeight, expectedVisibleHeight(forLineCount: 2), accuracy: 0.5)
        XCTAssertEqual(
            twoLineMetrics.visibleHeight - singleLineMetrics.visibleHeight,
            PrimitiveTokens.LineHeight.capture,
            accuracy: 0.5
        )
    }

    func testPastePayloadGrowsToCapBeforeScrollerTurnsOn() {
        layoutEditor(width: AppUIConstants.captureEditorViewportWidth)

        setText(multilinePaste(lineCount: 6), forceScrollToSelection: true)

        XCTAssertEqual(lastReportedMetrics.visibleHeight, expectedVisibleHeight(forLineCount: 6), accuracy: 1)
        XCTAssertFalse(lastReportedMetrics.isScrollable)
        XCTAssertFalse(container.scrollView.hasVerticalScroller)

        setText(multilinePaste(lineCount: 7), forceScrollToSelection: true)

        XCTAssertEqual(lastReportedMetrics.visibleHeight, AppUIConstants.captureEditorMaxHeight, accuracy: 1)
        XCTAssertTrue(lastReportedMetrics.isScrollable)
        XCTAssertTrue(container.scrollView.hasVerticalScroller)
        XCTAssertGreaterThan(lastReportedMetrics.contentHeight, AppUIConstants.captureEditorMaxHeight)
        XCTAssertGreaterThan(container.textView.frame.height, lastReportedMetrics.visibleHeight)
    }

    func testLargePasteUsesReservedScrollerWidthAfterCrossingCap() {
        layoutEditor(width: AppUIConstants.captureEditorViewportWidth)
        setText(multilinePaste(lineCount: 12), forceScrollToSelection: true)

        let viewportWidth = container.scrollView.contentSize.width
        let expectedReservedWidth = max(
            NSScroller.scrollerWidth(for: .regular, scrollerStyle: container.scrollView.scrollerStyle),
            PrimitiveTokens.Space.md
        )

        XCTAssertTrue(lastReportedMetrics.isScrollable)
        XCTAssertEqual(lastReportedMetrics.visibleHeight, AppUIConstants.captureEditorMaxHeight, accuracy: 1)
        XCTAssertGreaterThan(lastReportedMetrics.contentHeight, lastReportedMetrics.visibleHeight)
        XCTAssertEqual(lastReportedMetrics.layoutWidth, viewportWidth - expectedReservedWidth, accuracy: 1)
    }

    func testNarrowerWidthIncreasesMeasuredVisibleHeightForSameContent() {
        let text = "This contract should fail if a future rewrite stops measuring wrapped text against the available width."

        layoutEditor(width: 360)
        setText(text)
        let wideMetrics = lastReportedMetrics

        layoutEditor(width: 220)
        setText(text)
        let narrowMetrics = lastReportedMetrics

        XCTAssertGreaterThan(narrowMetrics.visibleHeight, wideMetrics.visibleHeight)
    }

    private func estimatedMetrics(for text: String) -> CaptureEditorMetrics {
        CaptureEditorLayoutCalculator.estimatedMetrics(
            text: text,
            viewportWidth: AppUIConstants.captureEditorViewportWidth,
            maxContentHeight: AppUIConstants.captureEditorMaxHeight,
            minimumLineHeight: PrimitiveTokens.LineHeight.capture,
            scrollerReservationWidth: max(
                NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay),
                PrimitiveTokens.Space.md
            ),
            font: NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.capture),
            lineHeight: PrimitiveTokens.LineHeight.capture
        )
    }

    private func expectedVisibleHeight(forLineCount lineCount: Int) -> CGFloat {
        (CGFloat(lineCount) * PrimitiveTokens.LineHeight.capture)
            + (AppUIConstants.captureEditorVerticalInset * 2)
            + AppUIConstants.captureEditorBottomBreathingRoom
    }

    private func multilinePaste(lineCount: Int) -> String {
        (1...lineCount)
            .map { "Paste line \($0) for Prompt Cue capture QA." }
            .joined(separator: "\n")
    }

    private var lastReportedMetrics: CaptureEditorMetrics {
        reportedMetrics.last ?? .empty
    }

    private func layoutEditor(width: CGFloat) {
        container.frame = NSRect(x: 0, y: 0, width: width, height: 320)
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        container.updateMeasuredMetrics(forceMeasure: true)
        drainMainQueue()
    }

    private func setText(_ text: String, forceScrollToSelection: Bool = false) {
        container.textView.string = text
        container.textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        applyProductionTypingStyle(to: container.textView)
        container.updateMeasuredMetrics(forceScrollToSelection: forceScrollToSelection, forceMeasure: true)
        drainMainQueue()
    }

    private func applyProductionTypingStyle(to textView: WrappingCueTextView) {
        let font = NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.capture)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = PrimitiveTokens.LineHeight.capture
        paragraphStyle.maximumLineHeight = PrimitiveTokens.LineHeight.capture

        textView.font = font
        textView.defaultParagraphStyle = paragraphStyle
        textView.textContainerInset = NSSize(
            width: 0,
            height: AppUIConstants.captureEditorVerticalInset
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]

        if let textStorage = textView.textStorage, textStorage.length > 0 {
            textStorage.beginEditing()
            textStorage.addAttributes(
                [
                    .font: font,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraphStyle,
                ],
                range: NSRange(location: 0, length: textStorage.length)
            )
            textStorage.endEditing()
        }
    }

    private func drainMainQueue(seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
