import Foundation
import GRDB
import PromptCueCore

enum PromptCueDatabaseSchema {
    static let cardsTableName = "cards"
    static let copyEventsTableName = "copy_events"
    static let projectDocumentsTableName = "project_documents"
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

        migrator.registerMigration("addSuggestedTargetJSON") { _ in
            // Migration preserved for ordering — suggestedTarget feature removed.
        }

        migrator.registerMigration("addTagsJSON") { db in
            let existingColumnNames = try db.columns(in: PromptCueDatabaseSchema.cardsTableName).map(\.name)
            guard !existingColumnNames.contains("tagsJSON") else {
                return
            }

            try db.alter(table: PromptCueDatabaseSchema.cardsTableName) { table in
                table.add(column: "tagsJSON", .text)
            }
        }

        migrator.registerMigration("normalizeCanonicalTagsJSON") { db in
            let rows = try CanonicalTagMigrationRow.fetchAll(
                db,
                sql: """
                SELECT id, tagsJSON
                FROM \(PromptCueDatabaseSchema.cardsTableName)
                WHERE tagsJSON IS NOT NULL
                """
            )

            for row in rows {
                let normalizedTagsJSON = CaptureTag.encodeJSONArray(
                    CaptureTag.decodeJSONArray(row.tagsJSON)
                )
                guard normalizedTagsJSON != row.tagsJSON else {
                    continue
                }

                if let normalizedTagsJSON {
                    try db.execute(
                        sql: "UPDATE \(PromptCueDatabaseSchema.cardsTableName) SET tagsJSON = ? WHERE id = ?",
                        arguments: [normalizedTagsJSON, row.id]
                    )
                } else {
                    try db.execute(
                        sql: "UPDATE \(PromptCueDatabaseSchema.cardsTableName) SET tagsJSON = NULL WHERE id = ?",
                        arguments: [row.id]
                    )
                }
            }
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

        migrator.registerMigration("addIsPinned") { db in
            try db.alter(table: PromptCueDatabaseSchema.cardsTableName) { table in
                table.add(column: "isPinned", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("createProjectDocuments") { db in
            try db.create(table: PromptCueDatabaseSchema.projectDocumentsTableName) { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("project", .text).notNull()
                table.column("topic", .text).notNull()
                table.column("documentType", .text).notNull()
                table.column("content", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("supersededByID", .text)
            }

            try db.execute(
                sql: """
                CREATE UNIQUE INDEX project_documents_active_key
                ON \(PromptCueDatabaseSchema.projectDocumentsTableName)(project, topic, documentType)
                WHERE supersededByID IS NULL
                """
            )

            try db.create(
                index: "project_documents_project_updated_at",
                on: PromptCueDatabaseSchema.projectDocumentsTableName,
                columns: ["project", "updatedAt"]
            )
        }

        return migrator
    }
}

private struct LegacyCardRecord: FetchableRecord, Decodable {
    let id: String
    let createdAt: Date
}

private struct CanonicalTagMigrationRow: FetchableRecord, Decodable {
    let id: String
    let tagsJSON: String?
}
