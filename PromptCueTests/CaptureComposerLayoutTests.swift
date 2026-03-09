import AppKit
import SwiftUI
import XCTest
@testable import Prompt_Cue

@MainActor
final class CaptureComposerLayoutTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testCaptureComposerKeepsStableHeightBetweenDetectedAndPreviewReady() throws {
        let coordinator = TestRecentScreenshotCoordinator()
        let model = makeModel(recentScreenshotCoordinator: coordinator)
        model.start()

        let previewURL = tempDirectoryURL.appendingPathComponent("preview.png")
        try Data("png".utf8).write(to: previewURL)

        let hostingView = makeHostingView(model: model)

        let sessionID = UUID()
        coordinator.emit(.detected(sessionID: sessionID, detectedAt: Date()))
        drainMainQueue()
        let detectedHeight = hostingView.fittingSize.height

        coordinator.emit(.previewReady(sessionID: sessionID, cacheURL: previewURL, thumbnailState: .ready))
        drainMainQueue()
        let previewHeight = hostingView.fittingSize.height

        XCTAssertEqual(detectedHeight, previewHeight, accuracy: 1)
    }

    func testCaptureComposerGrowsByOneLineForInjectedTwoLineMetric() throws {
        let model = makeModel()
        model.start()

        let hostingView = makeHostingView(model: model)

        model.updateDraftEditorMetrics(metric(forLineCount: 1))
        drainMainQueue()
        let singleLineHeight = hostingView.fittingSize.height

        model.updateDraftEditorMetrics(metric(forLineCount: 2))
        drainMainQueue()
        let twoLineHeight = hostingView.fittingSize.height

        XCTAssertEqual(
            twoLineHeight - singleLineHeight,
            PrimitiveTokens.LineHeight.capture,
            accuracy: 1
        )
    }

    func testCaptureComposerHonorsInjectedMaxHeightMetricWithoutExtraGrowth() throws {
        let model = makeModel()
        model.start()

        let hostingView = makeHostingView(model: model)

        model.updateDraftEditorMetrics(metric(visibleHeight: AppUIConstants.captureEditorMaxHeight))
        drainMainQueue()
        let cappedHeight = hostingView.fittingSize.height

        model.updateDraftEditorMetrics(
            CaptureEditorMetrics(
                contentHeight: CaptureRuntimeMetrics.editorMaxHeight + PrimitiveTokens.LineHeight.capture,
                visibleHeight: CaptureRuntimeMetrics.editorMaxHeight,
                isScrollable: true,
                layoutWidth: CaptureRuntimeMetrics.editorViewportWidth
            )
        )
        drainMainQueue()
        let scrollableHeight = hostingView.fittingSize.height

        XCTAssertEqual(cappedHeight, scrollableHeight, accuracy: 1)
    }

    private func makeModel(
        recentScreenshotCoordinator: RecentScreenshotCoordinating? = nil
    ) -> AppModel {
        AppModel(
            cardStore: CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")),
            attachmentStore: AttachmentStore(
                baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
            ),
            recentScreenshotCoordinator: recentScreenshotCoordinator ?? TestRecentScreenshotCoordinator()
        )
    }

    private func makeHostingView(model: AppModel) -> NSHostingView<CaptureComposerView> {
        let hostingView = NSHostingView(rootView: CaptureComposerView(model: model))
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: AppUIConstants.capturePanelWidth,
            height: 320
        )

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        return hostingView
    }

    private func metric(forLineCount lineCount: Int) -> CaptureEditorMetrics {
        metric(
            visibleHeight: (CGFloat(lineCount) * PrimitiveTokens.LineHeight.capture)
                + (CaptureRuntimeMetrics.editorVerticalInset * 2)
                + CaptureRuntimeMetrics.editorBottomBreathingRoom
        )
    }

    private func metric(visibleHeight: CGFloat) -> CaptureEditorMetrics {
        CaptureEditorMetrics(
            contentHeight: visibleHeight,
            visibleHeight: visibleHeight,
            isScrollable: false,
            layoutWidth: CaptureRuntimeMetrics.editorViewportWidth
        )
    }

    private func drainMainQueue(seconds: TimeInterval = 0.1) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

@MainActor
private final class TestRecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var state: RecentScreenshotState = .idle
    var onStateChange: ((RecentScreenshotState) -> Void)?

    func start() {}
    func stop() {}
    func prepareForCaptureSession() {}
    func refreshNow() {}
    func consumeCurrent() {}
    func dismissCurrent() {}

    func emit(_ nextState: RecentScreenshotState) {
        state = nextState
        onStateChange?(nextState)
    }
}
