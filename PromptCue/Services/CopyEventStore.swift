import Foundation
import GRDB
import PromptCueCore

enum CopyEventStoreError: Error {
    case unavailable(underlying: Error?)
    case loadFailed(Error)
    case saveFailed(Error)
}

@MainActor
final class CopyEventStore {
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

    func loadCopyEvents(for noteID: UUID? = nil) throws -> [CopyEvent] {
        guard let dbQueue = database.dbQueue else {
            throw CopyEventStoreError.unavailable(underlying: database.setupError)
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
            NSLog("CopyEventStore loadCopyEvents failed: %@", error.localizedDescription)
            throw CopyEventStoreError.loadFailed(error)
        }
    }

    func recordCopyEvents(_ copyEvents: [CopyEvent]) throws {
        guard let dbQueue = database.dbQueue else {
            throw CopyEventStoreError.unavailable(underlying: database.setupError)
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
            NSLog("CopyEventStore recordCopyEvents failed: %@", error.localizedDescription)
            throw CopyEventStoreError.saveFailed(error)
        }
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
            id: UUID(uuidString: id) ?? {
                assertionFailure("CopyEventStore: corrupt UUID '\(id)'")
                return UUID()
            }(),
            noteID: UUID(uuidString: noteID) ?? {
                assertionFailure("CopyEventStore: corrupt noteID '\(noteID)'")
                return UUID()
            }(),
            sessionID: sessionID,
            copiedAt: copiedAt,
            copiedVia: CopyEventVia(rawValue: copiedVia) ?? .clipboard,
            copiedBy: CopyEventActor(rawValue: copiedBy) ?? .user
        )
    }
}
