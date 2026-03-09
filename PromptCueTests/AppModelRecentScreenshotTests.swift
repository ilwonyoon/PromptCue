import Foundation
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

}

@MainActor
private final class TestRecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var state: RecentScreenshotState = .idle
    var onStateChange: ((RecentScreenshotState) -> Void)?
    var nextPreparedState: RecentScreenshotState = .idle
    var resolvedAttachmentURL: URL?
    var resolveDelay: TimeInterval = 0
    private(set) var consumeCurrentCallCount = 0

    func start() {}
    func stop() {}

    func prepareForCaptureSession() {
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
