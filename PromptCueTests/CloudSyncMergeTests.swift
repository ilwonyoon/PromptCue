import Foundation
import XCTest
@testable import Prompt_Cue
import PromptCueCore

@MainActor
final class CloudSyncMergeTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var model: AppModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        model = makeModel()
    }

    override func tearDownWithError() throws {
        model = nil
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Merge: New Card from Remote

    func testRemoteUpsertAddsNewCard() {
        let remoteCard = CaptureCard(text: "Remote note", createdAt: Date())

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: nil)
        ])

        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(model.cards.first?.text, "Remote note")
    }

    func testRemoteDeleteRemovesExistingCard() throws {
        let card = CaptureCard(text: "Delete me", createdAt: Date())
        try saveCards([card])
        model.reloadCards()

        model.applyRemoteChanges([
            .delete(card.id)
        ])

        XCTAssertTrue(model.cards.isEmpty)
    }

    // MARK: - Merge: Conflict Resolution

    func testLocalCopiedWinsOverRemoteUncopied() throws {
        let cardID = UUID()
        let localCard = CaptureCard(
            id: cardID,
            text: "Local",
            createdAt: Date(),
            lastCopiedAt: Date()
        )
        try saveCards([localCard])
        model.reloadCards()

        let remoteCard = CaptureCard(
            id: cardID,
            text: "Remote",
            createdAt: Date(),
            lastCopiedAt: nil
        )

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: nil)
        ])

        XCTAssertEqual(model.cards.first?.text, "Local")
    }

    func testRemoteCopiedWinsOverLocalUncopied() throws {
        let cardID = UUID()
        let localCard = CaptureCard(
            id: cardID,
            text: "Local",
            createdAt: Date(),
            lastCopiedAt: nil
        )
        try saveCards([localCard])
        model.reloadCards()

        let remoteCopiedAt = Date()
        let remoteCard = CaptureCard(
            id: cardID,
            text: "Remote",
            createdAt: Date(),
            lastCopiedAt: remoteCopiedAt
        )

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: nil)
        ])

        XCTAssertEqual(model.cards.first?.text, "Remote")
        XCTAssertEqual(model.cards.first?.lastCopiedAt, remoteCopiedAt)
    }

    func testMoreRecentCopiedWins() throws {
        let cardID = UUID()
        let earlyDate = Date(timeIntervalSince1970: 1000)
        let lateDate = Date(timeIntervalSince1970: 2000)

        let localCard = CaptureCard(
            id: cardID,
            text: "Local",
            createdAt: Date(),
            lastCopiedAt: earlyDate
        )
        try saveCards([localCard])
        model.reloadCards()

        let remoteCard = CaptureCard(
            id: cardID,
            text: "Remote",
            createdAt: Date(),
            lastCopiedAt: lateDate
        )

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: nil)
        ])

        XCTAssertEqual(model.cards.first?.text, "Remote")
    }

    func testBothUncopiedKeepsLocal() throws {
        let cardID = UUID()
        let localCard = CaptureCard(
            id: cardID,
            text: "Local",
            createdAt: Date()
        )
        try saveCards([localCard])
        model.reloadCards()

        let remoteCard = CaptureCard(
            id: cardID,
            text: "Remote",
            createdAt: Date()
        )

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: nil)
        ])

        XCTAssertEqual(model.cards.first?.text, "Local")
    }

    // MARK: - Screenshot Preservation

    func testMergePreservesLocalScreenshotWhenRemoteWins() throws {
        let cardID = UUID()
        let sourceURL = tempDirectoryURL.appendingPathComponent("test.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)

        let importedURL = try AttachmentStore(
            baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
        ).importScreenshot(from: sourceURL, ownerID: cardID)

        let localCard = CaptureCard(
            id: cardID,
            text: "Local",
            createdAt: Date(),
            screenshotPath: importedURL.path,
            lastCopiedAt: nil
        )
        try saveCards([localCard])
        model.reloadCards()

        let remoteCard = CaptureCard(
            id: cardID,
            text: "Remote",
            createdAt: Date(),
            screenshotPath: nil,
            lastCopiedAt: Date()
        )

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: nil)
        ])

        let merged = model.cards.first
        XCTAssertEqual(merged?.text, "Remote")
        XCTAssertEqual(merged?.screenshotPath, importedURL.path)
    }

    func testMergePreservesRemoteScreenshotWhenLocalWins() throws {
        let cardID = UUID()

        let localCard = CaptureCard(
            id: cardID,
            text: "Local",
            createdAt: Date(),
            screenshotPath: nil,
            lastCopiedAt: Date()
        )
        try saveCards([localCard])
        model.reloadCards()

        let remoteScreenshotURL = tempDirectoryURL.appendingPathComponent("remote.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: remoteScreenshotURL)

        let importedURL = try AttachmentStore(
            baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
        ).importScreenshot(from: remoteScreenshotURL, ownerID: cardID)

        let remoteCard = CaptureCard(
            id: cardID,
            text: "Remote",
            createdAt: Date(),
            screenshotPath: importedURL.path,
            lastCopiedAt: nil
        )

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: nil)
        ])

        let merged = model.cards.first
        XCTAssertEqual(merged?.text, "Local")
        XCTAssertEqual(merged?.screenshotPath, importedURL.path)
    }

    // MARK: - Remote Screenshot Import

    func testRemoteScreenshotAssetIsImportedLocally() throws {
        let assetFile = tempDirectoryURL.appendingPathComponent("cloud-asset.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: assetFile)

        let remoteCard = CaptureCard(text: "With screenshot", createdAt: Date())

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: assetFile)
        ])

        let card = model.cards.first
        XCTAssertNotNil(card?.screenshotPath)
        XCTAssertTrue(card?.screenshotPath?.contains("Attachments") == true)
    }

    func testRemoteScreenshotMissingFileGracefullySkipped() {
        let missingURL = tempDirectoryURL.appendingPathComponent("nonexistent.png")
        let remoteCard = CaptureCard(text: "No file", createdAt: Date())

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: missingURL)
        ])

        let card = model.cards.first
        XCTAssertNotNil(card)
        XCTAssertNil(card?.screenshotPath)
    }

    func testRemoteExternalScreenshotPathIsIgnoredWithoutImportedAsset() {
        let remoteCard = CaptureCard(
            text: "External path should not survive",
            createdAt: Date(),
            screenshotPath: tempDirectoryURL.appendingPathComponent("external.png").path
        )

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: nil)
        ])

        let card = model.cards.first
        XCTAssertNotNil(card)
        XCTAssertNil(card?.screenshotPath)
    }

    func testRemoteApplySkipsAssetImportWhenLocalWinnerAlreadyHasScreenshot() throws {
        let attachmentsURL = tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
        let localCard = CaptureCard(
            id: UUID(),
            text: "Local keeps screenshot",
            createdAt: Date(),
            screenshotPath: attachmentsURL.appendingPathComponent("local.png").path,
            lastCopiedAt: Date(timeIntervalSince1970: 2_000)
        )
        try saveCards([localCard])
        let attachmentStore = CountingAttachmentStore(baseDirectoryURL: attachmentsURL)
        model = makeModel(attachmentStore: attachmentStore)
        model.reloadCards()

        let assetFile = tempDirectoryURL.appendingPathComponent("redundant-remote.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: assetFile)
        let remoteCard = CaptureCard(
            id: localCard.id,
            text: "Remote loses merge",
            createdAt: localCard.createdAt,
            lastCopiedAt: Date(timeIntervalSince1970: 1_000)
        )

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: assetFile)
        ])

        XCTAssertEqual(attachmentStore.importCallCount, 0)
        XCTAssertEqual(model.cards.first?.screenshotPath, localCard.screenshotPath)
        XCTAssertEqual(model.cards.first?.text, localCard.text)
    }

    func testRemoteApplyImportsAssetWhenLocalWinnerNeedsScreenshot() throws {
        let attachmentsURL = tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
        let localCard = CaptureCard(
            id: UUID(),
            text: "Local needs screenshot",
            createdAt: Date(),
            screenshotPath: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 2_000)
        )
        try saveCards([localCard])
        let attachmentStore = CountingAttachmentStore(baseDirectoryURL: attachmentsURL)
        model = makeModel(attachmentStore: attachmentStore)
        model.reloadCards()

        let assetFile = tempDirectoryURL.appendingPathComponent("needed-remote.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: assetFile)
        let remoteCard = CaptureCard(
            id: localCard.id,
            text: "Remote loses merge",
            createdAt: localCard.createdAt,
            lastCopiedAt: Date(timeIntervalSince1970: 1_000)
        )

        model.applyRemoteChanges([
            .upsert(remoteCard, screenshotAssetURL: assetFile)
        ])

        XCTAssertEqual(attachmentStore.importCallCount, 1)
        XCTAssertEqual(model.cards.first?.text, localCard.text)
        XCTAssertNotNil(model.cards.first?.screenshotPath)
    }

    func testScheduledRemoteChangesApplyEventually() async throws {
        let remoteCard = CaptureCard(text: "Queued remote note", createdAt: Date())

        model.scheduleRemoteChangesForApply([
            .upsert(remoteCard, screenshotAssetURL: nil)
        ])
        await model.waitForRemoteApplyToDrain()

        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(model.cards.first?.text, "Queued remote note")
    }

    func testScheduledRemoteChangesSkipAssetImportWhenLocalWinnerAlreadyHasScreenshot() async throws {
        let attachmentsURL = tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
        let localCard = CaptureCard(
            id: UUID(),
            text: "Local keeps screenshot",
            createdAt: Date(),
            screenshotPath: attachmentsURL.appendingPathComponent("local.png").path,
            lastCopiedAt: Date(timeIntervalSince1970: 2_000)
        )
        try saveCards([localCard])
        let attachmentStore = CountingAttachmentStore(baseDirectoryURL: attachmentsURL)
        model = makeModel(attachmentStore: attachmentStore)
        model.reloadCards()

        let assetFile = tempDirectoryURL.appendingPathComponent("queued-redundant-remote.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: assetFile)
        let remoteCard = CaptureCard(
            id: localCard.id,
            text: "Remote loses merge",
            createdAt: localCard.createdAt,
            lastCopiedAt: Date(timeIntervalSince1970: 1_000)
        )

        model.scheduleRemoteChangesForApply([
            .upsert(remoteCard, screenshotAssetURL: assetFile)
        ])
        await model.waitForRemoteApplyToDrain()

        XCTAssertEqual(attachmentStore.importCallCount, 0)
        XCTAssertEqual(model.cards.first?.screenshotPath, localCard.screenshotPath)
        XCTAssertEqual(model.cards.first?.text, localCard.text)
    }

    func testScheduledRemoteChangesImportAssetWhenLocalWinnerNeedsScreenshot() async throws {
        let attachmentsURL = tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
        let localCard = CaptureCard(
            id: UUID(),
            text: "Local needs screenshot",
            createdAt: Date(),
            screenshotPath: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 2_000)
        )
        try saveCards([localCard])
        let attachmentStore = CountingAttachmentStore(baseDirectoryURL: attachmentsURL)
        model = makeModel(attachmentStore: attachmentStore)
        model.reloadCards()

        let assetFile = tempDirectoryURL.appendingPathComponent("queued-needed-remote.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: assetFile)
        let remoteCard = CaptureCard(
            id: localCard.id,
            text: "Remote loses merge",
            createdAt: localCard.createdAt,
            lastCopiedAt: Date(timeIntervalSince1970: 1_000)
        )

        model.scheduleRemoteChangesForApply([
            .upsert(remoteCard, screenshotAssetURL: assetFile)
        ])
        await model.waitForRemoteApplyToDrain()

        XCTAssertEqual(attachmentStore.importCallCount, 1)
        XCTAssertEqual(model.cards.first?.text, localCard.text)
        XCTAssertNotNil(model.cards.first?.screenshotPath)
    }

    // MARK: - Selection Cleanup on Delete

    func testRemoteDeleteClearsSelectionForDeletedCard() throws {
        let card = CaptureCard(text: "Selected", createdAt: Date())
        try saveCards([card])
        model.reloadCards()
        model.toggleSelection(for: card)
        XCTAssertTrue(model.selectedCardIDs.contains(card.id))

        model.applyRemoteChanges([
            .delete(card.id)
        ])

        XCTAssertFalse(model.selectedCardIDs.contains(card.id))
    }

    // MARK: - Helpers

    private func makeModel(attachmentStore: AttachmentStoring? = nil) -> AppModel {
        AppModel(
            cardStore: CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")),
            attachmentStore: attachmentStore ?? AttachmentStore(
                baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
            ),
            recentScreenshotCoordinator: TestSyncRecentScreenshotCoordinator()
        )
    }

    private func saveCards(_ cards: [CaptureCard]) throws {
        let store = CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite"))
        try store.save(cards)
    }
}

private final class CountingAttachmentStore: AttachmentStoring {
    let baseDirectoryURL: URL

    private(set) var importCallCount = 0

    init(baseDirectoryURL: URL) {
        self.baseDirectoryURL = baseDirectoryURL
    }

    func importScreenshot(from sourceURL: URL, ownerID: UUID) throws -> URL {
        importCallCount += 1
        return baseDirectoryURL
            .appendingPathComponent(ownerID.uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension(sourceURL.pathExtension)
    }

    func removeManagedFile(at fileURL: URL) throws {}
    func pruneUnreferencedManagedFiles(referencedFileURLs: Set<URL>) throws {}

    func isManagedFile(_ fileURL: URL) -> Bool {
        let standardizedURL = fileURL.standardizedFileURL
        let basePath = baseDirectoryURL.standardizedFileURL.path
        let filePath = standardizedURL.path
        return filePath == basePath || filePath.hasPrefix(basePath + "/")
    }
}

@MainActor
private final class TestSyncRecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var state: RecentScreenshotState = .idle
    var onStateChange: ((RecentScreenshotState) -> Void)?

    func start() {}
    func stop() {}
    func prepareForCaptureSession() {}
    func refreshNow() {}
    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
}
