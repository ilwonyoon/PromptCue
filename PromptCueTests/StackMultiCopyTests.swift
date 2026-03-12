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
    func refreshNow() {}
    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
    func suspendExpiration() {}
    func resumeExpiration() {}
}
