import Foundation
import PromptCueCore
import XCTest
@testable import Prompt_Cue

@MainActor
final class AppModelLicensingTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var databaseURL: URL!
    private var attachmentDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        attachmentDirectoryURL = tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }

        tempDirectoryURL = nil
        databaseURL = nil
        attachmentDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testSubmitCaptureBlocksNewSaveWhenTrialExpired() async throws {
        let accessController = TestCaptureAccessController(
            snapshot: AppAccessSnapshot(
                status: .expired(.trialExpired(expiredAt: Date(timeIntervalSince1970: 1_000)))
            )
        )
        let model = makeModel(captureAccessController: accessController)

        model.start()
        model.beginCaptureSession()
        model.draftText = "Capture should stay read-only"

        let didSubmit = await model.submitCapture()

        XCTAssertFalse(didSubmit)
        XCTAssertTrue(model.cards.isEmpty)
        XCTAssertEqual(accessController.blockedAttemptCount, 1)
        XCTAssertEqual(try CardStore(databaseURL: databaseURL).load().count, 0)
    }

    func testSubmitCaptureBlocksEditingExistingCardWhenTrialExpired() async throws {
        let card = CaptureCard(
            id: UUID(),
            text: "Original text",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            sortOrder: 10
        )
        try CardStore(databaseURL: databaseURL).save([card])

        let accessController = TestCaptureAccessController(
            snapshot: AppAccessSnapshot(
                status: .expired(.trialExpired(expiredAt: Date(timeIntervalSince1970: 1_000)))
            )
        )
        let model = makeModel(captureAccessController: accessController)

        model.start()
        model.beginEditingCaptureCard(card)
        model.beginCaptureSession()
        model.draftText = "Edited text that should not persist"

        let didSubmit = await model.submitCapture()
        let loadedCards = try CardStore(databaseURL: databaseURL).load()

        XCTAssertFalse(didSubmit)
        XCTAssertEqual(accessController.blockedAttemptCount, 1)
        XCTAssertEqual(loadedCards.count, 1)
        XCTAssertEqual(loadedCards.first?.text, "Original text")
    }

    private func makeModel(
        captureAccessController: any CaptureAccessControlling
    ) -> AppModel {
        AppModel(
            cardStore: CardStore(databaseURL: databaseURL),
            attachmentStore: AttachmentStore(baseDirectoryURL: attachmentDirectoryURL),
            recentScreenshotCoordinator: LicensingTestRecentScreenshotCoordinator(),
            captureAccessController: captureAccessController
        )
    }
}

@MainActor
private final class TestCaptureAccessController: CaptureAccessControlling {
    let accessSnapshot: AppAccessSnapshot
    private(set) var blockedAttemptCount = 0

    init(snapshot: AppAccessSnapshot) {
        self.accessSnapshot = snapshot
    }

    func handleBlockedCaptureAttempt() {
        blockedAttemptCount += 1
    }
}

@MainActor
private final class LicensingTestRecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var state: RecentScreenshotState = .idle
    var onStateChange: ((RecentScreenshotState) -> Void)?

    func start() {}
    func stop() {}
    func prepareForCaptureSession() {}
    func endCaptureSession() {}
    func refreshNow() {}
    func suspendExpiration() {}
    func resumeExpiration() {}
    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
}
