import Foundation
import GRDB

enum PromptCueDatabaseSchema {
    static let cardsTableName = "cards"
    static let workItemsTableName = "work_items"
    static let workItemSourcesTableName = "work_item_sources"
    static let copyEventsTableName = "copy_events"
}

final class PromptCueDatabase {
    let dbQueue: DatabaseQueue?
    let setupError: Error?

    init(
        fileManager: FileManager = .default,
        databaseURL: URL? = nil
    ) {
        let databaseURL = (databaseURL ?? Self.databaseURL(fileManager: fileManager)).standardizedFileURL

        do {
            try fileManager.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let queue = try DatabaseQueue(path: databaseURL.path)
            let migrator = Self.makeMigrator()
            try migrator.migrate(queue)
            dbQueue = queue
            setupError = nil
        } catch {
            dbQueue = nil
            setupError = error
            NSLog("PromptCueDatabase setup failed: %@", error.localizedDescription)
        }
    }

    static func databaseURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return baseDirectory
            .appendingPathComponent("PromptCue", isDirectory: true)
            .appendingPathComponent("PromptCue.sqlite", isDirectory: false)
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createCards") { db in
            try db.create(table: PromptCueDatabaseSchema.cardsTableName) { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("text", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("screenshotPath", .text)
                table.column("sortOrder", .double).notNull()
            }
        }

        migrator.registerMigration("addLastCopiedAt") { db in
            try db.alter(table: PromptCueDatabaseSchema.cardsTableName) { table in
                table.add(column: "lastCopiedAt", .datetime)
            }
        }

        migrator.registerMigration("addSortOrder") { db in
            let existingColumnNames = try db.columns(in: PromptCueDatabaseSchema.cardsTableName).map(\.name)
            guard !existingColumnNames.contains("sortOrder") else {
                return
            }

            try db.alter(table: PromptCueDatabaseSchema.cardsTableName) { table in
                table.add(column: "sortOrder", .double).notNull().defaults(to: 0)
            }

            let legacyCards = try LegacyCardRecord.fetchAll(
                db,
                sql: """
                SELECT id, createdAt
                FROM \(PromptCueDatabaseSchema.cardsTableName)
                ORDER BY createdAt DESC
                """
            )
            for (index, card) in legacyCards.enumerated() {
                let order = card.createdAt.timeIntervalSinceReferenceDate - (Double(index) * 0.000001)
                try db.execute(
                    sql: "UPDATE \(PromptCueDatabaseSchema.cardsTableName) SET sortOrder = ? WHERE id = ?",
                    arguments: [order, card.id]
                )
            }
        }

        migrator.registerMigration("addSuggestedTargetJSON") { db in
            let existingColumnNames = try db.columns(in: PromptCueDatabaseSchema.cardsTableName).map(\.name)
            guard !existingColumnNames.contains("suggestedTargetJSON") else {
                return
            }

            try db.alter(table: PromptCueDatabaseSchema.cardsTableName) { table in
                table.add(column: "suggestedTargetJSON", .text)
            }
        }

        migrator.registerMigration("createWorkItems") { db in
            try db.create(table: PromptCueDatabaseSchema.workItemsTableName) { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("title", .text).notNull()
                table.column("summary", .text)
                table.column("repoName", .text)
                table.column("branchName", .text)
                table.column("status", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("createdBy", .text).notNull()
                table.column("difficultyHint", .text)
                table.column("sourceNoteCount", .integer).notNull()
            }

            try db.create(
                index: "work_items_status_updated_at",
                on: PromptCueDatabaseSchema.workItemsTableName,
                columns: ["status", "updatedAt"]
            )
            try db.create(
                index: "work_items_repo_name",
                on: PromptCueDatabaseSchema.workItemsTableName,
                columns: ["repoName"]
            )
        }

        migrator.registerMigration("createWorkItemSources") { db in
            try db.create(table: PromptCueDatabaseSchema.workItemSourcesTableName) { table in
                table.column("workItemID", .text)
                    .notNull()
                    .references(PromptCueDatabaseSchema.workItemsTableName, onDelete: .cascade)
                table.column("noteID", .text).notNull()
                table.column("relationType", .text).notNull()
            }

            try db.create(
                index: "work_item_sources_work_item_id",
                on: PromptCueDatabaseSchema.workItemSourcesTableName,
                columns: ["workItemID"]
            )
            try db.create(
                index: "work_item_sources_note_id",
                on: PromptCueDatabaseSchema.workItemSourcesTableName,
                columns: ["noteID"]
            )
        }

        migrator.registerMigration("createCopyEvents") { db in
            try db.create(table: PromptCueDatabaseSchema.copyEventsTableName) { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("noteID", .text).notNull()
                table.column("sessionID", .text)
                table.column("copiedAt", .datetime).notNull()
                table.column("copiedVia", .text).notNull()
                table.column("copiedBy", .text).notNull()
            }

            try db.create(
                index: "copy_events_note_id_copied_at",
                on: PromptCueDatabaseSchema.copyEventsTableName,
                columns: ["noteID", "copiedAt"]
            )
        }

        return migrator
    }
}

private struct LegacyCardRecord: FetchableRecord, Decodable {
    let id: String
    let createdAt: Date
}
