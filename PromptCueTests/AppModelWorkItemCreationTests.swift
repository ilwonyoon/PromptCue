import Foundation
import XCTest
@testable import Prompt_Cue
import PromptCueCore

@MainActor
final class AppModelWorkItemCreationTests: XCTestCase {
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

    func testCreateWorkItemFromSelectionPersistsDerivedItemAndLeavesRawCardsActive() throws {
        let target = CaptureSuggestedTarget(
            appName: "Cursor",
            bundleIdentifier: "cursor",
            repositoryRoot: "/Users/me/PromptCue",
            repositoryName: "PromptCue",
            branch: "backtick-mcp",
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let cards = [
            CaptureCard(
                id: UUID(),
                text: "Stabilize retry logic",
                suggestedTarget: target,
                createdAt: Date(timeIntervalSinceReferenceDate: 300),
                sortOrder: 30
            ),
            CaptureCard(
                id: UUID(),
                text: "Check settings sync edge case",
                suggestedTarget: target,
                createdAt: Date(timeIntervalSinceReferenceDate: 200),
                sortOrder: 20
            ),
        ]
        try CardStore(databaseURL: databaseURL).save(cards)

        let model = makeModel()
        model.reloadCards()
        model.selectedCardIDs = Set(cards.map(\.id))

        let workItem = try XCTUnwrap(
            model.createWorkItemFromSelection(now: Date(timeIntervalSinceReferenceDate: 500))
        )

        XCTAssertTrue(model.selectedCardIDs.isEmpty)
        XCTAssertTrue(model.cards.allSatisfy { !$0.isCopied })
        XCTAssertEqual(workItem.status, .open)
        XCTAssertEqual(workItem.createdBy, .user)
        XCTAssertEqual(workItem.sourceNoteCount, 2)

        let loadedWorkItems = try WorkItemStore(databaseURL: databaseURL).loadWorkItems()
        let loadedSources = try WorkItemStore(databaseURL: databaseURL).loadSources(for: workItem.id)

        XCTAssertEqual(loadedWorkItems, [workItem])
        XCTAssertEqual(
            loadedSources,
            [
                WorkItemSource(workItemID: workItem.id, noteID: cards[0].id, relationType: .primary),
                WorkItemSource(workItemID: workItem.id, noteID: cards[1].id, relationType: .supporting),
            ]
        )
    }

    func testCreateWorkItemFromSelectionReturnsNilWithoutSelection() {
        let model = makeModel()
        model.reloadCards()

        XCTAssertNil(model.createWorkItemFromSelection())
    }

    private func makeModel() -> AppModel {
        let database = PromptCueDatabase(databaseURL: databaseURL)
        return AppModel(
            cardStore: CardStore(database: database),
            workItemStore: WorkItemStore(database: database),
            attachmentStore: AttachmentStore(
                baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
            ),
            recentScreenshotCoordinator: TestWorkItemRecentScreenshotCoordinator()
        )
    }
}

@MainActor
private final class TestWorkItemRecentScreenshotCoordinator: RecentScreenshotCoordinating {
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
