import Foundation
import GRDB
import PromptCueCore

enum WorkItemStoreError: Error {
    case unavailable(underlying: Error?)
    case loadFailed(Error)
    case saveFailed(Error)
}

@MainActor
final class WorkItemStore {
    private let database: PromptCueDatabase

    init(database: PromptCueDatabase) {
        self.database = database
    }

    convenience init(
        fileManager: FileManager = .default,
        databaseURL: URL? = nil
    ) {
        self.init(database: PromptCueDatabase(fileManager: fileManager, databaseURL: databaseURL))
    }

    func loadWorkItems() throws -> [WorkItem] {
        guard let dbQueue = database.dbQueue else {
            throw WorkItemStoreError.unavailable(underlying: database.setupError)
        }

        do {
            return try dbQueue.read { db in
                try WorkItemRecord.fetchAll(
                    db,
                    sql: """
                    SELECT *
                    FROM \(PromptCueDatabaseSchema.workItemsTableName)
                    ORDER BY updatedAt DESC, createdAt DESC
                    """
                ).map(\.workItem)
            }
        } catch {
            NSLog("WorkItemStore loadWorkItems failed: %@", error.localizedDescription)
            throw WorkItemStoreError.loadFailed(error)
        }
    }

    func upsert(_ workItem: WorkItem) throws {
        try upsert([workItem])
    }

    func upsert(_ workItems: [WorkItem]) throws {
        guard let dbQueue = database.dbQueue else {
            throw WorkItemStoreError.unavailable(underlying: database.setupError)
        }

        guard !workItems.isEmpty else {
            return
        }

        do {
            try dbQueue.write { db in
                for workItem in workItems {
                    try WorkItemRecord(workItem: workItem).upsert(db)
                }
            }
        } catch {
            NSLog("WorkItemStore upsert failed: %@", error.localizedDescription)
            throw WorkItemStoreError.saveFailed(error)
        }
    }

    func deleteWorkItems(ids: [UUID]) throws {
        guard let dbQueue = database.dbQueue else {
            throw WorkItemStoreError.unavailable(underlying: database.setupError)
        }

        guard !ids.isEmpty else {
            return
        }

        do {
            try dbQueue.write { db in
                let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
                try db.execute(
                    sql: "DELETE FROM \(PromptCueDatabaseSchema.workItemsTableName) WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(ids.map(\.uuidString))
                )
            }
        } catch {
            NSLog("WorkItemStore deleteWorkItems failed: %@", error.localizedDescription)
            throw WorkItemStoreError.saveFailed(error)
        }
    }

    func loadSources(for workItemID: UUID? = nil) throws -> [WorkItemSource] {
        guard let dbQueue = database.dbQueue else {
            throw WorkItemStoreError.unavailable(underlying: database.setupError)
        }

        do {
            return try dbQueue.read { db in
                if let workItemID {
                    return try WorkItemSourceRecord.fetchAll(
                        db,
                        sql: """
                        SELECT *
                        FROM \(PromptCueDatabaseSchema.workItemSourcesTableName)
                        WHERE workItemID = ?
                        ORDER BY rowid ASC
                        """,
                        arguments: [workItemID.uuidString]
                    ).map(\.workItemSource)
                }

                return try WorkItemSourceRecord.fetchAll(
                    db,
                    sql: """
                    SELECT *
                    FROM \(PromptCueDatabaseSchema.workItemSourcesTableName)
                    ORDER BY rowid ASC
                    """
                ).map(\.workItemSource)
            }
        } catch {
            NSLog("WorkItemStore loadSources failed: %@", error.localizedDescription)
            throw WorkItemStoreError.loadFailed(error)
        }
    }

    func replaceSources(for workItemID: UUID, with sources: [WorkItemSource]) throws {
        guard let dbQueue = database.dbQueue else {
            throw WorkItemStoreError.unavailable(underlying: database.setupError)
        }

        let normalizedSources = normalizedSources(for: workItemID, sources: sources)

        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "DELETE FROM \(PromptCueDatabaseSchema.workItemSourcesTableName) WHERE workItemID = ?",
                    arguments: [workItemID.uuidString]
                )

                for source in normalizedSources {
                    try WorkItemSourceRecord(workItemSource: source).insert(db)
                }
            }
        } catch {
            NSLog("WorkItemStore replaceSources failed: %@", error.localizedDescription)
            throw WorkItemStoreError.saveFailed(error)
        }
    }

    func loadCopyEvents(for noteID: UUID? = nil) throws -> [CopyEvent] {
        guard let dbQueue = database.dbQueue else {
            throw WorkItemStoreError.unavailable(underlying: database.setupError)
        }

        do {
            return try dbQueue.read { db in
                if let noteID {
                    return try CopyEventRecord.fetchAll(
                        db,
                        sql: """
                        SELECT *
                        FROM \(PromptCueDatabaseSchema.copyEventsTableName)
                        WHERE noteID = ?
                        ORDER BY copiedAt DESC
                        """,
                        arguments: [noteID.uuidString]
                    ).map(\.copyEvent)
                }

                return try CopyEventRecord.fetchAll(
                    db,
                    sql: """
                    SELECT *
                    FROM \(PromptCueDatabaseSchema.copyEventsTableName)
                    ORDER BY copiedAt DESC
                    """
                ).map(\.copyEvent)
            }
        } catch {
            NSLog("WorkItemStore loadCopyEvents failed: %@", error.localizedDescription)
            throw WorkItemStoreError.loadFailed(error)
        }
    }

    func recordCopyEvents(_ copyEvents: [CopyEvent]) throws {
        guard let dbQueue = database.dbQueue else {
            throw WorkItemStoreError.unavailable(underlying: database.setupError)
        }

        guard !copyEvents.isEmpty else {
            return
        }

        do {
            try dbQueue.write { db in
                for copyEvent in copyEvents {
                    try CopyEventRecord(copyEvent: copyEvent).upsert(db)
                }
            }
        } catch {
            NSLog("WorkItemStore recordCopyEvents failed: %@", error.localizedDescription)
            throw WorkItemStoreError.saveFailed(error)
        }
    }

    private func normalizedSources(for workItemID: UUID, sources: [WorkItemSource]) -> [WorkItemSource] {
        var seenNoteIDs = Set<UUID>()
        var normalizedSources: [WorkItemSource] = []

        for source in sources {
            let normalized = WorkItemSource(
                workItemID: workItemID,
                noteID: source.noteID,
                relationType: source.relationType
            )

            guard seenNoteIDs.insert(normalized.noteID).inserted else {
                continue
            }

            normalizedSources.append(normalized)
        }

        return normalizedSources
    }
}

private struct WorkItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = PromptCueDatabaseSchema.workItemsTableName

    let id: String
    let title: String
    let summary: String?
    let repoName: String?
    let branchName: String?
    let status: String
    let createdAt: Date
    let updatedAt: Date
    let createdBy: String
    let difficultyHint: String?
    let sourceNoteCount: Int

    init(workItem: WorkItem) {
        id = workItem.id.uuidString
        title = workItem.title
        summary = workItem.summary
        repoName = workItem.repoName
        branchName = workItem.branchName
        status = workItem.status.rawValue
        createdAt = workItem.createdAt
        updatedAt = workItem.updatedAt
        createdBy = workItem.createdBy.rawValue
        difficultyHint = workItem.difficultyHint?.rawValue
        sourceNoteCount = workItem.sourceNoteCount
    }

    var workItem: WorkItem {
        WorkItem(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            summary: summary,
            repoName: repoName,
            branchName: branchName,
            status: WorkItemStatus(rawValue: status) ?? .open,
            createdAt: createdAt,
            updatedAt: updatedAt,
            createdBy: WorkItemCreatedBy(rawValue: createdBy) ?? .user,
            difficultyHint: difficultyHint.flatMap(WorkItemDifficultyHint.init(rawValue:)),
            sourceNoteCount: sourceNoteCount
        )
    }
}

private struct WorkItemSourceRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = PromptCueDatabaseSchema.workItemSourcesTableName

    let workItemID: String
    let noteID: String
    let relationType: String

    init(workItemSource: WorkItemSource) {
        workItemID = workItemSource.workItemID.uuidString
        noteID = workItemSource.noteID.uuidString
        relationType = workItemSource.relationType.rawValue
    }

    var workItemSource: WorkItemSource {
        WorkItemSource(
            workItemID: UUID(uuidString: workItemID) ?? UUID(),
            noteID: UUID(uuidString: noteID) ?? UUID(),
            relationType: WorkItemSourceRelationType(rawValue: relationType) ?? .supporting
        )
    }
}

private struct CopyEventRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = PromptCueDatabaseSchema.copyEventsTableName

    let id: String
    let noteID: String
    let sessionID: String?
    let copiedAt: Date
    let copiedVia: String
    let copiedBy: String

    init(copyEvent: CopyEvent) {
        id = copyEvent.id.uuidString
        noteID = copyEvent.noteID.uuidString
        sessionID = copyEvent.sessionID
        copiedAt = copyEvent.copiedAt
        copiedVia = copyEvent.copiedVia.rawValue
        copiedBy = copyEvent.copiedBy.rawValue
    }

    var copyEvent: CopyEvent {
        CopyEvent(
            id: UUID(uuidString: id) ?? UUID(),
            noteID: UUID(uuidString: noteID) ?? UUID(),
            sessionID: sessionID,
            copiedAt: copiedAt,
            copiedVia: CopyEventVia(rawValue: copiedVia) ?? .clipboard,
            copiedBy: CopyEventActor(rawValue: copiedBy) ?? .user
        )
    }
}
