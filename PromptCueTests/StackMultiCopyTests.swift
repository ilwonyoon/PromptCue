import Foundation
import XCTest
@testable import Prompt_Cue
import PromptCueCore

@MainActor
final class StackMultiCopyTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }

        tempDirectoryURL = nil
        databaseURL = nil
        try super.tearDownWithError()
    }

    func testToggleMultiCopyUpdatesClipboardInClickOrderAndLeavesCardsInPlaceUntilCommit() throws {
        let cards = [
            CaptureCard(id: UUID(), text: "Top", createdAt: Date(timeIntervalSinceReferenceDate: 300), sortOrder: 30),
            CaptureCard(id: UUID(), text: "Middle", createdAt: Date(timeIntervalSinceReferenceDate: 200), sortOrder: 20),
            CaptureCard(id: UUID(), text: "Bottom", createdAt: Date(timeIntervalSinceReferenceDate: 100), sortOrder: 10),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()

        let firstPayload = model.toggleMultiCopiedCard(cards[1])
        XCTAssertEqual(firstPayload, ClipboardFormatter.string(for: [cards[1]]))
        XCTAssertEqual(model.stagedCopiedCardIDs, [cards[1].id])
        XCTAssertTrue(model.isMultiSelectMode)

        let secondPayload = model.toggleMultiCopiedCard(cards[0])
        XCTAssertEqual(secondPayload, ClipboardFormatter.string(for: [cards[1], cards[0]]))
        XCTAssertEqual(model.stagedCopiedCardIDs, [cards[1].id, cards[0].id])
        XCTAssertTrue(model.isMultiSelectMode)

        let thirdPayload = model.toggleMultiCopiedCard(cards[1])
        XCTAssertEqual(thirdPayload, ClipboardFormatter.string(for: [cards[0]]))
        XCTAssertEqual(model.stagedCopiedCardIDs, [cards[0].id])
        XCTAssertTrue(model.isMultiSelectMode)

        let fourthPayload = model.toggleMultiCopiedCard(cards[0])

        XCTAssertNil(fourthPayload)
        XCTAssertEqual(model.cards.map(\.id), cards.map(\.id))
        XCTAssertTrue(model.stagedCopiedCardIDs.isEmpty)
        XCTAssertEqual(model.stagedCopiedCount, 0)
        XCTAssertFalse(model.isMultiSelectMode)
        XCTAssertTrue(model.selectedCardIDs.isEmpty)
        XCTAssertTrue(model.cards.allSatisfy { $0.lastCopiedAt == nil })
    }

    func testStackPanelCloseCommitsOnlyCurrentlyStagedCards() throws {
        let cards = [
            CaptureCard(id: UUID(), text: "Newest", createdAt: Date(timeIntervalSinceReferenceDate: 300), sortOrder: 30),
            CaptureCard(id: UUID(), text: "Older", createdAt: Date(timeIntervalSinceReferenceDate: 200), sortOrder: 20),
            CaptureCard(id: UUID(), text: "Oldest", createdAt: Date(timeIntervalSinceReferenceDate: 100), sortOrder: 10),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()
        _ = model.toggleMultiCopiedCard(cards[1])
        _ = model.toggleMultiCopiedCard(cards[0])
        _ = model.toggleMultiCopiedCard(cards[1])

        let controller = StackPanelController(model: model)
        controller.close()

        XCTAssertFalse(model.isMultiSelectMode)
        XCTAssertTrue(model.selectedCardIDs.isEmpty)
        XCTAssertTrue(model.stagedCopiedCardIDs.isEmpty)

        let activeIDs = model.cards.filter { !$0.isCopied }.map(\.id)
        let copiedIDs = model.cards.filter { $0.isCopied }.map(\.id)
        XCTAssertEqual(Set(activeIDs), [cards[1].id, cards[2].id])
        XCTAssertEqual(copiedIDs, [cards[0].id])
        XCTAssertTrue(model.cards.filter { $0.isCopied }.allSatisfy { $0.lastCopiedAt != nil })

        let loadedCards = try CardStore(databaseURL: databaseURL).load()
        let sortedLoadedCards = CardStackOrdering.sort(loadedCards)
        XCTAssertEqual(sortedLoadedCards.filter { $0.isCopied }.map(\.id), [cards[0].id])
    }

    func testStackPanelCloseWithoutStagedCardsLeavesCardsUncopied() throws {
        let cards = [
            CaptureCard(id: UUID(), text: "One", createdAt: Date(timeIntervalSinceReferenceDate: 100), sortOrder: 10),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()
        let controller = StackPanelController(model: model)
        controller.close()

        XCTAssertFalse(model.isMultiSelectMode)
        XCTAssertTrue(model.selectedCardIDs.isEmpty)
        XCTAssertTrue(model.stagedCopiedCardIDs.isEmpty)
        XCTAssertFalse(model.cards[0].isCopied)
    }

    func testStackPanelCloseWithoutCommitClearsDeferredCopiesWithoutMovingCards() throws {
        let cards = [
            CaptureCard(id: UUID(), text: "Top", createdAt: Date(timeIntervalSinceReferenceDate: 300), sortOrder: 30),
            CaptureCard(id: UUID(), text: "Middle", createdAt: Date(timeIntervalSinceReferenceDate: 200), sortOrder: 20),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()
        _ = model.toggleMultiCopiedCard(cards[0])
        _ = model.toggleMultiCopiedCard(cards[1])

        let controller = StackPanelController(model: model)
        controller.close(commitDeferredCopies: false)

        XCTAssertFalse(model.isMultiSelectMode)
        XCTAssertTrue(model.stagedCopiedCardIDs.isEmpty)
        XCTAssertTrue(model.selectedCardIDs.isEmpty)
        XCTAssertEqual(model.cards.map(\.id), cards.map(\.id))
        XCTAssertTrue(model.cards.allSatisfy { !$0.isCopied })
    }

    // MARK: - Single-copy-closes-panel tests

    func testSingleCardCopyMarksCardCopiedImmediately() throws {
        let cards = [
            CaptureCard(id: UUID(), text: "Alpha", createdAt: Date(timeIntervalSinceReferenceDate: 200), sortOrder: 20),
            CaptureCard(id: UUID(), text: "Beta", createdAt: Date(timeIntervalSinceReferenceDate: 100), sortOrder: 10),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()

        let payload = model.copySingleCard(cards[0])

        XCTAssertEqual(payload, ClipboardFormatter.string(for: [cards[0]]))
        XCTAssertFalse(model.isMultiSelectMode)
        XCTAssertTrue(model.stagedCopiedCardIDs.isEmpty)

        let copiedIDs = model.cards.filter(\.isCopied).map(\.id)
        XCTAssertEqual(copiedIDs, [cards[0].id])
        XCTAssertNil(model.cards.first { $0.id == cards[1].id }?.lastCopiedAt)
    }

    func testSingleCardCopyDoesNotAffectOtherCards() throws {
        let cards = [
            CaptureCard(id: UUID(), text: "First", createdAt: Date(timeIntervalSinceReferenceDate: 300), sortOrder: 30),
            CaptureCard(id: UUID(), text: "Second", createdAt: Date(timeIntervalSinceReferenceDate: 200), sortOrder: 20),
            CaptureCard(id: UUID(), text: "Third", createdAt: Date(timeIntervalSinceReferenceDate: 100), sortOrder: 10),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()

        _ = model.copySingleCard(cards[1])

        let activeIDs = model.cards.filter { !$0.isCopied }.map(\.id)
        XCTAssertEqual(Set(activeIDs), [cards[0].id, cards[2].id])
        XCTAssertTrue(model.cards.first { $0.id == cards[1].id }!.isCopied)
    }

    func testCmdClickEntersMultiSelectThenNormalCopyToggles() throws {
        let cards = [
            CaptureCard(id: UUID(), text: "One", createdAt: Date(timeIntervalSinceReferenceDate: 200), sortOrder: 20),
            CaptureCard(id: UUID(), text: "Two", createdAt: Date(timeIntervalSinceReferenceDate: 100), sortOrder: 10),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()

        // Cmd+click first card enters multi-select
        _ = model.toggleMultiCopiedCard(cards[0])
        XCTAssertTrue(model.isMultiSelectMode)
        XCTAssertEqual(model.stagedCopiedCardIDs, [cards[0].id])

        // In multi-select mode, toggleMultiCopiedCard adds second card
        _ = model.toggleMultiCopiedCard(cards[1])
        XCTAssertEqual(model.stagedCopiedCardIDs, [cards[0].id, cards[1].id])

        // Cards are NOT yet marked as copied (deferred)
        XCTAssertTrue(model.cards.allSatisfy { $0.lastCopiedAt == nil })
    }

    func testSingleCardCopyExitsActiveMultiSelectMode() throws {
        let cards = [
            CaptureCard(id: UUID(), text: "A", createdAt: Date(timeIntervalSinceReferenceDate: 200), sortOrder: 20),
            CaptureCard(id: UUID(), text: "B", createdAt: Date(timeIntervalSinceReferenceDate: 100), sortOrder: 10),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()

        // Enter multi-select by staging a card
        _ = model.toggleMultiCopiedCard(cards[0])
        XCTAssertTrue(model.isMultiSelectMode)

        // copySingleCard should exit multi-select and mark only the target card
        _ = model.copySingleCard(cards[1])
        XCTAssertFalse(model.isMultiSelectMode)
        XCTAssertTrue(model.stagedCopiedCardIDs.isEmpty)
        XCTAssertEqual(model.cards.filter(\.isCopied).map(\.id), [cards[1].id])
    }

    // MARK: - Copy raw tests

    func testCopyRawReturnsUnformattedTextAndMarksOnlyThatCardCopied() throws {
        let cards = [
            CaptureCard(id: UUID(), text: "Raw body", createdAt: Date(timeIntervalSinceReferenceDate: 200), sortOrder: 20),
            CaptureCard(id: UUID(), text: "Other", createdAt: Date(timeIntervalSinceReferenceDate: 100), sortOrder: 10),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()
        _ = model.toggleMultiCopiedCard(cards[1])

        let payload = model.copyRaw(card: cards[0])

        XCTAssertEqual(payload, "Raw body")
        XCTAssertFalse(model.isMultiSelectMode)
        XCTAssertTrue(model.stagedCopiedCardIDs.isEmpty)

        let copiedIDs = model.cards.filter(\.isCopied).map(\.id)
        XCTAssertEqual(copiedIDs, [cards[0].id])
    }

    func testMarkCardCopiedWithoutCopyMarksOnlyThatCardAndKeepsStackState() throws {
        let cards = [
            CaptureCard(id: UUID(), text: "First", createdAt: Date(timeIntervalSinceReferenceDate: 300), sortOrder: 30),
            CaptureCard(id: UUID(), text: "Second", createdAt: Date(timeIntervalSinceReferenceDate: 200), sortOrder: 20),
            CaptureCard(id: UUID(), text: "Third", createdAt: Date(timeIntervalSinceReferenceDate: 100), sortOrder: 10),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()

        _ = model.toggleMultiCopiedCard(cards[0])
        _ = model.toggleMultiCopiedCard(cards[1])

        model.markCardCopiedWithoutCopy(cards[0])

        XCTAssertTrue(model.isMultiSelectMode)
        XCTAssertEqual(model.stagedCopiedCardIDs, [cards[1].id])
        XCTAssertTrue(model.cards.first(where: { $0.id == cards[0].id })?.isCopied == true)
        XCTAssertTrue(model.cards.first(where: { $0.id == cards[1].id })?.isCopied == false)
        XCTAssertTrue(model.cards.first(where: { $0.id == cards[2].id })?.isCopied == false)
    }

    func testMarkCardCopiedWithoutCopyDoesNothingForAlreadyCopiedCard() throws {
        let copiedAt = Date(timeIntervalSinceReferenceDate: 400)
        let cards = [
            CaptureCard(
                id: UUID(),
                text: "Already copied",
                createdAt: Date(timeIntervalSinceReferenceDate: 300),
                lastCopiedAt: copiedAt,
                sortOrder: 30
            ),
            CaptureCard(id: UUID(), text: "Active", createdAt: Date(timeIntervalSinceReferenceDate: 200), sortOrder: 20),
        ]
        try saveCards(cards)

        let model = makeModel()
        model.reloadCards()

        model.markCardCopiedWithoutCopy(cards[0])

        XCTAssertEqual(
            model.cards.first(where: { $0.id == cards[0].id })?.lastCopiedAt,
            copiedAt
        )
        XCTAssertFalse(model.isMultiSelectMode)
        XCTAssertTrue(model.stagedCopiedCardIDs.isEmpty)
    }

    func testRefreshCardsForExternalChangesReloadsCardsWrittenByExternalService() throws {
        let model = makeModel()
        model.reloadCards()
        XCTAssertTrue(model.cards.isEmpty)

        let externalService = StackWriteService(
            fileManager: .default,
            databaseURL: databaseURL,
            attachmentBaseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
        )
        let created = try externalService.createNote(
            StackNoteCreateRequest(text: "Created from MCP")
        )

        XCTAssertTrue(model.cards.isEmpty)

        model.refreshCardsForExternalChanges()

        XCTAssertEqual(model.cards.map(\.id), [created.id])
        XCTAssertEqual(model.cards.first?.text, "Created from MCP")
    }

    private func makeModel() -> AppModel {
        AppModel(
            cardStore: CardStore(databaseURL: databaseURL),
            attachmentStore: AttachmentStore(
                baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
            ),
            recentScreenshotCoordinator: TestStackRecentScreenshotCoordinator()
        )
    }

    private func saveCards(_ cards: [CaptureCard]) throws {
        try CardStore(databaseURL: databaseURL).save(cards)
    }
}

@MainActor
private final class TestStackRecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var state: RecentScreenshotState = .idle
    var onStateChange: ((RecentScreenshotState) -> Void)?

    func start() {}
    func stop() {}
    func prepareForCaptureSession() {}
    func endCaptureSession() {}
    func refreshNow() {}
    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
    func suspendExpiration() {}
    func resumeExpiration() {}
}
