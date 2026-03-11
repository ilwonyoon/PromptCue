import Foundation
import PromptCueCore

enum StackReadScope {
    case all
    case active
    case copied

    func matches(_ card: CaptureCard) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return card.isCopied == false
        case .copied:
            return card.isCopied
        }
    }
}

struct StackNoteDetail: Equatable {
    let note: CaptureCard
    let copyEvents: [CopyEvent]
}

@MainActor
final class StackReadService {
    private let cardStore: CardStore
    private let copyEventStore: CopyEventStore

    init(
        cardStore: CardStore,
        copyEventStore: CopyEventStore
    ) {
        self.cardStore = cardStore
        self.copyEventStore = copyEventStore
    }

    convenience init(
        fileManager: FileManager = .default,
        databaseURL: URL? = nil
    ) {
        let database = PromptCueDatabase(fileManager: fileManager, databaseURL: databaseURL)
        self.init(
            cardStore: CardStore(database: database),
            copyEventStore: CopyEventStore(database: database)
        )
    }

    func listNotes(scope: StackReadScope = .all) throws -> [CaptureCard] {
        let cards = CardStackOrdering.sort(try cardStore.load())
        return cards.filter(scope.matches(_:))
    }

    func note(id: UUID) throws -> CaptureCard? {
        try listNotes().first(where: { $0.id == id })
    }

    func noteDetail(id: UUID) throws -> StackNoteDetail? {
        guard let note = try note(id: id) else {
            return nil
        }

        return StackNoteDetail(
            note: note,
            copyEvents: try copyEventStore.loadCopyEvents(for: id)
        )
    }
}
