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

    func testSubmitCaptureWhileEditingUpdatesExistingCardInsteadOfCreatingNewOne() async throws {
        let card = CaptureCard(
            id: UUID(),
            text: "Original text",
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

    func testBeginEditingPreservesRawInlineTagText() {
        let card = CaptureCard(
            id: UUID(),
            text: "Discuss #design follow-up",
            tags: [CaptureTag(rawValue: "design")].compactMap { $0 },
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            sortOrder: 10
        )

        let model = makeModel()
        model.start()

        model.beginEditingCaptureCard(card)

        XCTAssertEqual(model.draftText, "Discuss #design follow-up")
    }

    func testSubmitCaptureDerivesCanonicalTagsFromInlineRawText() async throws {
        let model = makeModel()
        model.start()
        model.beginCaptureSession()
        model.draftText = "Ship #design review with #Design and #한글 notes"

        let didSubmit = await model.submitCapture()

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(model.cards.first?.text, "Ship #design review with #Design and #한글 notes")
        XCTAssertEqual(model.cards.first?.tags.map(\.name), ["design"])

        let loadedCards = try CardStore(databaseURL: databaseURL).load()
        XCTAssertEqual(loadedCards.first?.text, "Ship #design review with #Design and #한글 notes")
        XCTAssertEqual(loadedCards.first?.tags.map(\.name), ["design"])
    }

    func testSubmitCapturePreservesTagTestPositionForStackDisplay() async throws {
        let model = makeModel()
        model.start()
        model.beginCaptureSession()
        model.draftText = "alpha beta #tag_test gamma"

        let didSubmit = await model.submitCapture()

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(model.cards.first?.text, "alpha beta #tag_test gamma")
        XCTAssertEqual(model.cards.first?.tags.map(\.name), ["tag_test"])
        XCTAssertEqual(model.cards.first?.visibleInlineText, "alpha beta #tag_test gamma")
        XCTAssertEqual(model.cards.first?.visibleInlineTagRanges, [
            NSRange(location: 11, length: 9),
        ])

        let loadedCards = try CardStore(databaseURL: databaseURL).load()
        XCTAssertEqual(loadedCards.first?.text, "alpha beta #tag_test gamma")
        XCTAssertEqual(loadedCards.first?.tags.map(\.name), ["tag_test"])
        XCTAssertEqual(loadedCards.first?.visibleInlineText, "alpha beta #tag_test gamma")
        XCTAssertEqual(loadedCards.first?.visibleInlineTagRanges, [
            NSRange(location: 11, length: 9),
        ])
    }

    func testBeginEditingHidesExternalScreenshotPreviewUntilAttachmentIsManaged() throws {
        let externalScreenshotURL = tempDirectoryURL.appendingPathComponent("external.png")
        try Data("png".utf8).write(to: externalScreenshotURL)

        let card = CaptureCard(
            id: UUID(),
            text: "External screenshot",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            screenshotPath: externalScreenshotURL.path,
            sortOrder: 10
        )

        let model = makeModel()
        model.start()

        model.beginEditingCaptureCard(card)

        XCTAssertNil(model.recentScreenshotPreviewURL)
    }

    private func makeModel() -> AppModel {
        AppModel(
            cardStore: CardStore(databaseURL: databaseURL),
            attachmentStore: AttachmentStore(baseDirectoryURL: attachmentDirectoryURL),
            recentScreenshotCoordinator: EditingTestRecentScreenshotCoordinator()
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
