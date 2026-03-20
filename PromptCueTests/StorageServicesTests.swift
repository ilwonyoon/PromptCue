import Foundation
import GRDB
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

    func testPromptCueDatabaseMigratesLegacyCardSchemaAndPreservesRows() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let legacyCardID = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 250)
        let copiedAt = Date(timeIntervalSinceReferenceDate: 300)
        let legacyQueue = try DatabaseQueue(path: databaseURL.path)

        try legacyQueue.write { db in
            try db.create(table: "grdb_migrations") { table in
                table.column("identifier", .text).notNull().primaryKey()
            }
            try db.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?), (?)",
                arguments: ["createCards", "addLastCopiedAt"]
            )
            try db.create(table: "cards") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("text", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("screenshotPath", .text)
                table.column("lastCopiedAt", .datetime)
            }
            try db.execute(
                sql: """
                INSERT INTO cards (id, text, createdAt, screenshotPath, lastCopiedAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    legacyCardID.uuidString,
                    "Legacy note",
                    createdAt,
                    "/tmp/legacy.png",
                    copiedAt,
                ]
            )
        }

        let database = PromptCueDatabase(databaseURL: databaseURL)
        let store = CardStore(database: database)

        let loadedCards = try store.load()
        let cardColumns = try XCTUnwrap(database.dbQueue).read { db in
            try db.columns(in: PromptCueDatabaseSchema.cardsTableName).map(\.name)
        }

        XCTAssertEqual(loadedCards.count, 1)
        XCTAssertEqual(loadedCards.first?.id, legacyCardID)
        XCTAssertEqual(loadedCards.first?.text, "Legacy note")
        XCTAssertEqual(loadedCards.first?.screenshotPath, "/tmp/legacy.png")
        XCTAssertEqual(loadedCards.first?.lastCopiedAt, copiedAt)
        XCTAssertEqual(loadedCards.first?.sortOrder, createdAt.timeIntervalSinceReferenceDate)
        XCTAssertTrue(cardColumns.contains("sortOrder"))
        XCTAssertTrue(cardColumns.contains("tagsJSON"))
    }

    func testPromptCueDatabaseMigrationCanonicalizesPollutedTagsJSON() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let legacyCardID = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 250)
        let legacyQueue = try DatabaseQueue(path: databaseURL.path)

        try legacyQueue.write { db in
            try db.create(table: "grdb_migrations") { table in
                table.column("identifier", .text).notNull().primaryKey()
            }
            try db.execute(
                sql: """
                INSERT INTO grdb_migrations (identifier) VALUES (?), (?), (?), (?), (?)
                """,
                arguments: [
                    "createCards",
                    "addLastCopiedAt",
                    "addSortOrder",
                    "addSuggestedTargetJSON",
                    "addTagsJSON",
                ]
            )
            try db.create(table: "cards") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("text", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("screenshotPath", .text)
                table.column("lastCopiedAt", .datetime)
                table.column("sortOrder", .double).notNull()
                table.column("suggestedTargetJSON", .text)
                table.column("tagsJSON", .text)
            }
            try db.execute(
                sql: """
                INSERT INTO cards (id, text, createdAt, sortOrder, tagsJSON)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    legacyCardID.uuidString,
                    "Legacy polluted tags",
                    createdAt,
                    createdAt.timeIntervalSinceReferenceDate,
                    #"["bug","ㅠㅕbug","mcp"]"#,
                ]
            )
        }

        let database = PromptCueDatabase(databaseURL: databaseURL)
        let store = CardStore(database: database)

        let loadedCards = try store.load()
        let normalizedTagsJSON = try XCTUnwrap(database.dbQueue).read { db in
            try String?.fetchOne(
                db,
                sql: "SELECT tagsJSON FROM cards WHERE id = ?",
                arguments: [legacyCardID.uuidString]
            )
        }

        XCTAssertEqual(loadedCards.count, 1)
        XCTAssertEqual(loadedCards.first?.tags.map(\.name), ["bug", "mcp"])
        XCTAssertEqual(normalizedTagsJSON, #"["bug","mcp"]"#)
    }

    func testCardStoreUpsertPersistsEmptyTagsJSONArrayWhenLegacySchemaRequiresNonNullTags() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let cardID = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 250)
        let legacyQueue = try DatabaseQueue(path: databaseURL.path)

        try legacyQueue.write { db in
            try db.create(table: "grdb_migrations") { table in
                table.column("identifier", .text).notNull().primaryKey()
            }
            try db.execute(
                sql: """
                INSERT INTO grdb_migrations (identifier) VALUES (?), (?), (?), (?), (?), (?), (?), (?)
                """,
                arguments: [
                    "createCards",
                    "addLastCopiedAt",
                    "addSortOrder",
                    "addSuggestedTargetJSON",
                    "addTagsJSON",
                    "normalizeCanonicalTagsJSON",
                    "createCopyEvents",
                    "addIsPinned",
                ]
            )
            try db.create(table: "cards") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("text", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("screenshotPath", .text)
                table.column("lastCopiedAt", .datetime)
                table.column("sortOrder", .double).notNull()
                table.column("suggestedTargetJSON", .text)
                table.column("tagsJSON", .text).notNull().defaults(to: "[]")
                table.column("isPinned", .boolean).notNull().defaults(to: false)
            }
        }

        let store = CardStore(databaseURL: databaseURL)
        let card = CaptureCard(
            id: cardID,
            text: "Plain capture",
            createdAt: createdAt,
            sortOrder: createdAt.timeIntervalSinceReferenceDate
        )

        try store.upsert(card)

        let database = PromptCueDatabase(databaseURL: databaseURL)
        let persistedTagsJSON = try XCTUnwrap(database.dbQueue).read { db in
            try String.fetchOne(
                db,
                sql: "SELECT tagsJSON FROM cards WHERE id = ?",
                arguments: [cardID.uuidString]
            )
        }
        let loadedCards = try store.load()

        XCTAssertEqual(persistedTagsJSON, #"[]"#)
        XCTAssertEqual(loadedCards, [card])
    }

    func testCardStoreAndCopyEventStoreShareDatabaseWhenBootstrappedSeparately() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let cardStore = CardStore(databaseURL: databaseURL)
        let copyEventStore = CopyEventStore(databaseURL: databaseURL)
        let card = CaptureCard(
            id: UUID(),
            text: "Raw note stays intact",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            sortOrder: 10
        )
        let copyEvent = CopyEvent(
            id: UUID(),
            noteID: card.id,
            sessionID: "run-17",
            copiedAt: Date(timeIntervalSinceReferenceDate: 140),
            copiedVia: .agentRun,
            copiedBy: .mcp
        )

        try cardStore.save([card])
        try copyEventStore.recordCopyEvents([copyEvent])

        let loadedCards = try cardStore.load()
        let loadedCopyEvents = try copyEventStore.loadCopyEvents(for: card.id)

        XCTAssertEqual(loadedCards, [card])
        XCTAssertEqual(loadedCopyEvents, [copyEvent])
    }

    func testCopyEventStoreRoundTripsEvents() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let database = PromptCueDatabase(databaseURL: databaseURL)
        let store = CopyEventStore(database: database)
        let firstNoteID = UUID()
        let secondNoteID = UUID()
        let firstEvent = CopyEvent(
            id: UUID(),
            noteID: firstNoteID,
            sessionID: "run-17",
            copiedAt: Date(timeIntervalSinceReferenceDate: 140),
            copiedVia: .agentRun,
            copiedBy: .mcp
        )
        let secondEvent = CopyEvent(
            id: UUID(),
            noteID: secondNoteID,
            copiedAt: Date(timeIntervalSinceReferenceDate: 120),
            copiedVia: .clipboard,
            copiedBy: .user
        )

        try store.recordCopyEvents([secondEvent, firstEvent])

        let loadedForFirstNote = try store.loadCopyEvents(for: firstNoteID)
        let loadedAllEvents = try store.loadCopyEvents()

        XCTAssertEqual(loadedForFirstNote, [firstEvent])
        XCTAssertEqual(loadedAllEvents, [firstEvent, secondEvent])
    }

    func testCopyEventStoreCoexistsWithCardStoreOnSharedDatabase() throws {
        let databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        let database = PromptCueDatabase(databaseURL: databaseURL)
        let cardStore = CardStore(database: database)
        let copyEventStore = CopyEventStore(database: database)
        let card = CaptureCard(
            id: UUID(),
            text: "Raw note stays intact",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            sortOrder: 10
        )
        let copyEvent = CopyEvent(
            id: UUID(),
            noteID: card.id,
            copiedAt: Date(timeIntervalSinceReferenceDate: 110),
            copiedVia: .clipboard,
            copiedBy: .user
        )

        try cardStore.save([card])
        try copyEventStore.recordCopyEvents([copyEvent])

        let loadedCards = try cardStore.load()
        let loadedCopyEvents = try copyEventStore.loadCopyEvents(for: card.id)

        XCTAssertEqual(loadedCards, [card])
        XCTAssertEqual(loadedCopyEvents, [copyEvent])
    }
}
