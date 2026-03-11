import Foundation
import XCTest
@testable import Prompt_Cue
import PromptCueCore

@MainActor
final class StorageServicesTests: XCTestCase {
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

    func testAttachmentStoreImportsAndPrunesManagedFiles() throws {
        let attachmentsURL = tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
        let store = AttachmentStore(baseDirectoryURL: attachmentsURL)

        let sourceURL = tempDirectoryURL.appendingPathComponent("shot.png")
        try Data("png".utf8).write(to: sourceURL)

        let keptURL = try store.importScreenshot(from: sourceURL, ownerID: UUID())
        let orphanURL = try store.importScreenshot(from: sourceURL, ownerID: UUID())

        XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanURL.path))
        XCTAssertTrue(store.isManagedFile(keptURL))

        try store.pruneUnreferencedManagedFiles(referencedFileURLs: [keptURL])

        XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
    }

    func testCardStoreRoundTripsCopiedMetadata() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let store = CardStore(databaseURL: databaseURL)
        let copiedAt = Date().addingTimeInterval(-30)
        let expectedCard = CaptureCard(
            id: UUID(),
            text: "Round trip",
            createdAt: Date(),
            screenshotPath: "/tmp/screenshot.png",
            lastCopiedAt: copiedAt,
            sortOrder: 42
        )

        try store.save([expectedCard])
        let loadedCards = try store.load()

        XCTAssertEqual(loadedCards.count, 1)
        XCTAssertEqual(loadedCards.first?.id, expectedCard.id)
        XCTAssertEqual(loadedCards.first?.text, expectedCard.text)
        XCTAssertEqual(loadedCards.first?.screenshotPath, expectedCard.screenshotPath)
        XCTAssertEqual(loadedCards.first?.sortOrder, expectedCard.sortOrder)
        let loadedCopiedAt = try XCTUnwrap(loadedCards.first?.lastCopiedAt)
        XCTAssertLessThan(abs(loadedCopiedAt.timeIntervalSince(copiedAt)), 1)
    }

    func testCardStoreRoundTripsSuggestedTargetMetadata() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let store = CardStore(databaseURL: databaseURL)
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let suggestedTarget = CaptureSuggestedTarget(
            appName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            windowTitle: "PromptCue.swift",
            sessionIdentifier: "tab-7",
            currentWorkingDirectory: "/Users/ilwon/dev/PromptCue/App",
            repositoryRoot: "/Users/ilwon/dev/PromptCue",
            repositoryName: "PromptCue",
            branch: "feature/ide-targets",
            capturedAt: capturedAt,
            confidence: .low
        )
        let expectedCard = CaptureCard(
            id: UUID(),
            text: "Round trip suggested target",
            suggestedTarget: suggestedTarget,
            createdAt: Date(),
            sortOrder: 42
        )

        try store.save([expectedCard])
        let loadedCards = try store.load()

        XCTAssertEqual(loadedCards.count, 1)
        XCTAssertEqual(loadedCards.first?.id, expectedCard.id)
        XCTAssertEqual(loadedCards.first?.suggestedTarget, suggestedTarget)
    }

    func testCardStoreBatchUpsertUpdatesExistingCardAndInsertsNewCard() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let store = CardStore(databaseURL: databaseURL)
        let original = CaptureCard(
            id: UUID(),
            text: "Original",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            sortOrder: 10
        )
        let inserted = CaptureCard(
            id: UUID(),
            text: "Inserted",
            createdAt: Date(timeIntervalSinceReferenceDate: 200),
            sortOrder: 20
        )
        let updatedOriginal = CaptureCard(
            id: original.id,
            text: "Updated",
            createdAt: original.createdAt,
            screenshotPath: "/tmp/updated.png",
            lastCopiedAt: Date(timeIntervalSinceReferenceDate: 400),
            sortOrder: original.sortOrder
        )

        try store.replaceAll([original])
        try store.upsert([updatedOriginal, inserted])

        let loadedCards = try store.load()

        XCTAssertEqual(loadedCards.map(\.id), [inserted.id, original.id])
        XCTAssertEqual(loadedCards.first?.text, inserted.text)
        XCTAssertEqual(loadedCards.last?.text, updatedOriginal.text)
        XCTAssertEqual(loadedCards.last?.screenshotPath, updatedOriginal.screenshotPath)
        XCTAssertEqual(loadedCards.last?.lastCopiedAt, updatedOriginal.lastCopiedAt)
    }

    func testCardStoreBatchDeleteRemovesRequestedCardsOnly() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let store = CardStore(databaseURL: databaseURL)
        let first = CaptureCard(
            id: UUID(),
            text: "First",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            sortOrder: 10
        )
        let second = CaptureCard(
            id: UUID(),
            text: "Second",
            createdAt: Date(timeIntervalSinceReferenceDate: 200),
            sortOrder: 20
        )
        let third = CaptureCard(
            id: UUID(),
            text: "Third",
            createdAt: Date(timeIntervalSinceReferenceDate: 300),
            sortOrder: 30
        )

        try store.replaceAll([first, second, third])
        try store.delete(ids: [first.id, third.id])

        let loadedCards = try store.load()

        XCTAssertEqual(loadedCards.map(\.id), [second.id])
        XCTAssertEqual(loadedCards.first?.text, second.text)
    }

    func testWorkItemStoreRoundTripsItemsSourcesAndCopyEvents() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let database = PromptCueDatabase(databaseURL: databaseURL)
        let store = WorkItemStore(database: database)
        let workItem = WorkItem(
            id: UUID(),
            title: "Stabilize MCP lane",
            summary: "Keep raw notes and derived work items separate",
            repoName: "PromptCue",
            branchName: "backtick-mcp",
            status: .inProgress,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 120),
            createdBy: .mcpAI,
            difficultyHint: .large,
            sourceNoteCount: 2
        )
        let firstNoteID = UUID()
        let secondNoteID = UUID()
        let sources = [
            WorkItemSource(workItemID: UUID(), noteID: firstNoteID, relationType: .primary),
            WorkItemSource(workItemID: UUID(), noteID: secondNoteID, relationType: .supporting),
        ]
        let copyEvent = CopyEvent(
            id: UUID(),
            noteID: firstNoteID,
            sessionID: "run-17",
            copiedAt: Date(timeIntervalSinceReferenceDate: 140),
            copiedVia: .agentRun,
            copiedBy: .mcp
        )

        try store.upsert(workItem)
        try store.replaceSources(for: workItem.id, with: sources)
        try store.recordCopyEvents([copyEvent])

        let loadedWorkItems = try store.loadWorkItems()
        let loadedSources = try store.loadSources(for: workItem.id)
        let loadedCopyEvents = try store.loadCopyEvents(for: firstNoteID)

        XCTAssertEqual(loadedWorkItems, [workItem])
        XCTAssertEqual(
            loadedSources,
            [
                WorkItemSource(workItemID: workItem.id, noteID: firstNoteID, relationType: .primary),
                WorkItemSource(workItemID: workItem.id, noteID: secondNoteID, relationType: .supporting),
            ]
        )
        XCTAssertEqual(loadedCopyEvents, [copyEvent])
    }

    func testWorkItemStoreSourceReplacementDoesNotDuplicateMappings() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let store = WorkItemStore(databaseURL: databaseURL)
        let workItemID = UUID()
        let firstNoteID = UUID()
        let secondNoteID = UUID()
        let workItem = WorkItem(
            id: workItemID,
            title: "Replace mappings",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            createdBy: .user,
            sourceNoteCount: 1
        )

        try store.upsert(workItem)

        try store.replaceSources(
            for: workItemID,
            with: [
                WorkItemSource(workItemID: workItemID, noteID: firstNoteID, relationType: .primary),
                WorkItemSource(workItemID: workItemID, noteID: firstNoteID, relationType: .duplicate),
            ]
        )
        try store.replaceSources(
            for: workItemID,
            with: [
                WorkItemSource(workItemID: workItemID, noteID: secondNoteID, relationType: .supporting),
            ]
        )

        let loadedSources = try store.loadSources(for: workItemID)

        XCTAssertEqual(
            loadedSources,
            [
                WorkItemSource(workItemID: workItemID, noteID: secondNoteID, relationType: .supporting),
            ]
        )
    }

    func testWorkItemStoreCoexistsWithCardStoreOnSharedDatabase() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let database = PromptCueDatabase(databaseURL: databaseURL)
        let cardStore = CardStore(database: database)
        let workItemStore = WorkItemStore(database: database)
        let card = CaptureCard(
            id: UUID(),
            text: "Raw note stays intact",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            sortOrder: 10
        )
        let workItem = WorkItem(
            id: UUID(),
            title: "Derived execution card",
            createdAt: Date(timeIntervalSinceReferenceDate: 110),
            createdBy: .user,
            sourceNoteCount: 1
        )

        try cardStore.save([card])
        try workItemStore.upsert(workItem)
        try workItemStore.replaceSources(
            for: workItem.id,
            with: [
                WorkItemSource(workItemID: workItem.id, noteID: card.id, relationType: .primary),
            ]
        )

        let loadedCards = try cardStore.load()
        let loadedWorkItems = try workItemStore.loadWorkItems()
        let loadedSources = try workItemStore.loadSources(for: workItem.id)

        XCTAssertEqual(loadedCards, [card])
        XCTAssertEqual(loadedWorkItems, [workItem])
        XCTAssertEqual(
            loadedSources,
            [
                WorkItemSource(workItemID: workItem.id, noteID: card.id, relationType: .primary),
            ]
        )
    }
}
