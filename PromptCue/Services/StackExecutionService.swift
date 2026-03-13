import Foundation
import GRDB
import PromptCueCore

enum StackExecutionServiceError: Error {
    case unavailable(underlying: Error?)
    case saveFailed(Error)
}

struct StackExecutionResult: Equatable {
    let notes: [CaptureCard]
    let copyEvents: [CopyEvent]
}

@MainActor
final class StackExecutionService {
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

    func markExecuted(
        noteIDs: [UUID],
        sessionID: String? = nil,
        copiedAt: Date = Date(),
        copiedVia: CopyEventVia = .agentRun,
        copiedBy: CopyEventActor = .mcp
    ) throws -> StackExecutionResult {
        guard let dbQueue = database.dbQueue else {
            throw StackExecutionServiceError.unavailable(underlying: database.setupError)
        }

        let uniqueOrderedIDs = noteIDs.reduce(into: [UUID]()) { partialResult, id in
            if partialResult.contains(id) == false {
                partialResult.append(id)
            }
        }
        guard !uniqueOrderedIDs.isEmpty else {
            return StackExecutionResult(notes: [], copyEvents: [])
        }

        let copiedTimestamps = Dictionary(
            uniqueKeysWithValues: uniqueOrderedIDs.enumerated().map { offset, id in
                (
                    id,
                    copiedAt.addingTimeInterval(
                        TimeInterval(uniqueOrderedIDs.count - offset) * 0.001
                    )
                )
            }
        )

        do {
            return try dbQueue.write { db in
                let recordsByID = try Self.loadCardRecords(
                    ids: uniqueOrderedIDs,
                    db: db
                )

                var updatedNotes: [CaptureCard] = []
                var copyEvents: [CopyEvent] = []

                for noteID in uniqueOrderedIDs {
                    guard let record = recordsByID[noteID.uuidString] else {
                        continue
                    }

                    let timestamp = copiedTimestamps[noteID] ?? copiedAt
                    let updatedNote = record.captureCard.markCopied(at: timestamp)
                    let copyEvent = CopyEvent(
                        noteID: noteID,
                        sessionID: sessionID,
                        copiedAt: timestamp,
                        copiedVia: copiedVia,
                        copiedBy: copiedBy
                    )

                    try db.execute(
                        sql: """
                        UPDATE \(PromptCueDatabaseSchema.cardsTableName)
                        SET lastCopiedAt = ?
                        WHERE id = ?
                        """,
                        arguments: [timestamp, noteID.uuidString]
                    )
                    try db.execute(
                        sql: """
                        INSERT INTO \(PromptCueDatabaseSchema.copyEventsTableName)
                        (id, noteID, sessionID, copiedAt, copiedVia, copiedBy)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            copyEvent.id.uuidString,
                            copyEvent.noteID.uuidString,
                            copyEvent.sessionID,
                            copyEvent.copiedAt,
                            copyEvent.copiedVia.rawValue,
                            copyEvent.copiedBy.rawValue,
                        ]
                    )

                    updatedNotes.append(updatedNote)
                    copyEvents.append(copyEvent)
                }

                return StackExecutionResult(
                    notes: CardStackOrdering.sort(updatedNotes),
                    copyEvents: copyEvents.sorted { $0.copiedAt > $1.copiedAt }
                )
            }
        } catch {
            NSLog("StackExecutionService markExecuted failed: %@", error.localizedDescription)
            throw StackExecutionServiceError.saveFailed(error)
        }
    }

    private static func loadCardRecords(
        ids: [UUID],
        db: Database
    ) throws -> [String: StackExecutionCardRecord] {
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        let records = try StackExecutionCardRecord.fetchAll(
            db,
            sql: """
            SELECT *
            FROM \(PromptCueDatabaseSchema.cardsTableName)
            WHERE id IN (\(placeholders))
            """,
            arguments: StatementArguments(ids.map(\.uuidString))
        )

        return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }
}

private struct StackExecutionCardRecord: FetchableRecord, Decodable {
    let id: String
    let text: String
    let tagsJSON: String?
    let suggestedTargetJSON: String?
    let createdAt: Date
    let screenshotPath: String?
    let lastCopiedAt: Date?
    let sortOrder: Double

    var captureCard: CaptureCard {
        CaptureCard(
            id: UUID(uuidString: id) ?? UUID(),
            text: text,
            tags: CaptureTag.decodeJSONArray(tagsJSON),
            suggestedTarget: Self.decodeSuggestedTarget(suggestedTargetJSON),
            createdAt: createdAt,
            screenshotPath: screenshotPath,
            lastCopiedAt: lastCopiedAt,
            sortOrder: sortOrder
        )
    }

    private static func decodeSuggestedTarget(_ json: String?) -> CaptureSuggestedTarget? {
        guard let json,
              let data = json.data(using: .utf8),
              let target = try? JSONDecoder().decode(CaptureSuggestedTarget.self, from: data) else {
            return nil
        }

        return target
    }
}
