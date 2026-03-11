import Foundation
import GRDB
import PromptCueCore

enum CardStoreError: Error {
    case unavailable(underlying: Error?)
    case loadFailed(Error)
    case saveFailed(Error)
}

@MainActor
final class CardStore {
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

    func load() throws -> [CaptureCard] {
        guard let dbQueue = database.dbQueue else {
            throw CardStoreError.unavailable(underlying: database.setupError)
        }

        do {
            return try dbQueue.read { db in
                try CardRecord
                    .order(Column("sortOrder").desc)
                    .fetchAll(db)
                    .map(\.captureCard)
            }
        } catch {
            NSLog("CardStore load failed: %@", error.localizedDescription)
            throw CardStoreError.loadFailed(error)
        }
    }

    func save(_ cards: [CaptureCard]) throws {
        try replaceAll(cards)
    }

    func replaceAll(_ cards: [CaptureCard]) throws {
        guard let dbQueue = database.dbQueue else {
            throw CardStoreError.unavailable(underlying: database.setupError)
        }

        do {
            try dbQueue.write { db in
                try CardRecord.deleteAll(db)
                for card in cards {
                    try CardRecord(captureCard: card).insert(db)
                }
            }
        } catch {
            NSLog("CardStore save failed: %@", error.localizedDescription)
            throw CardStoreError.saveFailed(error)
        }
    }

    func upsert(_ card: CaptureCard) throws {
        try upsert([card])
    }

    func upsert(_ cards: [CaptureCard]) throws {
        guard let dbQueue = database.dbQueue else {
            throw CardStoreError.unavailable(underlying: database.setupError)
        }

        guard !cards.isEmpty else {
            return
        }

        do {
            try dbQueue.write { db in
                for card in cards {
                    try CardRecord(captureCard: card).upsert(db)
                }
            }
        } catch {
            NSLog("CardStore upsert failed: %@", error.localizedDescription)
            throw CardStoreError.saveFailed(error)
        }
    }

    func delete(id: UUID) throws {
        try delete(ids: [id])
    }

    func apply(upserts cards: [CaptureCard], deletions ids: [UUID]) throws {
        guard let dbQueue = database.dbQueue else {
            throw CardStoreError.unavailable(underlying: database.setupError)
        }

        guard !cards.isEmpty || !ids.isEmpty else {
            return
        }

        do {
            try dbQueue.write { db in
                if !ids.isEmpty {
                    let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
                    try db.execute(
                        sql: "DELETE FROM \(CardRecord.databaseTableName) WHERE id IN (\(placeholders))",
                        arguments: StatementArguments(ids.map(\.uuidString))
                    )
                }

                for card in cards {
                    try CardRecord(captureCard: card).upsert(db)
                }
            }
        } catch {
            NSLog("CardStore batch apply failed: %@", error.localizedDescription)
            throw CardStoreError.saveFailed(error)
        }
    }

    func delete(ids: [UUID]) throws {
        guard let dbQueue = database.dbQueue else {
            throw CardStoreError.unavailable(underlying: database.setupError)
        }

        guard !ids.isEmpty else {
            return
        }

        do {
            try dbQueue.write { db in
                let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
                try db.execute(
                    sql: "DELETE FROM \(CardRecord.databaseTableName) WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(ids.map(\.uuidString))
                )
            }
        } catch {
            NSLog("CardStore delete failed: %@", error.localizedDescription)
            throw CardStoreError.saveFailed(error)
        }
    }

    func allIDs() throws -> Set<UUID> {
        guard let dbQueue = database.dbQueue else {
            throw CardStoreError.unavailable(underlying: database.setupError)
        }

        do {
            return try dbQueue.read { db in
                let ids = try String.fetchAll(
                    db,
                    sql: "SELECT id FROM \(CardRecord.databaseTableName)"
                )
                return Set(ids.compactMap { UUID(uuidString: $0) })
            }
        } catch {
            NSLog("CardStore allIDs failed: %@", error.localizedDescription)
            throw CardStoreError.loadFailed(error)
        }
    }
}

private struct CardRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = PromptCueDatabaseSchema.cardsTableName

    let id: String
    let text: String
    let suggestedTargetJSON: String?
    let createdAt: Date
    let screenshotPath: String?
    let lastCopiedAt: Date?
    let sortOrder: Double

    init(captureCard: CaptureCard) {
        id = captureCard.id.uuidString
        text = captureCard.text
        suggestedTargetJSON = Self.encodeSuggestedTarget(captureCard.suggestedTarget)
        createdAt = captureCard.createdAt
        screenshotPath = captureCard.screenshotPath
        lastCopiedAt = captureCard.lastCopiedAt
        sortOrder = captureCard.sortOrder
    }

    var captureCard: CaptureCard {
        CaptureCard(
            id: UUID(uuidString: id) ?? UUID(),
            text: text,
            suggestedTarget: Self.decodeSuggestedTarget(suggestedTargetJSON),
            createdAt: createdAt,
            screenshotPath: screenshotPath,
            lastCopiedAt: lastCopiedAt,
            sortOrder: sortOrder
        )
    }

    private static func encodeSuggestedTarget(_ target: CaptureSuggestedTarget?) -> String? {
        guard let target,
              let data = try? JSONEncoder().encode(target) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
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
