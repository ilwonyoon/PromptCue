import Foundation
import PromptCueCore
import XCTest
@testable import Prompt_Cue

@MainActor
final class AppModelRecentScreenshotTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testBeginCaptureSessionConsumesDetectedStateImmediately() throws {
        let cardStore = CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite"))
        let attachmentStore = AttachmentStore(baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments"))
        let coordinator = TestRecentScreenshotCoordinator()
        let model = AppModel(
            cardStore: cardStore,
            attachmentStore: attachmentStore,
            recentScreenshotCoordinator: coordinator
        )

        model.start()
        coordinator.nextPreparedState = .detected(sessionID: UUID(), detectedAt: Date())

        model.beginCaptureSession()

        XCTAssertTrue(model.showsRecentScreenshotSlot)
        XCTAssertTrue(model.showsRecentScreenshotPlaceholder)
    }

    func testStartDoesNotStartRecentScreenshotCoordinatorUntilCaptureSession() throws {
        let cardStore = CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite"))
        let attachmentStore = AttachmentStore(baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments"))
        let coordinator = TestRecentScreenshotCoordinator()
        let model = AppModel(
            cardStore: cardStore,
            attachmentStore: attachmentStore,
            recentScreenshotCoordinator: coordinator
        )

        model.start()

        XCTAssertEqual(coordinator.startCallCount, 0)

        model.beginCaptureSession()

        XCTAssertEqual(coordinator.startCallCount, 1)
        XCTAssertEqual(coordinator.prepareForCaptureSessionCallCount, 1)
    }

    func testSubmitCapturePersistsImageOnlyCardWhenDetectedStateResolvesToAttachment() async throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let attachmentDirectoryURL = tempDirectoryURL.appendingPathComponent("Attachments")
        let cacheURL = tempDirectoryURL.appendingPathComponent("recent-preview.png")
        try Data("png".utf8).write(to: cacheURL)

        let cardStore = CardStore(databaseURL: databaseURL)
        let attachmentStore = AttachmentStore(baseDirectoryURL: attachmentDirectoryURL)
        let coordinator = TestRecentScreenshotCoordinator()
        let model = AppModel(
            cardStore: cardStore,
            attachmentStore: attachmentStore,
            recentScreenshotCoordinator: coordinator
        )

        model.start()
        coordinator.nextPreparedState = .detected(sessionID: UUID(), detectedAt: Date())
        coordinator.resolvedAttachmentURL = cacheURL
        model.beginCaptureSession()

        let didSubmit = await model.submitCapture()

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(model.cards.first?.text, "Screenshot attached")
        XCTAssertNotNil(model.cards.first?.screenshotPath)
        XCTAssertTrue(model.cards.first?.screenshotURL?.path.hasPrefix(attachmentDirectoryURL.path) == true)
        XCTAssertEqual(coordinator.consumeCurrentCallCount, 1)
    }

    func testSubmitCaptureFailsWhenDetectedStateDoesNotResolveAndTextIsEmpty() async throws {
        let cardStore = CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite"))
        let attachmentStore = AttachmentStore(baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments"))
        let coordinator = TestRecentScreenshotCoordinator()
        let model = AppModel(
            cardStore: cardStore,
            attachmentStore: attachmentStore,
            recentScreenshotCoordinator: coordinator
        )

        model.start()
        coordinator.nextPreparedState = .detected(sessionID: UUID(), detectedAt: Date())
        coordinator.resolvedAttachmentURL = nil
        model.beginCaptureSession()

        let didSubmit = await model.submitCapture()

        XCTAssertFalse(didSubmit)
        XCTAssertTrue(model.cards.isEmpty)
    }

    func testWaitForCaptureSubmissionToSettleWaitsForDelayedResolve() async throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let attachmentDirectoryURL = tempDirectoryURL.appendingPathComponent("Attachments")
        let cacheURL = tempDirectoryURL.appendingPathComponent("recent-preview-delayed.png")
        try Data("png".utf8).write(to: cacheURL)

        let cardStore = CardStore(databaseURL: databaseURL)
        let attachmentStore = AttachmentStore(baseDirectoryURL: attachmentDirectoryURL)
        let coordinator = TestRecentScreenshotCoordinator()
        coordinator.resolveDelay = 0.15
        let model = AppModel(
            cardStore: cardStore,
            attachmentStore: attachmentStore,
            recentScreenshotCoordinator: coordinator
        )

        model.start()
        coordinator.nextPreparedState = .detected(sessionID: UUID(), detectedAt: Date())
        coordinator.resolvedAttachmentURL = cacheURL
        model.beginCaptureSession()

        let submitTask = Task { await model.submitCapture() }
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertTrue(model.isSubmittingCapture)

        await model.waitForCaptureSubmissionToSettle(timeout: 0.5)
        let didSubmit = await submitTask.value

        XCTAssertTrue(didSubmit)
        XCTAssertFalse(model.isSubmittingCapture)
        XCTAssertEqual(model.cards.count, 1)
    }

    func testBeginCaptureSubmissionMarksSubmittingSynchronouslyAndPersistsCard() async throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let attachmentDirectoryURL = tempDirectoryURL.appendingPathComponent("Attachments")
        let cacheURL = tempDirectoryURL.appendingPathComponent("recent-preview-begin.png")
        try Data("png".utf8).write(to: cacheURL)

        let cardStore = CardStore(databaseURL: databaseURL)
        let attachmentStore = AttachmentStore(baseDirectoryURL: attachmentDirectoryURL)
        let coordinator = TestRecentScreenshotCoordinator()
        coordinator.resolveDelay = 0.12
        let model = AppModel(
            cardStore: cardStore,
            attachmentStore: attachmentStore,
            recentScreenshotCoordinator: coordinator
        )

        model.start()
        coordinator.nextPreparedState = .detected(sessionID: UUID(), detectedAt: Date())
        coordinator.resolvedAttachmentURL = cacheURL
        model.beginCaptureSession()

        model.beginCaptureSubmission()

        XCTAssertTrue(model.isSubmittingCapture)

        await model.waitForCaptureSubmissionToSettle(timeout: 1.0)

        XCTAssertFalse(model.isSubmittingCapture)
        XCTAssertEqual(model.cards.count, 1)
    }

    func testBeginCaptureSessionShowsSlotImmediatelyAndSubmitWaitsForAsyncReadablePromotion() async throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let attachmentDirectoryURL = tempDirectoryURL.appendingPathComponent("Attachments")
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let transientCacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)

        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-10 at 01.08.30.png")
        let screenshotData = Data("png".utf8)
        try screenshotData.write(to: screenshotURL)

        let candidate = RecentScreenshotCandidate(
            attachment: ScreenshotAttachment(
                path: screenshotURL.path,
                modifiedAt: Date(),
                fileSize: screenshotData.count
            ),
            sourceKey: screenshotURL.lastPathComponent.lowercased()
        )
        let signalResult = RecentScreenshotScanResult(
            signalCandidate: candidate,
            readableCandidate: nil,
            recentTemporaryContainerDate: nil
        )
        let fullResult = RecentScreenshotScanResult(
            signalCandidate: candidate,
            readableCandidate: candidate,
            recentTemporaryContainerDate: nil
        )
        let coordinator = RecentScreenshotCoordinator(
            observer: AppModelTestRecentScreenshotObserver(),
            locator: AppModelDelayedSignalProbeLocator(
                fullScanDelay: 0.2,
                signalResult: signalResult,
                fullResult: fullResult
            ),
            cache: TransientScreenshotCache(baseDirectoryURL: transientCacheURL),
            clipboardProvider: AppModelNilClipboardProvider(),
            maxAge: 30,
            settleGrace: 0.2
        )
        let cardStore = CardStore(databaseURL: databaseURL)
        let attachmentStore = AttachmentStore(baseDirectoryURL: attachmentDirectoryURL)
        let model = AppModel(
            cardStore: cardStore,
            attachmentStore: attachmentStore,
            recentScreenshotCoordinator: coordinator
        )

        model.start()
        model.beginCaptureSession()

        XCTAssertTrue(model.showsRecentScreenshotSlot)
        XCTAssertTrue(model.showsRecentScreenshotPlaceholder)

        let didSubmit = await model.submitCapture()

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(model.cards.first?.text, "Screenshot attached")
        XCTAssertTrue(model.cards.first?.screenshotURL?.path.hasPrefix(attachmentDirectoryURL.path) == true)
    }

}

@MainActor
private final class TestRecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var state: RecentScreenshotState = .idle
    var onStateChange: ((RecentScreenshotState) -> Void)?
    var nextPreparedState: RecentScreenshotState = .idle
    var resolvedAttachmentURL: URL?
    var resolveDelay: TimeInterval = 0
    private(set) var startCallCount = 0
    private(set) var prepareForCaptureSessionCallCount = 0
    private(set) var consumeCurrentCallCount = 0

    func start() {
        startCallCount += 1
    }
    func stop() {}

    func prepareForCaptureSession() {
        prepareForCaptureSessionCallCount += 1
        state = nextPreparedState
        onStateChange?(state)
    }

    func refreshNow() {
        onStateChange?(state)
    }

    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? {
        if resolveDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(resolveDelay * 1_000_000_000))
        }

        if let resolvedAttachmentURL {
            state = .previewReady(sessionID: state.sessionID ?? UUID(), cacheURL: resolvedAttachmentURL, thumbnailState: .ready)
            onStateChange?(state)
        }

        return resolvedAttachmentURL
    }

    func consumeCurrent() {
        consumeCurrentCallCount += 1
    }
    func dismissCurrent() {}
}

@MainActor
private final class AppModelTestRecentScreenshotObserver: RecentScreenshotObserving {
    var onChange: ((RecentScreenshotObservationEvent) -> Void)?

    func start() {}
    func stop() {}
}

@MainActor
private final class AppModelNilClipboardProvider: RecentClipboardImageProviding {
    func start() {}
    func stop() {}
    func refreshNow() {}
    func recentImage(referenceDate: Date, maxAge: TimeInterval) -> RecentClipboardImage? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
}

private struct AppModelDelayedSignalProbeLocator: RecentScreenshotLocating {
    let fullScanDelay: TimeInterval
    let signalResult: RecentScreenshotScanResult
    let fullResult: RecentScreenshotScanResult

    func locateRecentScreenshot(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        Thread.sleep(forTimeInterval: fullScanDelay)
        return fullResult
    }

    func locateRecentScreenshotSignal(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        signalResult
    }
}
