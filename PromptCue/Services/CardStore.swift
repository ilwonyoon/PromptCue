import Foundation
import GRDB

@MainActor
final class CardStore {
    private let dbQueue: DatabaseQueue?

    init(fileManager: FileManager = .default) {
        let databaseURL = Self.databaseURL(fileManager: fileManager)

        do {
            try fileManager.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let queue = try DatabaseQueue(path: databaseURL.path)
            var migrator = DatabaseMigrator()
            migrator.registerMigration("createCards") { db in
                try db.create(table: CardRecord.databaseTableName) { table in
                    table.column("id", .text).notNull().primaryKey()
                    table.column("text", .text).notNull()
                    table.column("createdAt", .datetime).notNull()
                    table.column("screenshotPath", .text)
                }
            }
            migrator.registerMigration("addLastCopiedAt") { db in
                try db.alter(table: CardRecord.databaseTableName) { table in
                    table.add(column: "lastCopiedAt", .datetime)
                }
            }
            try migrator.migrate(queue)
            dbQueue = queue
        } catch {
            dbQueue = nil
            NSLog("CardStore setup failed: %@", error.localizedDescription)
        }
    }

    func load() -> [CaptureCard] {
        guard let dbQueue else {
            return []
        }

        do {
            return try dbQueue.read { db in
                try CardRecord
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
                    .map(\.captureCard)
            }
        } catch {
            NSLog("CardStore load failed: %@", error.localizedDescription)
            return []
        }
    }

    func save(_ cards: [CaptureCard]) {
        guard let dbQueue else {
            return
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
        }
    }

    private static func databaseURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return baseDirectory
            .appendingPathComponent("PromptCue", isDirectory: true)
            .appendingPathComponent("PromptCue.sqlite", isDirectory: false)
    }
}

private struct CardRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cards"

    let id: String
    let text: String
    let createdAt: Date
    let screenshotPath: String?
    let lastCopiedAt: Date?

    init(captureCard: CaptureCard) {
        id = captureCard.id.uuidString
        text = captureCard.text
        createdAt = captureCard.createdAt
        screenshotPath = captureCard.screenshotPath
        lastCopiedAt = captureCard.lastCopiedAt
    }

    var captureCard: CaptureCard {
        CaptureCard(
            id: UUID(uuidString: id) ?? UUID(),
            text: text,
            createdAt: createdAt,
            screenshotPath: screenshotPath,
            lastCopiedAt: lastCopiedAt
        )
    }
}
