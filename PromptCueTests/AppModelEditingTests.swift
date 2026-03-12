import Foundation
import PromptCueCore
import XCTest
@testable import Prompt_Cue

@MainActor
final class AppModelEditingTests: XCTestCase {
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

    func testBeginEditingSeedsDraftAndPreservesCardSuggestedTarget() throws {
        let cardTarget = makeTarget(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            repo: "Backtick",
            branch: "feature/edit"
        )
        let automaticTarget = makeTarget(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            repo: "PromptCue",
            branch: "main"
        )
        let screenshotURL = attachmentDirectoryURL.appendingPathComponent("seeded-preview.png")
        try Data("png".utf8).write(to: screenshotURL)

        let card = CaptureCard(
            id: UUID(),
            text: "Seeded card",
            suggestedTarget: cardTarget,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            screenshotPath: screenshotURL.path,
            sortOrder: 10
        )
        try CardStore(databaseURL: databaseURL).save([card])

        let model = makeModel(
            provider: EditingTestSuggestedTargetProvider(
                latestTarget: automaticTarget,
                availableTargets: [automaticTarget]
            )
        )

        model.start()
        model.beginEditingCaptureCard(card)
        model.beginCaptureSession()

        XCTAssertTrue(model.isEditingCaptureCard)
        XCTAssertEqual(model.editingCaptureCardID, card.id)
        XCTAssertEqual(model.draftText, card.text)
        XCTAssertEqual(model.captureChooserTarget?.canonicalIdentityKey, cardTarget.canonicalIdentityKey)
        XCTAssertEqual(model.recentScreenshotPreviewURL?.path, screenshotURL.path)
    }

    func testSubmitCaptureWhileEditingUpdatesExistingCardInsteadOfCreatingNewOne() async throws {
        let cardTarget = makeTarget(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            repo: "Backtick",
            branch: "feature/edit"
        )
        let card = CaptureCard(
            id: UUID(),
            text: "Original text",
            suggestedTarget: cardTarget,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            sortOrder: 10
        )
        try CardStore(databaseURL: databaseURL).save([card])

        let model = makeModel()
        model.start()
        model.beginEditingCaptureCard(card)
        model.beginCaptureSession()
        model.draftText = "Edited text"

        let didSubmit = await model.submitCapture()

        XCTAssertTrue(didSubmit)
        XCTAssertFalse(model.isEditingCaptureCard)
        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(model.cards.first?.id, card.id)
        XCTAssertEqual(model.cards.first?.text, "Edited text")
        XCTAssertEqual(model.cards.first?.createdAt, card.createdAt)
        XCTAssertEqual(model.cards.first?.sortOrder, card.sortOrder)
        XCTAssertEqual(model.cards.first?.suggestedTarget, cardTarget)
        XCTAssertEqual(model.draftText, "")

        let loadedCards = try CardStore(databaseURL: databaseURL).load()
        XCTAssertEqual(loadedCards.count, 1)
        XCTAssertEqual(loadedCards.first?.id, card.id)
        XCTAssertEqual(loadedCards.first?.text, "Edited text")
    }

    func testSubmitCaptureWhileEditingCanRemoveManagedScreenshot() async throws {
        let screenshotURL = attachmentDirectoryURL.appendingPathComponent("managed-shot.png")
        try Data("png".utf8).write(to: screenshotURL)

        let card = CaptureCard(
            id: UUID(),
            text: "Screenshot card",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            screenshotPath: screenshotURL.path,
            sortOrder: 10
        )
        try CardStore(databaseURL: databaseURL).save([card])

        let model = makeModel()
        model.start()
        model.beginEditingCaptureCard(card)
        model.beginCaptureSession()
        model.dismissPendingScreenshot()
        model.draftText = "Edited without screenshot"

        let didSubmit = await model.submitCapture()

        XCTAssertTrue(didSubmit)
        XCTAssertNil(model.cards.first?.screenshotPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: screenshotURL.path))
    }

    func testSubmitCaptureFromCopiedCardEditCreatesNewActiveCard() async throws {
        let copiedAt = Date(timeIntervalSinceReferenceDate: 200)
        let copiedCard = CaptureCard(
            id: UUID(),
            text: "Copied source",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            lastCopiedAt: copiedAt,
            sortOrder: 10
        )
        try CardStore(databaseURL: databaseURL).save([copiedCard])

        let model = makeModel()
        model.start()
        model.beginEditingCaptureCard(copiedCard)
        model.beginCaptureSession()
        model.draftText = "Copied source refined"

        let didSubmit = await model.submitCapture()

        XCTAssertTrue(didSubmit)
        XCTAssertFalse(model.isEditingCaptureCard)
        XCTAssertEqual(model.cards.count, 2)

        let copiedCards = model.cards.filter(\.isCopied)
        let activeCards = model.cards.filter { !$0.isCopied }

        XCTAssertEqual(copiedCards.count, 1)
        XCTAssertEqual(copiedCards.first?.id, copiedCard.id)
        XCTAssertEqual(copiedCards.first?.text, copiedCard.text)
        XCTAssertEqual(activeCards.count, 1)
        XCTAssertNotEqual(activeCards.first?.id, copiedCard.id)
        XCTAssertEqual(activeCards.first?.text, "Copied source refined")
        XCTAssertNil(activeCards.first?.lastCopiedAt)
        XCTAssertEqual(model.draftText, "")
        XCTAssertNil(model.recentScreenshotPreviewURL)
    }

    private func makeModel(
        provider: EditingTestSuggestedTargetProvider? = nil
    ) -> AppModel {
        AppModel(
            cardStore: CardStore(databaseURL: databaseURL),
            attachmentStore: AttachmentStore(baseDirectoryURL: attachmentDirectoryURL),
            recentScreenshotCoordinator: EditingTestRecentScreenshotCoordinator(),
            suggestedTargetProvider: provider
        )
    }

    private func makeTarget(
        appName: String,
        bundleIdentifier: String,
        repo: String,
        branch: String
    ) -> CaptureSuggestedTarget {
        CaptureSuggestedTarget(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: "\(repo) window",
            sessionIdentifier: "\(appName)-1",
            currentWorkingDirectory: "/tmp/\(repo)",
            repositoryRoot: "/tmp/\(repo)",
            repositoryName: repo,
            branch: branch,
            capturedAt: Date(),
            confidence: .high
        )
    }
}

@MainActor
private final class EditingTestRecentScreenshotCoordinator: RecentScreenshotCoordinating {
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

@MainActor
private final class EditingTestSuggestedTargetProvider: SuggestedTargetProviding {
    var onChange: (() -> Void)?
    private let latestTarget: CaptureSuggestedTarget?
    private let availableTargets: [CaptureSuggestedTarget]

    init(latestTarget: CaptureSuggestedTarget?, availableTargets: [CaptureSuggestedTarget]) {
        self.latestTarget = latestTarget
        self.availableTargets = availableTargets
    }

    func start() {
        onChange?()
    }

    func stop() {}

    func currentFreshSuggestedTarget(
        relativeTo date: Date,
        freshness: TimeInterval
    ) -> CaptureSuggestedTarget? {
        guard let latestTarget,
              latestTarget.isFresh(relativeTo: date, freshness: freshness) else {
            return nil
        }

        return latestTarget
    }

    func availableSuggestedTargets() -> [CaptureSuggestedTarget] {
        availableTargets
    }

    func refreshAvailableSuggestedTargets() {
        onChange?()
    }
}
